using SimCenter.Application.Common;

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
        => WinnerRows(selection).ToDictionary(p => p.Key, p => DriverLabels.Name(p.Value.DriverName, p.Value.CarIndex));

    /// <summary>
    /// 라운드별 우승자 팀 색(<c>rounds[].winnerTeamColor</c>, 시즌 탭 WINNER 칸의 팀 점). 키는 <see cref="ByWeekend"/>와 같다.
    /// 팀을 모르면 <see cref="TeamCatalog"/>의 중립 회색이다.
    /// </summary>
    public static IReadOnlyDictionary<Guid, string> TeamColorByWeekend(SeasonSelection selection, string gameCode)
        => WinnerRows(selection).ToDictionary(p => p.Key, p => TeamCatalog.Resolve(gameCode, p.Value.TeamId, p.Value.TeamName).Color);

    /// <summary>주말 Id → 본 레이스 1위 행(같은 순위가 여럿이면 차 번호가 작은 쪽).</summary>
    private static Dictionary<Guid, SeasonResultRow> WinnerRows(SeasonSelection selection)
    {
        ArgumentNullException.ThrowIfNull(selection);

        var winnerBySession = selection.CountedRows
            .Where(r => r.Position == WinnerPosition)
            .GroupBy(r => r.SessionId)
            .ToDictionary(g => g.Key, g => g.OrderBy(r => r.CarIndex).First());

        var winners = new Dictionary<Guid, SeasonResultRow>();
        foreach (var (weekendId, mainRaceSessionId) in selection.MainRaceSessionByWeekend)
        {
            if (winnerBySession.TryGetValue(mainRaceSessionId, out var winner))
            {
                winners[weekendId] = winner;
            }
        }

        return winners;
    }
}
