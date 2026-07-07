using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Infrastructure.Common;

/// <summary>IIdGenerator 구현. UUID v7 생성(순차성 → 인덱스 지역성, D-6).</summary>
public sealed class UuidV7Generator : IIdGenerator
{
    public Guid NewId() => Guid.CreateVersion7();
}
