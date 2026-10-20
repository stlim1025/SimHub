using SimCenter.Agent.Core.Abstractions;
using SimCenter.Agent.Core.Telemetry.Events;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 도메인 이벤트 페이로드를 서버 전송용 <see cref="TelemetryEnvelope"/>로 감싼다.
/// eventId(멱등키)=IIdGenerator, occurredAt=IClock, gameCode=주입한 공급원의 현재 값(세션별 에디션 판별)으로 채운다(docs/06 §4, docs/11 §6.5).
/// </summary>
public sealed class DomainEventFactory
{
    private readonly IClock _clock;
    private readonly IIdGenerator _idGenerator;
    private readonly IGameCodeSource _gameCode;

    public DomainEventFactory(IClock clock, IIdGenerator idGenerator, IGameCodeSource gameCode)
    {
        _clock = clock;
        _idGenerator = idGenerator;
        _gameCode = gameCode;
    }

    public TelemetryEnvelope Wrap(TelemetryEvent payload) => new(
        EventId: _idGenerator.NewId(),
        GameCode: _gameCode.GameCode,
        OccurredAt: _clock.UtcNow,
        Type: payload.Type,
        Payload: payload);
}
