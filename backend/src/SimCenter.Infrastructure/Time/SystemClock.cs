using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Infrastructure.Time;

/// <summary>IClock 구현. 시스템 UTC 시각을 제공한다(직접 DateTime.Now 사용 금지 원칙 준수).</summary>
public sealed class SystemClock : IClock
{
    public DateTime UtcNow => DateTime.UtcNow;
}
