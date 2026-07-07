using SimCenter.Agent.Core.Abstractions;

namespace SimCenter.Agent.Infrastructure.Common;

/// <summary>IIdGenerator 구현. UUID v7(순차성). 이벤트 멱등키에 사용.</summary>
public sealed class UuidV7Generator : IIdGenerator
{
    public Guid NewId() => Guid.CreateVersion7();
}
