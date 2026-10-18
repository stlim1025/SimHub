using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 완주한 랩 기록(불변). 무효 랩도 저장하되 <see cref="IsRankingEligible"/>로 랭킹에서만 제외한다(D-15).
/// 랩타임/섹터타임은 부동소수 오차·정렬 안정성을 위해 int 밀리초로 저장한다.
/// </summary>
public class Lap : BaseEntity
{
    /// <summary><see cref="GameMode"/> 저장 열 길이. 넘는 값은 저장하지 않는다(null).</summary>
    public const int GameModeMaxLength = 30;

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

    /// <summary>
    /// 이 랩이 속한 게임 세션의 키(P7, 12 §4.6). <c>SessionKeys.For</c> 규칙(D-29)으로 인입 시 계산해 저장만 한다 — P8이
    /// <c>(UserId, GameCode, SessionKey)</c>로 <see cref="GameSession"/>과 잇는다. 옛 행과 <c>sessionRef</c>가 비었거나 너무 길어
    /// 키를 만들지 못한 랩은 null이다.
    /// </summary>
    public string? SessionKey { get; set; }

    /// <summary>
    /// 게임 모드(15 §5). 페이로드 <c>gameMode</c> 문자열을 그대로 저장한다(모르는 값도). 옛 랩·값 없음은 null.
    /// 세션 키 계산은 이 값과 별개로 <c>GameMode</c> enum 해석을 쓴다.
    /// </summary>
    public string? GameMode { get; set; }

    /// <summary>랩 끝의 차량·날씨 스냅샷(D-44, 1:0..1). 이전 Agent로 기록한 랩은 null.</summary>
    public LapSnapshot? Snapshot { get; set; }

    public ICollection<LapSector> Sectors { get; set; } = new List<LapSector>();
}
