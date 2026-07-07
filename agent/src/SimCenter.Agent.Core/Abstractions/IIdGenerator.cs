namespace SimCenter.Agent.Core.Abstractions;

/// <summary>이벤트 멱등키(eventId) 생성 추상화. UUID v7 권장(결정론적 테스트 위해 주입).</summary>
public interface IIdGenerator
{
    Guid NewId();
}
