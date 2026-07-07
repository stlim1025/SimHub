namespace SimCenter.Agent.Core.Abstractions;

/// <summary>시간 추상화(헌장: DateTime.Now 직접 사용 금지). 이벤트 occurredAt 기준.</summary>
public interface IClock
{
    DateTime UtcNow { get; }
}
