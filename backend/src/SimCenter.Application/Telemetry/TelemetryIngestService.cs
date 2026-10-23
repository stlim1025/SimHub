using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using SimCenter.Application.Common;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Laps.Ingest;
using SimCenter.Application.Rankings;
using SimCenter.Application.Rankings.Notifications;
using SimCenter.Application.Seasons.Ingest;
using SimCenter.Application.TrackSamples;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using SimCenter.Domain.Seasons;

namespace SimCenter.Application.Telemetry;

/// <summary>
/// 텔레메트리 인입 유스케이스(11 §5, 12 §6.1). <c>LapFinished</c>(랩)·<c>SessionClassified</c>(세션 최종 순위표)·<c>TrackSamplesChunk</c>(트랙 형상 표본)만 영속화하고
/// 나머지 이벤트는 Ack만 한다(YAGNI).
/// 공통 단계: 멱등 → 장치 확인 → LastSeenAt. 이어서 유형별로 갈린다:
/// <list type="bullet">
/// <item><c>LapFinished</c>: payload 파싱 → 트랙 매핑 → 스냅샷·트레이스(틀리면 그 부분만 버림, 15 §5) → 랭킹 적격 → PB
/// → 저장(랩 + 스냅샷 + 트레이스 + 멱등 기록 한 커밋) → 브로드캐스트.</item>
/// <item><c>SessionClassified</c>: <see cref="ISessionClassificationIngestor"/>가 변경을 추적만 하고, Stored·Ignored면 멱등 기록을 더해
/// 커밋 1회(결과 저장과 멱등 기록이 한 트랜잭션)로 Ack. Rejected는 LastSeenAt만 저장하고 Reject.</item>
/// </list>
/// 랩과 결과는 연결된 장치의 주인에게 귀속한다(D-25). 해제된 장치·영구 무효(파싱/검증/트랙 실패)는 Reject.
/// </summary>
public sealed class TelemetryIngestService : ITelemetryIngestService
{
    /// <summary>장치가 없거나 연결 해제된 경우의 Reject 사유(Agent가 그대로 기록한다).</summary>
    public const string RevokedDeviceReason = "연결이 해제된 장치입니다.";

    /// <summary>세션 최종 순위표 이벤트 유형(12 §5.5).</summary>
    public const string SessionClassifiedType = "SessionClassified";

    /// <summary>트랙 형상 표본 조각 이벤트 유형(헌장 Agent Rules 예외).</summary>
    public const string TrackSamplesChunkType = "TrackSamplesChunk";

    /// <summary>
    /// <see cref="AgentDevice.LastSeenAt"/> 쓰기 최소 간격. 이벤트마다 장치 행을 갱신하지 않도록,
    /// 값이 없거나 이 간격 이상 지났을 때만 기록한다.
    /// </summary>
    public static readonly TimeSpan LastSeenWriteInterval = TimeSpan.FromMinutes(1);

    private const string LapFinishedType = "LapFinished";

    /// <summary>PostgreSQL 텍스트 열은 NUL(0x00)을 저장하지 못한다(22021).</summary>
    private const char NulCharacter = '\0';

    private static readonly JsonSerializerOptions PayloadOptions = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly IProcessedEventRepository _processed;
    private readonly IAgentDeviceRepository _devices;
    private readonly ITrackRepository _tracks;
    private readonly ILapRepository _laps;
    private readonly ISessionClassificationIngestor _classification;
    private readonly ITrackSamplesIngestor _trackSamples;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IIdGenerator _idGenerator;
    private readonly IClock _clock;
    private readonly IRankingService _ranking;
    private readonly IRankingNotifier _notifier;
    private readonly ILapQueryRepository _lapQueries;
    private readonly LapDetailExtractor _lapDetails;
    private readonly ILogger<TelemetryIngestService> _logger;

    public TelemetryIngestService(
        IProcessedEventRepository processed,
        IAgentDeviceRepository devices,
        ITrackRepository tracks,
        ILapRepository laps,
        ISessionClassificationIngestor classification,
        ITrackSamplesIngestor trackSamples,
        IUnitOfWork unitOfWork,
        IIdGenerator idGenerator,
        IClock clock,
        IRankingService ranking,
        IRankingNotifier notifier,
        ILapQueryRepository lapQueries,
        LapDetailExtractor lapDetails,
        ILogger<TelemetryIngestService> logger)
    {
        _processed = processed;
        _devices = devices;
        _tracks = tracks;
        _laps = laps;
        _classification = classification;
        _trackSamples = trackSamples;
        _unitOfWork = unitOfWork;
        _idGenerator = idGenerator;
        _clock = clock;
        _ranking = ranking;
        _notifier = notifier;
        _lapQueries = lapQueries;
        _lapDetails = lapDetails;
        _logger = logger;
    }

    public async Task<IngestResult> IngestAsync(TelemetryEnvelopeDto envelope, Guid authenticatedDeviceId, CancellationToken cancellationToken = default)
    {
        // 1. 멱등: 이미 처리한 eventId면 즉시 Ack(effectively-once). 해제 전에 처리된 이벤트의 재전송도 Ack로 끝난다.
        if (await _processed.ExistsAsync(envelope.EventId, cancellationToken))
        {
            return IngestResult.Ack();
        }

        // 2. 장치 확인: 연결 후 해제됐을 수 있으므로 이벤트마다 다시 조회한다(이미 열린 연결로 계속 보내는 것을 막는다).
        var device = await _devices.GetByIdAsync(authenticatedDeviceId, cancellationToken);
        if (device is null)
        {
            _logger.LogWarning("없거나 연결 해제된 장치의 이벤트 device={Device} eventId={EventId}", authenticatedDeviceId, envelope.EventId);
            return IngestResult.Reject(RevokedDeviceReason);
        }

        // 3. 마지막 수신 시각(모든 유형). 실제 저장은 아래 반환 경로에서 한 번만 한다.
        var now = _clock.UtcNow;
        var lastSeenChanged = TouchLastSeen(device, now);

        // 4. 유형별 처리. LapFinished·SessionClassified·TrackSamplesChunk만 저장하고, 그 외 유효 이벤트는 무시하되 Ack.
        switch (envelope.Type)
        {
            case LapFinishedType:
                return await IngestLapFinishedAsync(envelope, device, now, lastSeenChanged, cancellationToken);
            case SessionClassifiedType:
                return await IngestSessionClassifiedAsync(envelope, device, now, lastSeenChanged, cancellationToken);
            case TrackSamplesChunkType:
                return await IngestTrackSamplesAsync(envelope, device, now, lastSeenChanged, cancellationToken);
            default:
                _logger.LogDebug("비저장 이벤트 {Type} device={Device} eventId={EventId}", envelope.Type, device.Id, envelope.EventId);
                return await FinishWithoutLapAsync(IngestResult.Ack(), lastSeenChanged, cancellationToken);
        }
    }

    /// <summary>
    /// <see cref="AgentDevice.LastSeenAt"/>이 없거나 <see cref="LastSeenWriteInterval"/> 이상 지났으면 지금 시각으로 바꾼다.
    /// </summary>
    /// <returns>값을 바꿨으면 true(저장 필요).</returns>
    private static bool TouchLastSeen(AgentDevice device, DateTime now)
    {
        if (device.LastSeenAt is { } lastSeen && now - lastSeen < LastSeenWriteInterval)
        {
            return false;
        }

        device.LastSeenAt = now;
        return true;
    }

    /// <summary>
    /// 랩·세션 결과를 저장하지 않는 반환 경로(무시하는 이벤트, 영구 무효 Reject). LastSeenAt이 바뀌었을 때만 한 번 저장한다.
    /// 호출 시점에 랩·결과 변경이 추적되어 있지 않다는 것이 전제다(<see cref="ISessionClassificationIngestor"/>의 Rejected 불변식).
    /// </summary>
    private async Task<IngestResult> FinishWithoutLapAsync(IngestResult result, bool lastSeenChanged, CancellationToken cancellationToken)
    {
        if (lastSeenChanged)
        {
            await _unitOfWork.SaveChangesAsync(cancellationToken);
        }

        return result;
    }

    /// <summary>멱등 기록을 추적에 더한다(저장은 호출자의 커밋과 함께).</summary>
    private Task AddProcessedEventAsync(TelemetryEnvelopeDto envelope, DateTime now, CancellationToken cancellationToken)
        => _processed.AddAsync(new ProcessedEvent
        {
            EventId = envelope.EventId,
            EventType = envelope.Type,
            ProcessedAt = now,
        }, cancellationToken);

    /// <summary>
    /// <c>SessionClassified</c>: 처리기가 변경을 추적한 뒤, Stored·Ignored면 멱등 기록을 더해 한 번에 커밋하고 Ack(12 §6.1).
    /// Rejected는 영구 무효 — 처리기는 아무것도 추적하지 않았으므로 LastSeenAt만 저장하고 Reject.
    /// </summary>
    private async Task<IngestResult> IngestSessionClassifiedAsync(
        TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, bool lastSeenChanged, CancellationToken cancellationToken)
    {
        var outcome = await _classification.ApplyAsync(envelope, device, now, cancellationToken);

        if (outcome is ClassificationOutcome.Rejected rejected)
        {
            return await FinishWithoutLapAsync(IngestResult.Reject(rejected.Reason), lastSeenChanged, cancellationToken);
        }

        await AddProcessedEventAsync(envelope, now, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return IngestResult.Ack();
    }

    /// <summary>
    /// <c>TrackSamplesChunk</c>: 처리기가 새 조각을 추적하면(이미 받은 조각이면 추적 없음) 멱등 기록을 더해 한 번에 커밋하고 Ack.
    /// 거부는 영구 무효 — 처리기는 아무것도 추적하지 않았으므로 LastSeenAt만 저장하고 Reject.
    /// </summary>
    private async Task<IngestResult> IngestTrackSamplesAsync(
        TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, bool lastSeenChanged, CancellationToken cancellationToken)
    {
        var rejectReason = await _trackSamples.ApplyAsync(envelope, device, now, cancellationToken);
        if (rejectReason is not null)
        {
            return await FinishWithoutLapAsync(IngestResult.Reject(rejectReason), lastSeenChanged, cancellationToken);
        }

        await AddProcessedEventAsync(envelope, now, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);
        return IngestResult.Ack();
    }

    /// <summary>LapFinished payload 파싱(실패는 영구 무효 → Reject) 후 랩 저장 경로로 이어간다.</summary>
    private async Task<IngestResult> IngestLapFinishedAsync(
        TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, bool lastSeenChanged, CancellationToken cancellationToken)
    {
        var payload = TryParseLapFinished(envelope, out var parseError);
        if (payload is null)
        {
            return await FinishWithoutLapAsync(IngestResult.Reject(parseError), lastSeenChanged, cancellationToken);
        }

        return await IngestLapAsync(envelope, payload, device, now, lastSeenChanged, cancellationToken);
    }

    /// <summary>LapFinished payload를 해석한다. 실패하면 null과 Reject 사유를 돌려준다.</summary>
    private LapFinishedPayloadDto? TryParseLapFinished(TelemetryEnvelopeDto envelope, out string rejectReason)
    {
        try
        {
            var payload = envelope.Payload.Deserialize<LapFinishedPayloadDto>(PayloadOptions);
            rejectReason = payload is null ? "LapFinished payload가 비어 있습니다." : string.Empty;
            return payload;
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "LapFinished payload 파싱 실패 eventId={EventId}", envelope.EventId);
            rejectReason = "LapFinished payload 파싱 실패";
            return null;
        }
    }

    /// <summary>트랙 매핑 → 스냅샷·트레이스 → 랭킹 적격 → PB 판정 → 저장(랩 + 트레이스 + 멱등 기록 + LastSeenAt 한 커밋) → 브로드캐스트.</summary>
    private async Task<IngestResult> IngestLapAsync(
        TelemetryEnvelopeDto envelope, LapFinishedPayloadDto payload, AgentDevice device, DateTime now, bool lastSeenChanged,
        CancellationToken cancellationToken)
    {
        // 5-1. 게임 에디션: 옛 Agent가 F1 25로 보낸 2026 시즌팩 랩(차량 팀이 2026 팀)은 F1 26으로 저장한다.
        //      이후 트랙 매핑·랩 GameCode·PB·랭킹 브로드캐스트가 모두 이 코드를 쓴다.
        envelope = envelope with { GameCode = GameEditionResolver.ForLap(envelope.GameCode, payload.Car) };

        // 6. Track 매핑. 없으면 영구 무효(시드 누락) → Reject.
        var track = await _tracks.GetByGameTrackIdAsync(envelope.GameCode, payload.TrackId, cancellationToken);
        if (track is null)
        {
            _logger.LogWarning("Track 매핑 없음 gameCode={GameCode} trackId={TrackId} eventId={EventId}",
                envelope.GameCode, payload.TrackId, envelope.EventId);
            return await FinishWithoutLapAsync(
                IngestResult.Reject($"트랙 매핑 없음(gameCode={envelope.GameCode}, trackId={payload.TrackId})"),
                lastSeenChanged, cancellationToken);
        }

        var lap = CreateLap(envelope, payload, device, track.Id, now);

        // 6-1. 스냅샷·트레이스(D-44, D-45): 틀린 부분만 버리고 경고 — 랩은 그대로 저장한다.
        lap.Snapshot = _lapDetails.BuildSnapshot(envelope.EventId, payload.Car, payload.Conditions, lap.Id, now);
        var trace = _lapDetails.BuildTrace(envelope.EventId, payload.Trace, lap.Id, now);

        // 7. PB 판정: 저장 커밋 전에 이전 최고(랭킹적격)를 조회한다. 현재 랩은 아직 미저장이라 자기비교가 없다.
        var (isPersonalBest, previousBestMs) = await CheckPersonalBestAsync(lap, cancellationToken);

        // 8. Lap(+섹터·스냅샷) + 트레이스 + 멱등 기록 + 장치 LastSeenAt을 한 트랜잭션으로 커밋.
        await _laps.AddAsync(lap, cancellationToken);
        if (trace is not null)
        {
            await _laps.AddTraceAsync(trace, cancellationToken);
        }

        await AddProcessedEventAsync(envelope, now, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        _logger.LogInformation(
            "랩 저장 device={Device} user={User} track={Track} lapMs={LapMs} eligible={Eligible} snapshot={HasSnapshot} trace={HasTrace} eventId={EventId}",
            device.Id, lap.UserId, track.Name, lap.LapTimeMs, lap.IsRankingEligible, lap.Snapshot is not null, trace is not null,
            envelope.EventId);

        // 9. 실시간 브로드캐스트(커밋 이후 best-effort). 랩은 이미 저장됐으므로 실패해도 Ack를 유지한다.
        //    Agent 연결 취소와 앱 브로드캐스트를 분리하기 위해 CancellationToken.None을 사용한다.
        await BroadcastAsync(lap, isPersonalBest, previousBestMs);

        return IngestResult.Ack();
    }

    /// <summary>랭킹 적격 랩이면 이전 최고와 비교한다. 비적격 랩은 PB가 아니다(조회하지 않는다).</summary>
    private async Task<(bool IsPersonalBest, int? PreviousBestMs)> CheckPersonalBestAsync(Lap lap, CancellationToken cancellationToken)
    {
        if (!lap.IsRankingEligible)
        {
            return (false, null);
        }

        var previousBest = await _laps.GetPersonalBestLapAsync(lap.UserId, lap.TrackId, lap.GameCode, cancellationToken);
        return (previousBest is null || lap.LapTimeMs < previousBest.LapTimeMs, previousBest?.LapTimeMs);
    }

    /// <summary>
    /// 장치 주인에게 귀속된 랩을 만든다. 랭킹 적격은 Backend가 일원화해 판정한다(D-15):
    /// 유효 &amp;&amp; 아웃/인랩 아님 &amp;&amp; TimeTrial.
    /// </summary>
    private Lap CreateLap(TelemetryEnvelopeDto envelope, LapFinishedPayloadDto payload, AgentDevice device, Guid trackId, DateTime now)
        => new()
        {
            Id = _idGenerator.NewId(),
            AgentDeviceId = device.Id,
            UserId = device.UserId,
            TrackId = trackId,
            GameCode = envelope.GameCode,
            SessionType = payload.SessionType,
            LapNumber = payload.LapNumber,
            LapTimeMs = payload.LapTimeMs,
            IsValid = payload.IsValid,
            IsInvalidatedManually = false,
            IsRankingEligible = payload.IsValid && !payload.IsOutOrInLap && payload.SessionType == SessionType.TimeTrial,
            SetAt = envelope.OccurredAt,
            SessionKey = BuildSessionKey(payload),
            GameMode = StorableGameMode(payload.GameMode),
            CreatedAt = now,
            Sectors = payload.Sectors
                .Select(s => new LapSector
                {
                    Id = _idGenerator.NewId(),
                    SectorNumber = s.SectorNumber,
                    SectorTimeMs = s.SectorTimeMs,
                    CreatedAt = now,
                })
                .ToList(),
        };

    /// <summary>
    /// 랩이 속한 게임 세션의 키(<c>Lap.SessionKey</c>, 12 §4.6)를 <see cref="SessionKeys.For"/> 규칙으로 만든다 — 세션 결과(<c>GameSession</c>)와
    /// 같은 규칙이라 P8이 같은 키로 잇는다. 옛 Agent(모드·링크 필드 없음)는 <c>uid:{sessionRef}</c>가 된다.
    /// <c>sessionRef</c>가 비었거나 열 길이(<see cref="SessionClassificationValidator.MaxSessionRefLength"/>)를 넘거나 NUL을 품으면 키를 만들지 않고
    /// null로 둔다 — 그런 값이 저장 시 예외가 되어 같은 랩이 끝없이 재시도되는 일을 막는다(12 §0).
    /// </summary>
    private static string? BuildSessionKey(LapFinishedPayloadDto payload)
    {
        var sessionRef = payload.SessionRef;
        if (string.IsNullOrEmpty(sessionRef)
            || sessionRef.Length > SessionClassificationValidator.MaxSessionRefLength
            || sessionRef.Contains(NulCharacter))
        {
            return null;
        }

        return SessionKeys.For(
            LenientEnum.Parse<GameMode>(payload.GameMode),
            payload.SeasonLinkId,
            payload.WeekendLinkId,
            payload.SessionLinkId,
            sessionRef);
    }

    /// <summary>
    /// 랩에 저장할 게임 모드(15 §5): 페이로드 문자열 그대로(모르는 이름도). 비었거나 열 길이(<see cref="Lap.GameModeMaxLength"/>)를 넘거나
    /// NUL을 품으면 null — 저장 시 예외가 되어 같은 랩이 끝없이 재시도되는 일을 막는다(<see cref="BuildSessionKey"/>와 같은 이유).
    /// </summary>
    private static string? StorableGameMode(string? gameMode)
        => string.IsNullOrEmpty(gameMode) || gameMode.Length > Lap.GameModeMaxLength || gameMode.Contains(NulCharacter)
            ? null
            : gameMode;

    /// <summary>
    /// 저장된 랩에 대한 실시간 이벤트를 발행한다(05 §3). 모든 랩→LapRecorded(주인에게만, D-50), PB 갱신→PersonalBestAchieved(user 그룹),
    /// 랭킹적격→월별 TOP N 재조회 후 RankingUpdated(track 그룹, D-8a). 어떤 실패도 Ack에 영향을 주지 않는다.
    /// </summary>
    private async Task BroadcastAsync(Lap lap, bool isPersonalBest, int? previousBestMs)
    {
        // LapRecorded가 실패해도 랭킹 갱신은 나가도록 따로 감싼다.
        await SendLapRecordedAsync(lap);

        try
        {
            if (isPersonalBest)
            {
                await _notifier.PersonalBestAchievedAsync(
                    new PersonalBestNotice(lap.UserId, lap.TrackId, lap.LapTimeMs, previousBestMs));
            }

            if (lap.IsRankingEligible)
            {
                var snapshot = await _ranking.GetRankingAsync(lap.TrackId, lap.GameCode, RankingPeriod.Monthly, date: null);
                await _notifier.RankingUpdatedAsync(snapshot);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "랩 저장 후 브로드캐스트 실패 lapId={LapId} track={TrackId}", lap.Id, lap.TrackId);
        }
    }

    /// <summary>
    /// 새 랩을 주인에게 보낸다(docs/15 §9, D-50). 무효 랩도 보낸다 — 내 랩 목록이 무효 랩도 보이기 때문이다.
    /// 페이로드는 커밋된 랩을 <c>GET /me/laps</c>와 같은 조회·매퍼로 다시 읽어 만든다(필드 규칙 한 곳, 쿼리 1번).
    /// </summary>
    private async Task SendLapRecordedAsync(Lap lap)
    {
        try
        {
            var row = await _lapQueries.GetMineAsync(lap.UserId, lap.Id);
            if (row is null)
            {
                _logger.LogWarning("방금 저장한 랩을 다시 읽지 못해 LapRecorded 생략 lapId={LapId} user={User}", lap.Id, lap.UserId);
                return;
            }

            await _notifier.LapRecordedAsync(lap.UserId, new LapRecordedNotice(LapDtoMapper.ToLapDto(row), row.TrackId));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "LapRecorded 전송 실패 lapId={LapId} user={User}", lap.Id, lap.UserId);
        }
    }
}
