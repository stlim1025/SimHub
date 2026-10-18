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
/// 넘으면 부가 정보부터 줄인다: SessionClassified는 스틴트를 빼고, LapFinished는 트레이스 해상도를 낮추거나 트레이스를 뺀다(D-45).
/// </summary>
public sealed class OutboxTelemetrySink : ITelemetrySink
{
    /// <summary>
    /// 봉투 직렬화 크기 한도(UTF-8 바이트). 백엔드 <c>TelemetryHub.MaxMessageBytes</c>(64KiB)보다 낮게 둬서
    /// SignalR 호출 포장(메서드 이름·구분자 등)이 더해져도 한도 안에 남게 한다.
    /// </summary>
    internal const int MaxEnvelopeBytes = 48 * 1024;

    /// <summary>LapFinished 트레이스를 한도에 맞추려 낮출 수 있는 가장 거친 해상도(m, D-45: 5m → 10m → 20m).</summary>
    internal const int MaxTraceResolutionM = 20;

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
        var bytes = Utf8Bytes(json);

        if (bytes > MaxEnvelopeBytes)
        {
            var fitted = envelope.Payload switch
            {
                SessionClassified classified => FitWithoutStints(envelope, classified, bytes),
                LapFinished { Trace: not null } lap => FitLapTrace(envelope, lap, bytes),
                _ => null,
            };

            if (fitted is null)
            {
                _logger.LogError(
                    "{Type} {EventId}가 {Bytes}바이트로 한도({Max})를 넘어 적재하지 않고 버립니다.",
                    envelope.Type, envelope.EventId, bytes, MaxEnvelopeBytes);
                return;
            }

            json = fitted;
        }

        await _outbox.EnqueueAsync(envelope.EventId, envelope.OccurredAt, json, cancellationToken);
    }

    /// <summary>스틴트는 순위표의 부가 정보다 — 빼고 다시 재서 순위표 자체는 지킨다. 그래도 넘으면 null.</summary>
    private string? FitWithoutStints(TelemetryEnvelope envelope, SessionClassified classified, int bytes)
    {
        var json = Serialize(envelope, classified with { Results = StripTyreStints(classified.Results) });
        var strippedBytes = Utf8Bytes(json);
        if (strippedBytes > MaxEnvelopeBytes)
        {
            return null;
        }

        _logger.LogWarning(
            "SessionClassified {EventId}가 {Bytes}바이트로 한도({Max})를 넘어 타이어 스틴트를 빼고 적재합니다({StrippedBytes}바이트).",
            envelope.EventId, bytes, MaxEnvelopeBytes, strippedBytes);
        return json;
    }

    /// <summary>
    /// 트레이스는 랩의 덤이다(D-45) — 해상도를 두 배씩(5m → 10m → 20m) 낮추며 다시 재고, 20m에서도 넘으면 트레이스만 빼고 랩을 보낸다.
    /// 트레이스를 빼도 넘으면 트레이스 탓이 아니므로 null(호출부가 오류 로그 후 버린다). 랩은 트레이스 때문에 버리지 않는다.
    /// </summary>
    private string? FitLapTrace(TelemetryEnvelope envelope, LapFinished lap, int bytes)
    {
        var withoutTrace = Serialize(envelope, lap with { Trace = null });
        if (Utf8Bytes(withoutTrace) > MaxEnvelopeBytes)
        {
            return null;
        }

        var trace = lap.Trace!;
        while (trace.ResolutionM < MaxTraceResolutionM)
        {
            trace = trace.Downsample();
            var json = Serialize(envelope, lap with { Trace = trace });
            var downsampledBytes = Utf8Bytes(json);
            if (downsampledBytes <= MaxEnvelopeBytes)
            {
                _logger.LogInformation(
                    "LapFinished {EventId}가 {Bytes}바이트로 한도({Max})를 넘어 트레이스를 {ResolutionM}m 해상도로 낮춰 적재합니다({DownsampledBytes}바이트).",
                    envelope.EventId, bytes, MaxEnvelopeBytes, trace.ResolutionM, downsampledBytes);
                return json;
            }
        }

        _logger.LogWarning(
            "LapFinished {EventId}의 트레이스가 {ResolutionM}m 해상도로도 한도({Max})를 넘어 트레이스만 빼고 랩을 적재합니다.",
            envelope.EventId, MaxTraceResolutionM, MaxEnvelopeBytes);
        return withoutTrace;
    }

    private static int Utf8Bytes(string json) => Encoding.UTF8.GetByteCount(json);

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
