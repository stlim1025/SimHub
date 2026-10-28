using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Laps;

/// <summary>
/// 랩 상세·트레이스 조회(15 §4.2, D-46, §10 D-51). 상세는 쿼리 5번 이하
/// (랩 → 스냅샷 → 비교 대상 → 남의 랩이면 주인 이름 → 세션 키가 있으면 세션 ID)로 끝난다.
/// </summary>
public sealed class LapQueryService : ILapQueryService
{
    private const string LapNotFoundMessage = "랩을 찾을 수 없습니다.";
    private const string TraceNotFoundMessage = "이 랩의 텔레메트리를 찾을 수 없습니다.";
    private const string CompareField = "compare";
    private const string CompareLapIdField = "compareLapId";

    private readonly ILapQueryRepository _laps;
    private readonly IGameSessionQueryRepository _sessions;
    private readonly ILogger<LapQueryService> _logger;

    public LapQueryService(ILapQueryRepository laps, IGameSessionQueryRepository sessions, ILogger<LapQueryService> logger)
    {
        _laps = laps;
        _sessions = sessions;
        _logger = logger;
    }

    public async Task<LapDetailResponse> GetMyLapAsync(
        Guid userId, Guid lapId, LapComparisonRequest? comparison = null, CancellationToken cancellationToken = default)
    {
        var request = comparison ?? LapComparisonRequest.Default;
        Validate(request);

        var lap = await _laps.GetMineAsync(userId, lapId, cancellationToken)
            ?? throw new NotFoundException(LapNotFoundMessage);

        var snapshot = await _laps.GetSnapshotAsync(lap.LapId, cancellationToken);
        var assists = LapAssistValues.From(snapshot);
        var (compared, unavailable) = await CompareAsync(userId, lap, assists, request, cancellationToken);
        var sessionId = lap.SessionKey is { } sessionKey
            ? await _sessions.FindMySessionIdAsync(userId, lap.GameCode, sessionKey, cancellationToken)
            : null;

        return new LapDetailResponse(
            LapDtoMapper.ToLapDto(lap),
            lap.TrackId,
            lap.CountryCode,
            sessionId,
            LapDtoMapper.ToCar(snapshot),
            LapDtoMapper.ToConditions(snapshot),
            LapAssistNames.ToDto(assists),
            compared,
            unavailable);
    }

    public async Task<LapTraceResponse> GetMyLapTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
    {
        var trace = await _laps.GetMyTraceAsync(userId, lapId, cancellationToken)
            ?? throw new NotFoundException(TraceNotFoundMessage);
        return ToTraceResponse(lapId, trace);
    }

    public async Task<LapTraceResponse> GetComparableLapTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
    {
        // 공개 규칙(D-51): 내 랩 또는 남의 랭킹 적격 랩. 그 밖은 없는 것과 같은 404(D-34).
        var trace = await _laps.GetComparableTraceAsync(userId, lapId, cancellationToken)
            ?? throw new NotFoundException(TraceNotFoundMessage);
        return ToTraceResponse(lapId, trace);
    }

    public async Task<PublicLapDetailResponse> GetPublicLapAsync(
        Guid lapId, Guid? compareLapId = null, CancellationToken cancellationToken = default)
    {
        var lap = await _laps.GetSharedAsync(lapId, cancellationToken)
            ?? throw new NotFoundException(LapNotFoundMessage);

        var snapshot = await _laps.GetSnapshotAsync(lap.LapId, cancellationToken);
        var displayName = await PublicDisplayNameAsync(lap.UserId, cancellationToken);
        var comparison = compareLapId is { } id ? await SharedComparisonAsync(lap, id, cancellationToken) : null;

        return new PublicLapDetailResponse(
            LapDtoMapper.ToLapDto(lap),
            lap.TrackId,
            lap.CountryCode,
            displayName,
            LapDtoMapper.ToCar(snapshot),
            LapDtoMapper.ToConditions(snapshot),
            LapAssistNames.ToDto(LapAssistValues.From(snapshot)),
            comparison);
    }

    /// <summary>
    /// 공유 링크의 비교 랩(종류 <c>lap</c>). 이 랩 자신·없는(지운) 랩·다른 트랙이나 게임의 랩이면 null(비교 없이 보인다).
    /// 공유 랩과 같은 규칙(지우지 않은 랩)으로 읽고, 주인이 다르면 이름은 랭킹과 같은 규칙(D-39)이다.
    /// </summary>
    private async Task<LapComparisonDto?> SharedComparisonAsync(LapRow lap, Guid compareLapId, CancellationToken cancellationToken)
    {
        if (compareLapId == lap.LapId)
        {
            return null;
        }

        var picked = await _laps.GetSharedAsync(compareLapId, cancellationToken);
        if (picked is null || picked.TrackId != lap.TrackId || picked.GameCode != lap.GameCode)
        {
            return null;
        }

        return await ToComparisonAsync(lap.UserId, picked, LapComparisonKinds.Lap, [], cancellationToken);
    }

    public async Task<LapTraceResponse> GetPublicLapTraceAsync(Guid lapId, CancellationToken cancellationToken = default)
    {
        var trace = await _laps.GetSharedTraceAsync(lapId, cancellationToken)
            ?? throw new NotFoundException(TraceNotFoundMessage);
        return ToTraceResponse(lapId, trace);
    }

    private static void Validate(LapComparisonRequest request)
    {
        if (!Enum.IsDefined(request.Kind))
        {
            throw new ValidationException(CompareField, "compare는 best·leaderboard·lap·none 중 하나여야 합니다.");
        }

        if (request.Kind == LapComparisonKind.Lap && request.CompareLapId is null)
        {
            throw new ValidationException(CompareLapIdField, "compare=lap이면 compareLapId가 필요합니다.");
        }
    }

    /// <summary>고른 비교 대상(D-51). 없으면 까닭(<see cref="LapComparisonUnavailable"/>), <c>none</c>이면 둘 다 null.</summary>
    private async Task<(LapComparisonDto? Comparison, string? Unavailable)> CompareAsync(
        Guid userId, LapRow lap, LapAssistValues assists, LapComparisonRequest request, CancellationToken cancellationToken)
    {
        switch (request.Kind)
        {
            case LapComparisonKind.None:
                return (null, null);

            case LapComparisonKind.Lap:
                var picked = await _laps.GetComparableAsync(userId, request.CompareLapId!.Value, cancellationToken);
                return picked is null
                    ? (null, LapComparisonUnavailable.NotFound)
                    : (await ToComparisonAsync(userId, picked, LapComparisonKinds.Lap, [], cancellationToken), null);

            default:
                var (criteria, applied) = BuildCriteria(userId, lap, assists, request);
                var fastest = await _laps.FindFastestAsync(criteria, cancellationToken);
                var kind = request.Kind == LapComparisonKind.Leaderboard ? LapComparisonKinds.Leaderboard : LapComparisonKinds.Best;
                return fastest is null
                    ? (null, LapComparisonUnavailable.NoMatch)
                    : (await ToComparisonAsync(userId, fastest, kind, applied, cancellationToken), null);
        }
    }

    /// <summary>
    /// 최고 랩 조건 + 실제로 적용한 필터. 이 랩의 값을 모르는 필터(팀 없음·어시스트 전부 모름)는 적용하지 않는다 —
    /// "같은 값"을 정할 수 없어서다. 세션 유형은 늘 안다.
    /// </summary>
    private static (LapComparisonCriteria Criteria, IReadOnlyList<string> Applied) BuildCriteria(
        Guid userId, LapRow lap, LapAssistValues assists, LapComparisonRequest request)
    {
        var applied = new List<string>();
        var teamId = request.SameTeam ? lap.TeamId : null;
        if (teamId is not null)
        {
            applied.Add(LapComparisonFilters.SameTeam);
        }

        var sessionType = request.SameSessionType ? lap.SessionType : (Domain.Enums.SessionType?)null;
        if (sessionType is not null)
        {
            applied.Add(LapComparisonFilters.SameSessionType);
        }

        var assistFilter = request.SameAssists && assists.HasAny ? assists : null;
        if (assistFilter is not null)
        {
            applied.Add(LapComparisonFilters.SameAssists);
        }

        var compound = request.SameTyre ? lap.VisualTyreCompound : null;
        if (compound is not null)
        {
            applied.Add(LapComparisonFilters.SameTyre);
        }

        var scope = request.Kind == LapComparisonKind.Leaderboard
            ? LapComparisonScope.LeaderboardEligible
            : LapComparisonScope.MineValid;
        return (new LapComparisonCriteria(scope, userId, lap.TrackId, lap.GameCode, teamId, sessionType, assistFilter, compound), applied);
    }

    /// <summary>비교 DTO. 남의 랩이면 주인 이름을 랭킹과 같은 규칙으로(D-39, 행이 없으면 익명).</summary>
    private async Task<LapComparisonDto> ToComparisonAsync(
        Guid userId, LapRow row, string kind, IReadOnlyList<string> applied, CancellationToken cancellationToken)
    {
        var isMine = row.UserId == userId;
        string? displayName = null;
        if (!isMine)
        {
            displayName = await PublicDisplayNameAsync(row.UserId, cancellationToken);
        }

        return LapDtoMapper.ToComparison(row, kind, isMine, displayName, applied);
    }

    /// <summary>남에게 보이는 랩 주인 이름: 랭킹과 같은 규칙(D-39) — 이름 비공개·지운 사용자(행 없음)는 익명 드라이버.</summary>
    private async Task<string> PublicDisplayNameAsync(Guid ownerId, CancellationToken cancellationToken)
    {
        var driver = await _laps.GetDriverAsync(ownerId, cancellationToken);
        return driver is { ShowOnLeaderboard: true } ? driver.DisplayName : RankingPrivacy.AnonymousDisplayName;
    }

    private LapTraceResponse ToTraceResponse(Guid lapId, LapTelemetryTrace trace)
    {
        LapTraceChannels channels;
        try
        {
            channels = LapTraceCodec.Decode(trace.Payload);
        }
        catch (InvalidDataException ex)
        {
            // 인입 때 검증한 값만 저장하므로 저장 데이터 손상이다 — 500으로 두고 원인을 남긴다.
            _logger.LogError(ex, "트레이스 복원 실패 lapId={LapId} traceId={TraceId}", lapId, trace.Id);
            throw;
        }

        return new LapTraceResponse(
            lapId,
            trace.ResolutionM,
            trace.SampleCount,
            channels.TimeMs,
            channels.SpeedKph,
            channels.Throttle,
            channels.Brake,
            channels.Steer,
            channels.Gear,
            channels.Rpm,
            channels.Extra ?? new Dictionary<string, double[]>());
    }
}
