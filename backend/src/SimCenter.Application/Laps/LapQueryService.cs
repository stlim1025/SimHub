using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.Laps;

/// <summary>
/// 랩 상세·트레이스 조회(15 §4.2, D-46). 상세는 쿼리 4번 이하(랩 → 스냅샷 → 비교 대상 → 세션 ID, 세션 키가 없으면 3번)로 끝난다.
/// </summary>
public sealed class LapQueryService : ILapQueryService
{
    private const string LapNotFoundMessage = "랩을 찾을 수 없습니다.";
    private const string TraceNotFoundMessage = "이 랩의 텔레메트리를 찾을 수 없습니다.";

    private readonly ILapQueryRepository _laps;
    private readonly IGameSessionQueryRepository _sessions;
    private readonly ILogger<LapQueryService> _logger;

    public LapQueryService(ILapQueryRepository laps, IGameSessionQueryRepository sessions, ILogger<LapQueryService> logger)
    {
        _laps = laps;
        _sessions = sessions;
        _logger = logger;
    }

    public async Task<LapDetailResponse> GetMyLapAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
    {
        var lap = await _laps.GetMineAsync(userId, lapId, cancellationToken)
            ?? throw new NotFoundException(LapNotFoundMessage);

        var snapshot = await _laps.GetSnapshotAsync(lap.LapId, cancellationToken);
        var best = await _laps.GetMyFastestValidAsync(userId, lap.TrackId, lap.GameCode, cancellationToken);
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
            LapDtoMapper.ToComparison(best));
    }

    public async Task<LapTraceResponse> GetMyLapTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
    {
        var trace = await _laps.GetMyTraceAsync(userId, lapId, cancellationToken)
            ?? throw new NotFoundException(TraceNotFoundMessage);

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
