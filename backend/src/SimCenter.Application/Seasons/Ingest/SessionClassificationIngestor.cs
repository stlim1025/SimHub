using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using SimCenter.Application.Common;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Telemetry;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using SimCenter.Domain.Seasons;

namespace SimCenter.Application.Seasons.Ingest;

/// <summary>
/// <c>SessionClassified</c> 처리기(12 §6.2). 처리 순서: 파싱 → 검증 → Time Trial → 트랙 매핑 → 분류 시각 → 세션 찾기 → 늦은 결과 →
/// 시즌·주말 업서트 → 세션 생성·갱신.
/// <para>
/// <b>불변식:</b> 1~7단계(늦은 결과 판정까지)는 아무것도 추가·수정하지 않는다. Reject는 파싱·검증·트랙 매핑에서만 나온다.
/// 그래서 Reject 경로의 <c>SaveChanges</c>(LastSeen)가 반쯤 만든 그래프를 저장하는 일이 없다.
/// </para>
/// 변경은 추적만 하고 저장하지 않는다 — 커밋은 호출자(<c>TelemetryIngestService</c>)가 멱등 기록과 함께 1회 한다.
/// </summary>
public sealed class SessionClassificationIngestor : ISessionClassificationIngestor
{
    /// <summary>Agent 시계가 서버보다 앞서 있어도 이후 재분류가 막히지 않도록, 분류 시각의 상한을 서버 시각보다 이만큼만 허용한다.</summary>
    public static readonly TimeSpan MaxClockSkew = TimeSpan.FromMinutes(5);

    private const char NulCharacter = '\0';
    private const string ParseFailedReason ="SessionClassified payload 파싱 실패";
    private const string EmptyPayloadReason = "SessionClassified payload가 비어 있습니다.";
    private const string ValidationFailedPrefix = "SessionClassified 검증 실패: ";
    private const string TimeTrialIgnoredReason = "Time Trial 세션은 저장하지 않습니다(D-30).";
    private const string KeyConflictIgnoredReason = "같은 세션 UID로 트랙 또는 세션 종류가 다른 결과가 이미 있습니다.";
    private const string OutdatedIgnoredReason = "저장된 결과보다 이른 순위표입니다.";

    private static readonly JsonSerializerOptions PayloadOptions = new(JsonSerializerDefaults.Web);

    private readonly ISeasonRepository _seasons;
    private readonly IGameSessionRepository _sessions;
    private readonly ITrackRepository _tracks;
    private readonly IIdGenerator _idGenerator;
    private readonly ILogger<SessionClassificationIngestor> _logger;

    public SessionClassificationIngestor(
        ISeasonRepository seasons,
        IGameSessionRepository sessions,
        ITrackRepository tracks,
        IIdGenerator idGenerator,
        ILogger<SessionClassificationIngestor> logger)
    {
        _seasons = seasons;
        _sessions = sessions;
        _tracks = tracks;
        _idGenerator = idGenerator;
        _logger = logger;
    }

    public async Task<ClassificationOutcome> ApplyAsync(
        TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, CancellationToken cancellationToken = default)
    {
        // 1~2. 파싱(구조만) → 검증. 영구 무효는 Reject.
        if (!TryReadPayload(envelope, out var payload, out var rejection))
        {
            return rejection;
        }

        var classification = new ClassificationKinds(
            LenientEnum.Parse<SessionType>(payload.SessionType),
            LenientEnum.Parse<SessionKind>(payload.SessionKind),
            LenientEnum.Parse<GameMode>(payload.GameMode));

        // 3. Time Trial은 Laps·Leaderboard 담당(D-30) — 저장하지 않고 Ack한다.
        if (classification.SessionType == SessionType.TimeTrial || classification.GameMode == GameMode.TimeTrial)
        {
            return Ignore(device, payload, TimeTrialIgnoredReason);
        }

        // 4. 트랙 매핑. 없으면 영구 무효(시드 누락) → Reject(랩과 같은 문구).
        var track = await _tracks.GetByGameTrackIdAsync(envelope.GameCode, payload.TrackId, cancellationToken);
        if (track is null)
        {
            _logger.LogWarning("Track 매핑 없음 gameCode={GameCode} trackId={TrackId} eventId={EventId}",
                envelope.GameCode, payload.TrackId, envelope.EventId);
            return new ClassificationOutcome.Rejected($"트랙 매핑 없음(gameCode={envelope.GameCode}, trackId={payload.TrackId})");
        }

        // 5. 분류 시각.
        var request = new StoreRequest(
            device, envelope.GameCode, payload, classification, track, ResolveClassifiedAt(envelope.OccurredAt, now), now);

        return await StoreAsync(request, cancellationToken);
    }

    /// <summary>6~9단계: 세션 찾기 → 늦은 결과 → 시즌·주말 업서트 → 세션 생성·갱신.</summary>
    private async Task<ClassificationOutcome> StoreAsync(StoreRequest request, CancellationToken cancellationToken)
    {
        // 6. 세션 찾기(트랙·종류가 다르면 uid 키로 대체).
        var target = await ResolveTargetAsync(request, cancellationToken);
        if (target.Unresolvable)
        {
            return Ignore(request.Device, request.Payload, KeyConflictIgnoredReason);
        }

        // 7. 늦은 결과.
        if (target.Existing is { } stored && request.ClassifiedAt < stored.ClassifiedAt)
        {
            return Ignore(request.Device, request.Payload, OutdatedIgnoredReason);
        }

        // 이 아래부터 변경을 추적한다. Reject는 더 이상 나오지 않는다.
        // 8. 시즌·주말 업서트.
        var membership = target.JoinsSeason ? await UpsertSeasonAndWeekendAsync(request, cancellationToken) : null;

        // 9. 세션 생성·갱신.
        var isNew = target.Existing is null;
        if (target.Existing is null)
        {
            await CreateSessionAsync(request, target.SessionKey, membership, cancellationToken);
        }
        else
        {
            MergeIntoExisting(target.Existing, request, membership);
        }

        _logger.LogInformation(
            "세션 결과 저장 device={Device} user={User} sessionKey={SessionKey} track={Track} results={Results} stored={Mode}",
            request.Device.Id, request.Device.UserId, target.SessionKey, request.Track.Name, request.Results.Count, isNew ? "신규" : "병합");

        return new ClassificationOutcome.Stored(target.SessionKey, isNew);
    }

    /// <summary>payload를 해석·검증한다. 실패하면 false와 Reject 결과를 돌려준다.</summary>
    private bool TryReadPayload(
        TelemetryEnvelopeDto envelope,
        [NotNullWhen(true)] out SessionClassifiedPayloadDto? payload,
        [NotNullWhen(false)] out ClassificationOutcome.Rejected? rejection)
    {
        payload = null;
        rejection = null;

        switch (envelope.Payload.ValueKind)
        {
            case JsonValueKind.Undefined or JsonValueKind.Null:
                rejection = new ClassificationOutcome.Rejected(EmptyPayloadReason);
                return false;
            case JsonValueKind.Object:
                break;
            default:
                _logger.LogWarning("SessionClassified payload가 객체가 아님 eventId={EventId} kind={Kind}", envelope.EventId, envelope.Payload.ValueKind);
                rejection = new ClassificationOutcome.Rejected(ParseFailedReason);
                return false;
        }

        try
        {
            payload = envelope.Payload.Deserialize<SessionClassifiedPayloadDto>(PayloadOptions);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "SessionClassified payload 파싱 실패 eventId={EventId}", envelope.EventId);
            rejection = new ClassificationOutcome.Rejected(ParseFailedReason);
            return false;
        }

        if (payload is null)
        {
            rejection = new ClassificationOutcome.Rejected(EmptyPayloadReason);
            return false;
        }

        var validationError = SessionClassificationValidator.Validate(payload);
        if (validationError is not null)
        {
            _logger.LogWarning("SessionClassified 검증 실패 eventId={EventId} detail={Detail}", envelope.EventId, validationError);
            rejection = new ClassificationOutcome.Rejected(ValidationFailedPrefix + validationError);
            payload = null;
            return false;
        }

        return true;
    }

    private ClassificationOutcome Ignore(AgentDevice device, SessionClassifiedPayloadDto payload, string reason)
    {
        _logger.LogInformation(
            "세션 결과 무시 device={Device} user={User} sessionRef={SessionRef} reason={Reason}",
            device.Id, device.UserId, payload.SessionRef, reason);
        return new ClassificationOutcome.Ignored(reason);
    }

    /// <summary><c>min(occurredAt, now + MaxClockSkew)</c>. Npgsql이 거부하지 않도록 항상 Utc로 맞춘다.</summary>
    private static DateTime ResolveClassifiedAt(DateTime occurredAt, DateTime now)
    {
        var occurredUtc = occurredAt.Kind switch
        {
            DateTimeKind.Utc => occurredAt,
            DateTimeKind.Local => occurredAt.ToUniversalTime(),
            _ => DateTime.SpecifyKind(occurredAt, DateTimeKind.Utc),
        };

        var latestAllowed = DateTime.SpecifyKind(now + MaxClockSkew, DateTimeKind.Utc);
        return occurredUtc < latestAllowed ? occurredUtc : latestAllowed;
    }

    /// <summary>
    /// 세션 키로 기존 세션을 찾는다(D-29). 찾은 세션의 트랙 또는 세션 종류가 다르면 경고를 남기고
    /// 키를 <c>uid:{sessionRef}</c>로 바꿔 다시 찾으며, 이 세션은 시즌·주말에 넣지 않는다.
    /// </summary>
    private async Task<SessionTarget> ResolveTargetAsync(StoreRequest request, CancellationToken cancellationToken)
    {
        var payload = request.Payload;
        var mode = request.Classification.GameMode;
        var userId = request.Device.UserId;
        var key = SessionKeys.For(mode, payload.SeasonLinkId, payload.WeekendLinkId, payload.SessionLinkId, payload.SessionRef);

        var existing = await _sessions.GetByKeyWithResultsAsync(userId, request.GameCode, key, cancellationToken);
        if (existing is null || IsSameSession(existing, request))
        {
            return new SessionTarget(key, existing, SeasonPolicy.BelongsToSeason(mode, payload.SeasonLinkId, payload.WeekendLinkId), Unresolvable: false);
        }

        _logger.LogWarning(
            "세션 키 충돌: 트랙 또는 종류가 다름 → uid 키로 대체 sessionKey={SessionKey} sessionRef={SessionRef} " +
            "storedTrack={StoredTrack} track={Track} storedKind={StoredKind} kind={Kind}",
            key, payload.SessionRef, existing.TrackId, request.Track.Id, existing.SessionKind, request.Classification.SessionKind);

        var uidKey = SessionKeys.Uid(payload.SessionRef);
        var uidExisting = await _sessions.GetByKeyWithResultsAsync(userId, request.GameCode, uidKey, cancellationToken);
        var stillConflicting = uidExisting is not null && !IsSameSession(uidExisting, request);
        return new SessionTarget(uidKey, uidExisting, JoinsSeason: false, Unresolvable: stillConflicting);
    }

    private static bool IsSameSession(GameSession stored, StoreRequest request)
        => stored.TrackId == request.Track.Id && stored.SessionKind == request.Classification.SessionKind;

    /// <summary>
    /// 시즌을 <c>(UserId, GameCode, SeasonLinkId)</c>로, 주말을 <c>(SeasonId, WeekendLinkId)</c>로 찾거나 만든다.
    /// 새로 만들 때는 첫·마지막 시각을 분류 시각으로 직접 채운다 — <c>Touch</c>는 이미 채워진 범위만 넓힌다.
    /// </summary>
    private async Task<SeasonMembership> UpsertSeasonAndWeekendAsync(StoreRequest request, CancellationToken cancellationToken)
    {
        var payload = request.Payload;
        var season = await _seasons.GetByLinkAsync(request.Device.UserId, request.GameCode, payload.SeasonLinkId, cancellationToken);
        if (season is null)
        {
            season = new Season
            {
                Id = _idGenerator.NewId(),
                UserId = request.Device.UserId,
                GameCode = request.GameCode,
                SeasonLinkId = payload.SeasonLinkId,
                GameMode = request.Classification.GameMode,
                FirstSessionAt = request.ClassifiedAt,
                LastSessionAt = request.ClassifiedAt,
                CreatedAt = request.Now,
            };
            await _seasons.AddAsync(season, cancellationToken);
        }
        else
        {
            season.Touch(request.ClassifiedAt, request.Now);
        }

        var weekend = await _seasons.GetWeekendAsync(season.Id, payload.WeekendLinkId, cancellationToken);
        if (weekend is null)
        {
            weekend = new RaceWeekend
            {
                Id = _idGenerator.NewId(),
                SeasonId = season.Id,
                WeekendLinkId = payload.WeekendLinkId,
                TrackId = request.Track.Id,
                FirstSessionAt = request.ClassifiedAt,
                CreatedAt = request.Now,
            };
            await _seasons.AddWeekendAsync(weekend, cancellationToken);
        }
        else
        {
            weekend.Touch(request.ClassifiedAt, request.Now);
        }

        return new SeasonMembership(season.Id, weekend.Id);
    }

    private async Task CreateSessionAsync(
        StoreRequest request, string sessionKey, SeasonMembership? membership, CancellationToken cancellationToken)
    {
        var sessionId = _idGenerator.NewId();
        var session = new GameSession
        {
            Id = sessionId,
            UserId = request.Device.UserId,
            AgentDeviceId = request.Device.Id,
            SeasonId = membership?.SeasonId,
            RaceWeekendId = membership?.RaceWeekendId,
            GameCode = request.GameCode,
            SessionKey = sessionKey,
            SeasonLinkId = request.Payload.SeasonLinkId,
            WeekendLinkId = request.Payload.WeekendLinkId,
            SessionLinkId = request.Payload.SessionLinkId,
            SessionRef = request.Payload.SessionRef,
            TrackId = request.Track.Id,
            SessionType = request.Classification.SessionType,
            SessionKind = request.Classification.SessionKind,
            GameMode = request.Classification.GameMode,
            TotalLaps = request.Payload.TotalLaps,
            AiDifficulty = request.Payload.AiDifficulty,
            IsNetworkGame = request.Payload.IsNetworkGame,
            ClassifiedAt = request.ClassifiedAt,
            CreatedAt = request.Now,
            Results = BuildResults(sessionId, request),
        };

        await _sessions.AddAsync(session, cancellationToken);
    }

    /// <summary>
    /// 같은 키의 기존 세션을 최신 결과로 갱신한다. 세션 필드를 덮어쓰고 결과는 carIndex별로 병합한다(<see cref="GameSession.ReplaceResults"/>).
    /// 트랙·종류는 같다고 확인된 세션이라 바꾸지 않는다. 시즌 소속은 이번 순위표가 시즌 대상일 때만 다시 맞춘다.
    /// </summary>
    private void MergeIntoExisting(GameSession existing, StoreRequest request, SeasonMembership? membership)
    {
        existing.SessionRef = request.Payload.SessionRef;
        existing.AgentDeviceId = request.Device.Id;
        existing.ClassifiedAt = request.ClassifiedAt;
        existing.SessionType = request.Classification.SessionType;
        existing.GameMode = request.Classification.GameMode;
        existing.SeasonLinkId = request.Payload.SeasonLinkId;
        existing.WeekendLinkId = request.Payload.WeekendLinkId;
        existing.SessionLinkId = request.Payload.SessionLinkId;
        existing.TotalLaps = request.Payload.TotalLaps;
        existing.AiDifficulty = request.Payload.AiDifficulty;
        existing.IsNetworkGame = request.Payload.IsNetworkGame;
        existing.UpdatedAt = request.Now;

        if (membership is not null)
        {
            existing.SeasonId = membership.SeasonId;
            existing.RaceWeekendId = membership.RaceWeekendId;
        }

        existing.ReplaceResults(BuildResults(existing.Id, request), request.Now);
    }

    /// <summary>
    /// 결과 행과 스틴트를 만든다(스틴트 번호는 1부터). 만든 행은 새 세션의 <c>Results</c>로 붙이거나
    /// <see cref="GameSession.ReplaceResults"/>에 넘기는 용도로만 쓴다 — 저장소에 따로 추가하지 않는다.
    /// </summary>
    private List<SessionResult> BuildResults(Guid gameSessionId, StoreRequest request)
    {
        var results = new List<SessionResult>(request.Results.Count);
        foreach (var dto in request.Results)
        {
            var driverName = NormalizeText(dto.DriverName);
            var resultId = _idGenerator.NewId();
            results.Add(new SessionResult
            {
                Id = resultId,
                GameSessionId = gameSessionId,
                CarIndex = dto.CarIndex,
                Position = dto.Position,
                GridPosition = dto.GridPosition,
                NumLaps = dto.NumLaps,
                Points = dto.Points,
                NumPitStops = dto.NumPitStops,
                NumPenalties = dto.NumPenalties,
                ResultStatus = LenientEnum.Parse<ResultStatus>(dto.ResultStatus),
                BestLapTimeMs = dto.BestLapTimeMs,
                TotalRaceTimeMs = dto.TotalRaceTimeMs,
                PenaltiesTimeMs = dto.PenaltiesTimeMs,
                DriverKey = DriverKeys.Build(
                    dto.IsPlayer, dto.GameDriverId, driverName, dto.RaceNumber, request.Payload.SessionRef, dto.CarIndex),
                DriverName = driverName,
                GameDriverId = dto.GameDriverId,
                TeamId = dto.TeamId,
                RaceNumber = dto.RaceNumber,
                IsAiControlled = dto.IsAiControlled,
                IsPlayer = dto.IsPlayer,
                CreatedAt = request.Now,
                TyreStints = BuildStints(resultId, dto.TyreStints, request.Now),
            });
        }

        return results;
    }

    private List<SessionResultTyreStint> BuildStints(Guid resultId, IReadOnlyList<TyreStintDto>? stints, DateTime now)
    {
        var built = new List<SessionResultTyreStint>(stints?.Count ?? 0);
        if (stints is null)
        {
            return built;
        }

        for (var i = 0; i < stints.Count; i++)
        {
            built.Add(new SessionResultTyreStint
            {
                Id = _idGenerator.NewId(),
                SessionResultId = resultId,
                StintNumber = i + 1,
                EndLap = stints[i].EndLap,
                VisualCompound = LenientEnum.Parse<TyreCompound>(stints[i].VisualCompound),
                ActualCompound = NormalizeText(stints[i].ActualCompound),
                CreatedAt = now,
            });
        }

        return built;
    }

    /// <summary>
    /// 첫 NUL(<c>\0</c>)부터 잘라 내고(UDP 고정 길이 문자열의 NUL 패딩이 정상 형태이고, PostgreSQL 텍스트는 NUL을 저장하지 못한다)
    /// 앞뒤 공백을 지운다. 비면 null(드라이버 이름이 비면 표시는 <c>Car {carIndex + 1}</c>).
    /// </summary>
    private static string? NormalizeText(string? value)
    {
        if (value is null)
        {
            return null;
        }

        var nulIndex = value.IndexOf(NulCharacter);
        var trimmed = (nulIndex >= 0 ? value[..nulIndex] : value).Trim();
        return trimmed.Length == 0 ? null : trimmed;
    }

    /// <summary>문자열로 받은 enum 필드의 해석 결과.</summary>
    private readonly record struct ClassificationKinds(SessionType SessionType, SessionKind SessionKind, GameMode GameMode);

    /// <summary>세션 찾기 결과. <paramref name="Unresolvable"/>이면 대체 키로도 같은 세션이 아닌 세션과 겹쳐 저장할 곳이 없다.</summary>
    private sealed record SessionTarget(string SessionKey, GameSession? Existing, bool JoinsSeason, bool Unresolvable);

    private sealed record SeasonMembership(Guid SeasonId, Guid RaceWeekendId);

    /// <summary>4단계를 통과한 뒤 저장 단계들이 함께 쓰는 입력 묶음.</summary>
    private sealed record StoreRequest(
        AgentDevice Device,
        string GameCode,
        SessionClassifiedPayloadDto Payload,
        ClassificationKinds Classification,
        Track Track,
        DateTime ClassifiedAt,
        DateTime Now)
    {
        /// <summary>검증을 통과했으므로 null이 아니다.</summary>
        public IReadOnlyList<ClassifiedResultDto> Results => Payload.Results!;
    }
}
