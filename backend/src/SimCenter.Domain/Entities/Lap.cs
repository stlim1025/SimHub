using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 완주한 랩 기록(불변). 무효 랩도 저장하되 <see cref="IsRankingEligible"/>로 랭킹에서만 제외한다(D-15).
/// 랩타임/섹터타임은 부동소수 오차·정렬 안정성을 위해 int 밀리초로 저장한다.
/// </summary>
public class Lap : BaseEntity
{
    /// <summary>랩을 보낸 Agent 장치(D-25). 해제된 장치의 랩도 기록으로 남는다.</summary>
    public Guid AgentDeviceId { get; set; }

    /// <summary>
    /// 랩을 보낸 장치(내비게이션). <b>주의:</b> <c>AgentDevice</c> 엔티티에는 전역 soft-delete 필터가 걸려 있어,
    /// 이 내비게이션을 거치는 <c>Include</c>·프로젝션(<c>lap.AgentDevice.Name</c> 등)은 <b>연결 해제된 장치의 랩을 결과에서 빼 버린다</b>
    /// (필수 관계라 EF가 inner join을 쓴다). 장치 정보가 필요하면 <c>IgnoreQueryFilters()</c>를 쓰거나
    /// <see cref="AgentDeviceId"/>로 left join한다. EF 모델(마이그레이션 스냅샷)을 바꾸지 않으려고 내비게이션은 유지한다(Ruling R10).
    /// </summary>
    public AgentDevice? AgentDevice { get; set; }

    /// <summary>랩 주인 = 장치 주인(인입 시 확정). 조회·랭킹 성능을 위해 랩에 직접 둔다.</summary>
    public Guid UserId { get; set; }

    public Guid TrackId { get; set; }
    public Track? Track { get; set; }

    /// <summary>이벤트 봉투의 게임 코드(랭킹 필터).</summary>
    public required string GameCode { get; set; }

    /// <summary>게임 세션 유형. 랭킹은 TimeTrial만(D-16).</summary>
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
