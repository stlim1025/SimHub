namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>
/// 서버 전송 봉투(shared/schema/telemetry_envelope.json). <see cref="EventId"/>는 멱등키(재전송 시 동일).
/// 전송 자체는 P3(SignalR/Outbox). 이 계층은 봉투 생성까지만 담당한다.
/// </summary>
public sealed record TelemetryEnvelope(
    Guid EventId,
    string RigCode,
    string GameCode,
    DateTime OccurredAt,
    TelemetryEventType Type,
    TelemetryEvent Payload);
