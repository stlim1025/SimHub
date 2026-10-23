using SimCenter.Application.Telemetry;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.TrackSamples;

/// <summary>
/// <c>TrackSamplesChunk</c> 처리기. 새 조각이면 저장할 행을 <b>추적만</b> 하고 저장하지 않는다 —
/// <c>ProcessedEvent</c> 추가와 커밋 1회는 <see cref="ITelemetryIngestService"/>가 한다. 거부일 때는 아무것도 추적하지 않는다.
/// </summary>
public interface ITrackSamplesIngestor
{
    /// <returns>Ack면 null(새 조각 추적 또는 이미 받은 조각), 영구 무효면 Reject 사유.</returns>
    Task<string?> ApplyAsync(TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, CancellationToken cancellationToken = default);
}
