using SimCenter.Agent.Core.Abstractions;

namespace SimCenter.Agent.Infrastructure.Time;

/// <summary>IClock 구현. 시스템 UTC 시각.</summary>
public sealed class SystemClock : IClock
{
    public DateTime UtcNow => DateTime.UtcNow;
}
