using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;

namespace SimCenter.Application.TrackSamples;

/// <summary>내 세션의 다른 차 랩을 표본으로 복원한다(폴 포지션 랩과 내 랩 비교 등).</summary>
public interface IFieldLapService
{
    /// <summary>
    /// 그 차의 베스트 랩(순위표의 베스트 랩 타임과 가장 가까운 랩)을 내 랩 트레이스와 같은 모양으로.
    /// 남의 세션·없는 세션·그 차 결과 없음·표본 없음·복원할 랩 없음은 모두 <see cref="NotFoundException"/>.
    /// </summary>
    Task<LapTraceResponse> GetBestLapTraceAsync(Guid userId, Guid sessionId, int carIndex, CancellationToken cancellationToken = default);
}

/// <summary><see cref="IFieldLapService"/> 구현. 풀 수 없는 조각은 경고만 남기고 건너뛴다.</summary>
public sealed class FieldLapService : IFieldLapService
{
    private const string NotFoundMessage = "그 차의 랩을 표본으로 복원할 수 없습니다.";

    private readonly IGameSessionQueryRepository _sessions;
    private readonly ITrackSampleChunkRepository _chunks;
    private readonly ILogger<FieldLapService> _logger;

    public FieldLapService(IGameSessionQueryRepository sessions, ITrackSampleChunkRepository chunks, ILogger<FieldLapService> logger)
    {
        _sessions = sessions;
        _chunks = chunks;
        _logger = logger;
    }

    public async Task<LapTraceResponse> GetBestLapTraceAsync(
        Guid userId, Guid sessionId, int carIndex, CancellationToken cancellationToken = default)
    {
        var session = await _sessions.GetMineDetailAsync(userId, sessionId, cancellationToken)
            ?? throw new NotFoundException("세션을 찾을 수 없습니다.");
        var result = session.Results.FirstOrDefault(r => !r.IsDeleted && r.CarIndex == carIndex)
            ?? throw new NotFoundException(NotFoundMessage);

        var decoded = new List<DecodedTrackSamples>();
        var stored = await _chunks.ListForSessionAsync(userId, session.SessionRef, cancellationToken);
        foreach (var chunk in stored)
        {
            try
            {
                decoded.Add(TrackSampleDecoder.Decode(chunk.Payload, chunk.Format));
            }
            catch (FormatException ex)
            {
                _logger.LogWarning(ex, "Skipping undecodable track sample chunk {SessionRef}#{ChunkIndex}", chunk.SessionRef, chunk.ChunkIndex);
            }
        }

        var bestLapTimeMs = result.BestLapTimeMs > 0 ? result.BestLapTimeMs : (int?)null;
        var trackLength = stored.Max(c => c.TrackLengthM) is > 0 and var length ? (double?)length : null;
        var channels = FieldLapBuilder.Build(decoded, carIndex, bestLapTimeMs, trackLength)
            ?? throw new NotFoundException(NotFoundMessage);
        return new LapTraceResponse(
            Guid.Empty,
            FieldLapBuilder.ResolutionM,
            channels.TimeMs.Length,
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
