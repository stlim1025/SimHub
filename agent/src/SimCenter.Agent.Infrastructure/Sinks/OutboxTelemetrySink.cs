using System.Text.Json;
using System.Text.Json.Serialization;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Infrastructure.Outbox;

namespace SimCenter.Agent.Infrastructure.Sinks;

/// <summary>
/// P3 싱크. 봉투를 서버 계약(camelCase + enum 문자열) JSON으로 직렬화해 Outbox에 적재한다(전송은 업로더가 담당).
/// Payload를 object로 담아 런타임 타입(LapFinished 등)의 모든 필드가 직렬화되게 한다.
/// </summary>
public sealed class OutboxTelemetrySink : ITelemetrySink
{
    internal static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly TelemetryOutbox _outbox;

    public OutboxTelemetrySink(TelemetryOutbox outbox) => _outbox = outbox;

    public async Task EmitAsync(TelemetryEnvelope envelope, CancellationToken cancellationToken = default)
    {
        var wire = new WireEnvelope(
            envelope.EventId,
            envelope.RigCode,
            envelope.GameCode,
            envelope.OccurredAt,
            envelope.Type.ToString(),
            envelope.Payload);

        var json = JsonSerializer.Serialize(wire, WireJson);
        await _outbox.EnqueueAsync(envelope.EventId, envelope.OccurredAt, json, cancellationToken);
    }

    /// <summary>전송용 봉투. Type은 문자열, Payload는 object(런타임 타입 직렬화).</summary>
    private sealed record WireEnvelope(
        Guid EventId,
        string RigCode,
        string GameCode,
        DateTime OccurredAt,
        string Type,
        object Payload);
}
