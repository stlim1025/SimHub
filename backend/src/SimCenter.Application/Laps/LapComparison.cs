using SimCenter.Domain.Enums;

namespace SimCenter.Application.Laps;

/// <summary>비교 대상 종류(docs/15 §10, D-51). REST 쿼리 <c>compare=best|leaderboard|lap|none</c>(대소문자 무시, 기본 best).</summary>
public enum LapComparisonKind
{
    /// <summary>같은 트랙·게임의 내 최고 유효 랩(기본).</summary>
    Best,

    /// <summary>같은 트랙·게임의 랭킹 적격 랩(모든 사용자, 전체 기간) 중 최고.</summary>
    Leaderboard,

    /// <summary>랩 ID로 고른 랩 — 내 랩이면 무엇이든, 남의 랩이면 랭킹 적격 랩만.</summary>
    Lap,

    /// <summary>비교하지 않는다.</summary>
    None,
}

/// <summary>
/// 랩 상세의 비교 선택(D-51). 필터는 <see cref="LapComparisonKind.Best"/>·<see cref="LapComparisonKind.Leaderboard"/>를 고를 때만 쓴다.
/// <see cref="CompareLapId"/>는 <see cref="LapComparisonKind.Lap"/>일 때 필수, 그 밖에는 무시한다.
/// </summary>
public sealed record LapComparisonRequest(
    LapComparisonKind Kind,
    Guid? CompareLapId = null,
    bool SameTeam = false,
    bool SameSessionType = false,
    bool SameAssists = false,
    bool SameTyre = false)
{
    public static readonly LapComparisonRequest Default = new(LapComparisonKind.Best);
}

/// <summary>응답의 <c>comparison.kind</c> 값(D-51).</summary>
public static class LapComparisonKinds
{
    public const string Best = "best";
    public const string Leaderboard = "leaderboard";
    public const string Lap = "lap";
}

/// <summary>응답의 <c>comparison.appliedFilters</c> 값(D-51). 쿼리 이름과 같다.</summary>
public static class LapComparisonFilters
{
    public const string SameTeam = "sameTeam";
    public const string SameSessionType = "sameSessionType";
    public const string SameAssists = "sameAssists";

    /// <summary>같은 보이는 컴파운드(랩 끝 스냅샷)의 랩만 — 레이스 랩을 같은 타이어끼리 비교한다.</summary>
    public const string SameTyre = "sameTyre";
}

/// <summary>
/// 비교 대상이 없는 까닭(<c>comparisonUnavailable</c>, D-51).
/// <see cref="NotFound"/> = 고른 랩 ID가 없거나 남의 비공개(랭킹 부적격) 랩 — 둘을 구분하지 않는다(D-34와 같은 이유: 남의 랩이 있는지 알려 주지 않는다).
/// <see cref="NoMatch"/> = 최고 랩·리더보드 최고 랩을 찾았지만 조건(필터 포함)에 맞는 랩이 없다.
/// </summary>
public static class LapComparisonUnavailable
{
    public const string NotFound = "notFound";
    public const string NoMatch = "noMatch";
}

/// <summary>최고 랩을 찾는 범위(D-51).</summary>
public enum LapComparisonScope
{
    /// <summary>내 유효(<c>IsValid</c>) 랩.</summary>
    MineValid,

    /// <summary>모든 사용자의 랭킹 적격(<c>IsRankingEligible</c>) 랩.</summary>
    LeaderboardEligible,
}

/// <summary>
/// 최고 랩 검색 조건(D-51). 같은 트랙·게임은 늘 적용, 나머지는 값이 있을 때만 같아야 한다.
/// <see cref="Assists"/>는 값이 있는 칸만 같아야 한다(모르는 칸은 조건 없음).
/// </summary>
public sealed record LapComparisonCriteria(
    LapComparisonScope Scope,
    Guid UserId,
    Guid TrackId,
    string GameCode,
    int? TeamId = null,
    SessionType? SessionType = null,
    LapAssistValues? Assists = null,
    int? VisualTyreCompound = null);

/// <summary>남의 랩 주인의 이름 공개 설정(D-39). 리포지토리 → 서비스.</summary>
public sealed record LapDriverRow(string DisplayName, bool ShowOnLeaderboard);
