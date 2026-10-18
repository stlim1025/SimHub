namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 시즌 안의 그랑프리 주말에 라운드 번호를 매긴다(12 §4.2, §7.3). 순수 함수 — 상태 없음.
/// 번호는 저장하지 않고 조회 때마다 계산한다: <c>FirstSessionAt</c> 오름차순, 같으면 주말 Id 오름차순, 1부터.
/// 그래서 <c>R{n}</c>은 "기록된 주말 순서"이며 게임의 라운드와 다를 수 있다.
/// <para>
/// 가져온 시즌(<see cref="WeekendRow.CalendarRounds"/>, docs/15 §12 D-55)은 F1Laps의 <c>#</c>가 캘린더 순서라
/// 라운드 = 트랙 <see cref="WeekendRow.DisplayOrder"/>다. 순서가 없거나(0) 이미 쓴 번호인 주말은 위 순서대로 그 뒤 번호를 받는다.
/// </para>
/// </summary>
public static class RoundNumbering
{
    /// <summary>한 시즌의 주말들 → (주말 Id → 라운드 번호).</summary>
    public static IReadOnlyDictionary<Guid, int> Assign(IEnumerable<WeekendRow> weekends)
    {
        ArgumentNullException.ThrowIfNull(weekends);

        var ordered = weekends.OrderBy(w => w.FirstSessionAt).ThenBy(w => w.WeekendId).ToList();
        return ordered.Any(w => w.CalendarRounds) ? ByCalendar(ordered) : ByRecordedOrder(ordered);
    }

    private static Dictionary<Guid, int> ByRecordedOrder(List<WeekendRow> ordered)
    {
        var rounds = new Dictionary<Guid, int>();
        foreach (var weekend in ordered)
        {
            rounds[weekend.WeekendId] = rounds.Count + 1;
        }

        return rounds;
    }

    private static Dictionary<Guid, int> ByCalendar(List<WeekendRow> ordered)
    {
        var rounds = new Dictionary<Guid, int>();
        var used = new HashSet<int>();
        var leftovers = new List<WeekendRow>();
        foreach (var weekend in ordered)
        {
            if (weekend.DisplayOrder >= 1 && used.Add(weekend.DisplayOrder))
            {
                rounds[weekend.WeekendId] = weekend.DisplayOrder;
            }
            else
            {
                leftovers.Add(weekend);
            }
        }

        var next = used.Count == 0 ? 1 : used.Max() + 1;
        foreach (var weekend in leftovers)
        {
            rounds[weekend.WeekendId] = next++;
        }

        return rounds;
    }
}
