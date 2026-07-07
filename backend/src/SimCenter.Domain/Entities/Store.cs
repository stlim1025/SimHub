using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 매장(멀티스토어 선반영, D-1). MVP는 시드로 단일 매장 1개를 채운다.
/// </summary>
public class Store : BaseEntity
{
    public required string Name { get; set; }

    public ICollection<SimRig> Rigs { get; set; } = new List<SimRig>();
}
