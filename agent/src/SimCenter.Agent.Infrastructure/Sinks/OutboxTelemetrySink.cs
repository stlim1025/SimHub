using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Infrastructure.Outbox;

namespace SimCenter.Agent.Infrastructure.Sinks;

/// <summary>
/// P3 싱크. 봉투를 서버 계약(camelCase + enum 문자열) JSON으로 직렬화해 Outbox에 적재한다(전송은 업로더가 담당).
/// Payload를 object로 담아 런타임 타입(LapFinished 등)의 모든 필드가 직렬화되게 한다.
/// P7: Outbox에 넣기 전에 직렬화 UTF-8 바이트를 재서 <see cref="MaxEnvelopeBytes"/>를 넘는 봉투가 허브 한도(64KiB)에 걸려
/// 연결이 끊긴 채 같은 항목을 끝없이 재시도하는 일을 막는다(12 §5.5).
/// </summary>
public sealed class OutboxTelemetrySink : ITelemetrySink
{
    /// <summary>
    /// 봉투 직렬화 크기 한도(UTF-8 바이트). 백엔드 <c>TelemetryHub.MaxMessageBytes</c>(64KiB)보다 낮게 둬서
    /// SignalR 호출 포장(메서드 이름·구분자 등)이 더해져도 한도 안에 남게 한다.
    /// </summary>
    internal const int MaxEnvelopeBytes = 48 * 1024;

    internal static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly TelemetryOutbox _outbox;
    private readonly ILogger<OutboxTelemetrySink> _logger;

    public OutboxTelemetrySink(TelemetryOutbox outbox, ILogger<OutboxTelemetrySink> logger)
    {
        _outbox = outbox;
        _logger = logger;
    }

    public async Task EmitAsync(TelemetryEnvelope envelope, CancellationToken cancellationToken = default)
    {
        var json = Serialize(envelope, envelope.Payload);
        var bytes = Encoding.UTF8.GetByteCount(json);

        if (bytes > MaxEnvelopeBytes)
        {
            if (envelope.Payload is SessionClassified classified)
            {
                // 스틴트는 순위표의 부가 정보다 — 빼고 다시 재서 순위표 자체는 지킨다.
                var withoutStints = classified with { Results = StripTyreStints(classified.Results) };
                json = Serialize(envelope, withoutStints);
                var strippedBytes = Encoding.UTF8.GetByteCount(json);
                if (strippedBytes <= MaxEnvelopeBytes)
                {
                    _logger.LogWarning(
                        "SessionClassified {EventId}가 {Bytes}바이트로 한도({Max})를 넘어 타이어 스틴트를 빼고 적재합니다({StrippedBytes}바이트).",
                        envelope.EventId, bytes, MaxEnvelopeBytes, strippedBytes);
                    await _outbox.EnqueueAsync(envelope.EventId, envelope.OccurredAt, json, cancellationToken);
                    return;
                }

                bytes = strippedBytes;
            }

            _logger.LogError(
                "{Type} {EventId}가 {Bytes}바이트로 한도({Max})를 넘어 적재하지 않고 버립니다.",
                envelope.Type, envelope.EventId, bytes, MaxEnvelopeBytes);
            return;
        }

        await _outbox.EnqueueAsync(envelope.EventId, envelope.OccurredAt, json, cancellationToken);
    }

    private static string Serialize(TelemetryEnvelope envelope, TelemetryEvent payload) =>
        JsonSerializer.Serialize(
            new WireEnvelope(envelope.EventId, envelope.GameCode, envelope.OccurredAt, envelope.Type.ToString(), payload),
            WireJson);

    private static IReadOnlyList<ClassifiedResult> StripTyreStints(IReadOnlyList<ClassifiedResult> results) =>
        results.Select(result => result with { TyreStints = [] }).ToArray();

    /// <summary>전송용 봉투. Type은 문자열, Payload는 object(런타임 타입 직렬화). 장치 식별은 담지 않는다(D-26).</summary>
    private sealed record WireEnvelope(
        Guid EventId,
        string GameCode,
        DateTime OccurredAt,
        string Type,
        object Payload);
}
