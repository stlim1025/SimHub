namespace SimCenter.Application.Rankings;

/// <summary>
/// 랭킹 공개 설정(D-39, 14 §6). 사용자가 "랭킹에 내 이름 표시"를 끄면 랭킹 항목(REST <c>/rankings</c>·RankingHub <c>RankingUpdated</c>)의
/// 표시 이름을 <see cref="AnonymousDisplayName"/>으로 바꾼다. 순위·랩타임은 그대로다. 내 기록(<c>/me/*</c>)에는 적용하지 않는다.
/// </summary>
public static class RankingPrivacy
{
    public const string AnonymousDisplayName = "익명 드라이버";

    /// <summary>랭킹에 보일 표시 이름.</summary>
    public static string DisplayNameFor(RankingLapRow row)
    {
        ArgumentNullException.ThrowIfNull(row);
        return row.ShowOnLeaderboard ? row.DisplayName : AnonymousDisplayName;
    }
}
