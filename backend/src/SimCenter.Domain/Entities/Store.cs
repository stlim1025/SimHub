using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 매장(멀티스토어 선반영, D-1). MVP는 시드로 단일 매장 1개를 채운다.
/// </summary>
public class Store : BaseEntity
{
    public required string Name { get; set; }

    /// <summary>
    /// 매장 로컬 타임존(IANA, 예: "Asia/Seoul"). 랭킹 기간(일/월/연) 경계를 이 타임존의 자정 기준으로 계산한다(D-8/D-24).
    /// </summary>
    public required string TimeZoneId { get; set; }

    public ICollection<SimRig> Rigs { get; set; } = new List<SimRig>();
}
