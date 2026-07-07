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

    /// <summary>
    /// Agent 장비 인증 키의 해시(SHA-256 hex). 원문은 저장하지 않는다(D-12/D-21). Unique.
    /// TelemetryHub 접속 시 이 해시로 좌석을 특정하고 연결에 RigCode를 귀속한다.
    /// </summary>
    public string? ApiKeyHash { get; set; }
}
