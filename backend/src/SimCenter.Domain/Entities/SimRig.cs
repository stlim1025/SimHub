using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 시뮬레이터 좌석/장비. Agent config·체크인 코드가 <see cref="RigCode"/>로 참조한다.
/// </summary>
public class SimRig : BaseEntity
{
    public Guid StoreId { get; set; }
    public Store? Store { get; set; }

    /// <summary>Agent config·체크인이 참조하는 코드(예: "A-01"). Unique.</summary>
    public required string RigCode { get; set; }

    /// <summary>UI 표시명(예: "1번 좌석").</summary>
    public required string DisplayName { get; set; }
}
