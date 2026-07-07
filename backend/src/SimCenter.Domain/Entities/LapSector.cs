using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 랩의 섹터 기록. 가변 섹터(D-7): 게임별 섹터 수가 다를 수 있어 별도 테이블로 정규화한다.
/// Unique(LapId, SectorNumber).
/// </summary>
public class LapSector : BaseEntity
{
    public Guid LapId { get; set; }
    public Lap? Lap { get; set; }

    /// <summary>섹터 번호(1..N, 게임별 상이).</summary>
    public int SectorNumber { get; set; }

    /// <summary>섹터 타임(밀리초).</summary>
    public int SectorTimeMs { get; set; }
}
