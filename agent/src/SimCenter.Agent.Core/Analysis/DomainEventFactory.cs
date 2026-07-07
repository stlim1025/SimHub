using SimCenter.Agent.Core.Abstractions;
using SimCenter.Agent.Core.Telemetry.Events;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 도메인 이벤트 페이로드를 서버 전송용 <see cref="TelemetryEnvelope"/>로 감싼다.
/// eventId(멱등키)=IIdGenerator, occurredAt=IClock, rigCode/gameCode=주입 식별로 채운다(docs/06 §4).
/// </summary>
public sealed class DomainEventFactory
{
    private readonly IClock _clock;
    private readonly IIdGenerator _idGenerator;
    private readonly AgentIdentity _identity;

    public DomainEventFactory(IClock clock, IIdGenerator idGenerator, AgentIdentity identity)
    {
        _clock = clock;
        _idGenerator = idGenerator;
        _identity = identity;
    }

    public TelemetryEnvelope Wrap(TelemetryEvent payload) => new(
        EventId: _idGenerator.NewId(),
        RigCode: _identity.RigCode,
        GameCode: _identity.GameCode,
        OccurredAt: _clock.UtcNow,
        Type: payload.Type,
        Payload: payload);
}
