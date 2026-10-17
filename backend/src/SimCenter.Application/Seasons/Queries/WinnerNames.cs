namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 라운드별 우승자 이름(12 §7.3 <c>rounds[].winnerName</c>). 순수 함수 — 상태 없음.
/// 주말의 <b>본 레이스</b> 1위 행의 표시 이름이다(스프린트 우승자는 아님). 이름이 없으면 <c>Car {carIndex+1}</c>.
/// 본 레이스가 없거나 1위 행이 없는 주말은 키가 없다.
/// </summary>
public static class WinnerNames
{
    private const int WinnerPosition = 1;

    public static IReadOnlyDictionary<Guid, string> ByWeekend(SeasonSelection selection)
    {
        ArgumentNullException.ThrowIfNull(selection);

        var winnerBySession = selection.CountedRows
            .Where(r => r.Position == WinnerPosition)
            .GroupBy(r => r.SessionId)
            .ToDictionary(g => g.Key, g => g.OrderBy(r => r.CarIndex).First());

        var names = new Dictionary<Guid, string>();
        foreach (var (weekendId, mainRaceSessionId) in selection.MainRaceSessionByWeekend)
        {
            if (winnerBySession.TryGetValue(mainRaceSessionId, out var winner))
            {
                names[weekendId] = DriverLabels.Name(winner.DriverName, winner.CarIndex);
            }
        }

        return names;
    }
}
