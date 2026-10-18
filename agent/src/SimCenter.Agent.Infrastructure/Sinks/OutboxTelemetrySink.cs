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
/// P7: Outbox에 넣기 전에 직렬화 UTF-8 바이트를 재서 <see cref="MaxEnvelopeBytes"/>를 넘는 봉투가 허브 한도에 걸려
/// 연결이 끊긴 채 같은 항목을 끝없이 재시도하는 일을 막는다(12 §5.5).
/// 넘으면 부가 정보부터 줄인다: SessionClassified는 랩 기록(D-49) → 스틴트 순으로 빼고, LapFinished는 트레이스 해상도를 낮추거나
/// 트레이스를 빼고(D-45), 그래도 넘으면 상세(<c>car.details</c>, D-49)까지 뺀다. 랩·순위표 자체는 지킨다.
/// </summary>
public sealed class OutboxTelemetrySink : ITelemetrySink
{
    /// <summary>
    /// 봉투 직렬화 크기 한도(UTF-8 바이트) — D-49(docs/15 §8)에서 48KiB → 768KiB. 백엔드 <c>TelemetryHub.MaxMessageBytes</c>(1MiB)보다 낮게 둬서
    /// SignalR 호출 포장(메서드 이름·구분자 등)이 더해져도 한도 안에 남게 한다.
    /// </summary>
    internal const int MaxEnvelopeBytes = 768 * 1024;

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
                SessionClassified classified => FitClassified(envelope, classified, bytes),
                LapFinished lap => FitLap(envelope, lap, bytes),
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

    /// <summary>
    /// 랩 기록(lapHistory·lapPositions, D-49)과 스틴트는 순위표의 부가 정보다 — 랩 기록부터, 그래도 넘으면 스틴트까지 빼고 다시 재서 순위표 자체는 지킨다.
    /// 둘 다 빼도 넘으면 null.
    /// </summary>
    private string? FitClassified(TelemetryEnvelope envelope, SessionClassified classified, int bytes)
    {
        var withoutLapRecords = classified with { Results = StripLapHistory(classified.Results), LapPositions = null };
        var candidates = new (string What, SessionClassified Payload)[]
        {
            ("랩 기록을", withoutLapRecords),
            ("랩 기록과 타이어 스틴트를", withoutLapRecords with { Results = StripTyreStints(withoutLapRecords.Results) }),
        };

        foreach (var (what, payload) in candidates)
        {
            var json = Serialize(envelope, payload);
            var strippedBytes = Utf8Bytes(json);
            if (strippedBytes <= MaxEnvelopeBytes)
            {
                _logger.LogWarning(
                    "SessionClassified {EventId}가 {Bytes}바이트로 한도({Max})를 넘어 {What} 빼고 적재합니다({StrippedBytes}바이트).",
                    envelope.EventId, bytes, MaxEnvelopeBytes, what, strippedBytes);
                return json;
            }
        }

        return null;
    }

    /// <summary>
    /// 트레이스는 랩의 덤이다(D-45) — 해상도를 두 배씩(5m → 10m → 20m) 낮추며 다시 재고, 20m에서도 넘으면 트레이스만 빼고 랩을 보낸다.
    /// 트레이스를 빼도 넘으면 트레이스 탓이 아니므로 낮춰 보지 않고 상세(<c>car.details</c>, D-49)까지 빼 본다. 그래도 넘으면 null(호출부가 오류 로그 후 버린다).
    /// </summary>
    private string? FitLap(TelemetryEnvelope envelope, LapFinished lap, int bytes)
    {
        var withoutTrace = Serialize(envelope, lap with { Trace = null });
        if (Utf8Bytes(withoutTrace) > MaxEnvelopeBytes)
        {
            return FitWithoutDetails(envelope, lap, bytes);
        }

        if (lap.Trace is { } trace && FitTrace(envelope, lap, trace, bytes) is { } downsampled)
        {
            return downsampled;
        }

        _logger.LogWarning(
            "LapFinished {EventId}의 트레이스가 {ResolutionM}m 해상도로도 한도({Max})를 넘어 트레이스만 빼고 랩을 적재합니다.",
            envelope.EventId, MaxTraceResolutionM, MaxEnvelopeBytes);
        return withoutTrace;
    }

    private string? FitTrace(TelemetryEnvelope envelope, LapFinished lap, LapTrace trace, int bytes)
    {
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

        return null;
    }

    /// <summary>
    /// 트레이스 없이도 넘으면 상세를 빼고(스냅샷 본체는 남긴다) 트레이스 맞추기를 처음부터 다시 한다 — 상세 때문에 트레이스까지 잃지 않게.
    /// 상세가 없으면 null(상세 탓이 아니다).
    /// </summary>
    private string? FitWithoutDetails(TelemetryEnvelope envelope, LapFinished lap, int bytes)
    {
        if (lap.Car?.Details is null)
        {
            return null;
        }

        _logger.LogWarning(
            "LapFinished {EventId}가 {Bytes}바이트로 트레이스를 빼도 한도({Max})를 넘어 상세(car.details)를 빼고 다시 맞춥니다.",
            envelope.EventId, bytes, MaxEnvelopeBytes);
        var withoutDetails = lap with { Car = lap.Car with { Details = null } };
        var json = Serialize(envelope, withoutDetails);
        return Utf8Bytes(json) <= MaxEnvelopeBytes ? json : FitLap(envelope, withoutDetails, bytes);
    }

    private static int Utf8Bytes(string json) => Encoding.UTF8.GetByteCount(json);

    private static string Serialize(TelemetryEnvelope envelope, TelemetryEvent payload) =>
        JsonSerializer.Serialize(
            new WireEnvelope(envelope.EventId, envelope.GameCode, envelope.OccurredAt, envelope.Type.ToString(), payload),
            WireJson);

    private static IReadOnlyList<ClassifiedResult> StripTyreStints(IReadOnlyList<ClassifiedResult> results) =>
        results.Select(result => result with { TyreStints = [] }).ToArray();

    private static IReadOnlyList<ClassifiedResult> StripLapHistory(IReadOnlyList<ClassifiedResult> results) =>
        results.Select(result => result with { LapHistory = null }).ToArray();

    /// <summary>전송용 봉투. Type은 문자열, Payload는 object(런타임 타입 직렬화). 장치 식별은 담지 않는다(D-26).</summary>
    private sealed record WireEnvelope(
        Guid EventId,
        string GameCode,
        DateTime OccurredAt,
        string Type,
        object Payload);
}
