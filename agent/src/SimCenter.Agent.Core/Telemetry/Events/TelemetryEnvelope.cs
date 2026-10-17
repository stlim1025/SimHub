namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>
/// 서버 전송 봉투(shared/schema/telemetry_envelope.json). <see cref="EventId"/>는 멱등키(재전송 시 동일).
/// 보낸 장치는 봉투에 담지 않고 연결의 장치 키 인증으로 정해진다(D-26).
/// 전송 자체는 Outbox·업로더가 담당한다. 이 계층은 봉투 생성까지만 담당한다.
/// </summary>
public sealed record TelemetryEnvelope(
    Guid EventId,
    string GameCode,
    DateTime OccurredAt,
    TelemetryEventType Type,
    TelemetryEvent Payload);
