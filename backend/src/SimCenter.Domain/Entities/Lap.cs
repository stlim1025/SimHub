using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 완주한 랩 기록(불변). 무효 랩도 저장하되 <see cref="IsRankingEligible"/>로 랭킹에서만 제외한다(D-15).
/// 랩타임/섹터타임은 부동소수 오차·정렬 안정성을 위해 int 밀리초로 저장한다.
/// </summary>
public class Lap : BaseEntity
{
    public Guid DrivingSessionId { get; set; }
    public DrivingSession? DrivingSession { get; set; }

    /// <summary>세션에서 확정한 사용자(비정규화, 조회 성능).</summary>
    public Guid UserId { get; set; }

    public Guid TrackId { get; set; }
    public Track? Track { get; set; }

    /// <summary>세션에서 복사(비정규화, 랭킹 필터).</summary>
    public required string GameCode { get; set; }

    /// <summary>세션에서 복사(비정규화). 랭킹은 TimeTrial만(D-16).</summary>
    public SessionType SessionType { get; set; }

    /// <summary>세션 내 랩 번호.</summary>
    public int LapNumber { get; set; }

    /// <summary>랩타임(밀리초).</summary>
    public int LapTimeMs { get; set; }

    /// <summary>게임 판정 유효성(트랙 이탈 등).</summary>
    public bool IsValid { get; set; }

    /// <summary>운영자 수동 무효화.</summary>
    public bool IsInvalidatedManually { get; set; }

    /// <summary>
    /// 파생 플래그: IsValid &amp;&amp; !수동무효 &amp;&amp; SessionType=TimeTrial &amp;&amp; !아웃/인랩.
    /// Backend가 최종 판정한다.
    /// </summary>
    public bool IsRankingEligible { get; set; }

    /// <summary>랩 완주 시각(UTC).</summary>
    public DateTime SetAt { get; set; }

    public ICollection<LapSector> Sectors { get; set; } = new List<LapSector>();
}
