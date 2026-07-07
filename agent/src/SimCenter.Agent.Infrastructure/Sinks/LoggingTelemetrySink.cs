using Microsoft.Extensions.Logging;
using SimCenter.Agent.Core.Telemetry.Events;

namespace SimCenter.Agent.Infrastructure.Sinks;

/// <summary>이벤트 봉투를 로그로만 출력하는 P2 싱크(전송 없음).</summary>
public sealed class LoggingTelemetrySink : ITelemetrySink
{
    private readonly ILogger<LoggingTelemetrySink> _logger;

    public LoggingTelemetrySink(ILogger<LoggingTelemetrySink> logger) => _logger = logger;

    public Task EmitAsync(TelemetryEnvelope envelope, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "이벤트 {Type} rig={Rig} session={Session} eventId={EventId} payload={Payload}",
            envelope.Type, envelope.RigCode, envelope.Payload.SessionRef, envelope.EventId, envelope.Payload);
        return Task.CompletedTask;
    }
}
