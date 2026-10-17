namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 시즌 안의 그랑프리 주말에 라운드 번호를 매긴다(12 §4.2, §7.3). 순수 함수 — 상태 없음.
/// 번호는 저장하지 않고 조회 때마다 계산한다: <c>FirstSessionAt</c> 오름차순, 같으면 주말 Id 오름차순, 1부터.
/// 그래서 <c>R{n}</c>은 "기록된 주말 순서"이며 게임의 라운드와 다를 수 있다.
/// </summary>
public static class RoundNumbering
{
    /// <summary>한 시즌의 주말들 → (주말 Id → 라운드 번호).</summary>
    public static IReadOnlyDictionary<Guid, int> Assign(IEnumerable<WeekendRow> weekends)
    {
        ArgumentNullException.ThrowIfNull(weekends);

        var rounds = new Dictionary<Guid, int>();
        foreach (var weekend in weekends.OrderBy(w => w.FirstSessionAt).ThenBy(w => w.WeekendId))
        {
            rounds[weekend.WeekendId] = rounds.Count + 1;
        }

        return rounds;
    }
}
