using SimCenter.Agent.Core.Telemetry.Events;

namespace SimCenter.Agent.Infrastructure.Sinks;

/// <summary>
/// 도메인 이벤트 봉투의 출력 지점. P2는 로깅 싱크, <b>P3에서 Outbox(SQLite)+SignalR 싱크로 교체</b>한다.
/// </summary>
public interface ITelemetrySink
{
    Task EmitAsync(TelemetryEnvelope envelope, CancellationToken cancellationToken = default);
}
