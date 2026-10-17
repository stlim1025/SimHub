using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 시즌 Standings 계산(D-31, 12 §7.3). 순수 함수 — 상태 없음.
/// <list type="bullet">
/// <item><b>대상 행</b> = 계산 대상 세션(<see cref="SeasonSelection.CountedRows"/>) 중 레이스 세션이거나 점수가 있는 행.
/// 시즌 목록(DB에서 이미 대상 행만 읽음)과 상세(전체 행)가 같은 순위를 내는 이유다. 대상 행이 없는 드라이버는 Standings에 오르지 않는다.</item>
/// <item>점수 = 대상 행 점수의 합(스프린트 포함). 우승·포디움·카운트백 = 주말의 <b>본 레이스</b> 결과만.</item>
/// <item>드라이버 동점: 점수 ↓ → 본 레이스 1위 수 ↓ → 2위 수 ↓ … → 표시 이름 Ordinal ↑ → <c>DriverKey</c> Ordinal ↑.</item>
/// <item>컨스트럭터: 팀별 점수 합(그 세션에서 그 드라이버가 속한 팀 기준, 팀 없는 행 제외) — 점수 ↓ → 우승 ↓ → 팀 이름 Ordinal ↑ → 팀 ID ↑.</item>
/// </list>
/// 합계는 <c>long</c>으로 구해 정렬하고 표시 값만 <c>int</c> 상한으로 자른다(점수는 0 이상 <c>int</c>까지 검증을 통과하므로).
/// </summary>
public static class StandingsCalculator
{
    private const int PodiumPositions = 3;

    public static SeasonStandings Calculate(SeasonSelection selection, string gameCode)
    {
        ArgumentNullException.ThrowIfNull(selection);
        ArgumentNullException.ThrowIfNull(gameCode);

        var scoringRows = selection.CountedRows.Where(IsScoringRow).ToList();
        if (scoringRows.Count == 0)
        {
            return new SeasonStandings([], []);
        }

        var mainRace = selection.MainRaceSessionByWeekend;
        return new SeasonStandings(
            BuildDrivers(selection, scoringRows),
            BuildConstructors(scoringRows, mainRace, gameCode));
    }

    private static bool IsScoringRow(SeasonResultRow row) => row.SessionType == SessionType.Race || row.Points > 0;

    private static bool IsMainRaceRow(SeasonResultRow row, IReadOnlyDictionary<Guid, Guid> mainRace)
        => mainRace.TryGetValue(row.WeekendId, out var mainSessionId) && row.SessionId == mainSessionId;

    // ---- 드라이버 ----

    private sealed record DriverTally(
        SeasonResultRow Latest,
        string Name,
        long Points,
        int Wins,
        int Podiums,
        int[] PositionCounts);

    private static List<DriverStanding> BuildDrivers(SeasonSelection selection, List<SeasonResultRow> scoringRows)
    {
        var mainRace = selection.MainRaceSessionByWeekend;
        var positionIndex = MainRacePositionIndex(scoringRows, mainRace);

        var tallies = scoringRows
            .GroupBy(r => r.DriverKey)
            .Select(group => Tally(group.ToList(), mainRace, positionIndex))
            .ToList();

        var cellsByDriver = selection.CountedRows.ToLookup(r => r.DriverKey);
        var weekendStart = selection.CountedRows
            .GroupBy(r => r.WeekendId)
            .ToDictionary(g => g.Key, g => g.Min(r => r.ClassifiedAt));

        return Rank(tallies, positionIndex.Count)
            .Select((tally, index) => new DriverStanding(
                index + 1,
                tally.Latest.DriverKey,
                tally.Name,
                tally.Latest.TeamId,
                tally.Latest.IsPlayer,
                tally.Latest.IsAiControlled,
                PointTotals.ToInt(tally.Points),
                tally.Wins,
                tally.Podiums,
                BuildCells(cellsByDriver[tally.Latest.DriverKey], mainRace, weekendStart)))
            .ToList();
    }

    /// <summary>본 레이스에서 나온 순위(1 이상)를 오름차순으로 번호 매긴다 — 카운트백 배열의 칸 번호.</summary>
    private static Dictionary<int, int> MainRacePositionIndex(
        List<SeasonResultRow> scoringRows, IReadOnlyDictionary<Guid, Guid> mainRace)
    {
        var positions = scoringRows
            .Where(r => IsMainRaceRow(r, mainRace) && r.Position >= 1)
            .Select(r => r.Position)
            .Distinct()
            .Order()
            .ToList();

        var index = new Dictionary<int, int>(positions.Count);
        foreach (var position in positions)
        {
            index[position] = index.Count;
        }

        return index;
    }

    private static DriverTally Tally(
        List<SeasonResultRow> rows, IReadOnlyDictionary<Guid, Guid> mainRace, Dictionary<int, int> positionIndex)
    {
        var latest = rows
            .OrderByDescending(r => r.ClassifiedAt)
            .ThenByDescending(r => r.SessionId)
            .ThenBy(r => r.CarIndex)
            .First();

        var mainRaceRows = rows.Where(r => IsMainRaceRow(r, mainRace) && r.Position >= 1).ToList();
        var counts = new int[positionIndex.Count];
        foreach (var row in mainRaceRows)
        {
            counts[positionIndex[row.Position]]++;
        }

        return new DriverTally(
            latest,
            DriverLabels.Name(latest.DriverName, latest.CarIndex),
            rows.Sum(r => (long)r.Points),
            mainRaceRows.Count(r => r.Position == 1),
            mainRaceRows.Count(r => r.Position <= PodiumPositions),
            counts);
    }

    /// <summary>점수 → 카운트백(1위 수, 2위 수 …) → 이름 → DriverKey. 마지막 키가 유일해 전순서다.</summary>
    private static IEnumerable<DriverTally> Rank(List<DriverTally> tallies, int positionCount)
    {
        var ordered = tallies.OrderByDescending(t => t.Points);
        for (var i = 0; i < positionCount; i++)
        {
            var slot = i;
            ordered = ordered.ThenByDescending(t => t.PositionCounts[slot]);
        }

        return ordered
            .ThenBy(t => t.Name, StringComparer.Ordinal)
            .ThenBy(t => t.Latest.DriverKey, StringComparer.Ordinal);
    }

    /// <summary>
    /// 드라이버의 결과표 칸: 계산 대상 세션에 결과가 있는 주말마다 1개(주말 시각 순).
    /// 순위·상태는 본 레이스 행에서, 점수는 그 주말 행 전부의 합에서 구한다.
    /// </summary>
    private static List<StandingCell> BuildCells(
        IEnumerable<SeasonResultRow> driverRows,
        IReadOnlyDictionary<Guid, Guid> mainRace,
        Dictionary<Guid, DateTime> weekendStart)
    {
        return driverRows
            .GroupBy(r => r.WeekendId)
            .OrderBy(g => weekendStart[g.Key])
            .ThenBy(g => g.Key)
            .Select(g =>
            {
                var main = g
                    .Where(r => IsMainRaceRow(r, mainRace))
                    .OrderBy(r => r.Position)
                    .ThenBy(r => r.CarIndex)
                    .FirstOrDefault();

                return new StandingCell(
                    g.Key,
                    main?.Position,
                    main?.ResultStatus,
                    PointTotals.ToInt(g.Sum(r => (long)r.Points)));
            })
            .ToList();
    }

    // ---- 컨스트럭터 ----

    private static List<ConstructorStanding> BuildConstructors(
        List<SeasonResultRow> scoringRows, IReadOnlyDictionary<Guid, Guid> mainRace, string gameCode)
    {
        var teams = scoringRows
            .Where(r => r.TeamId is not null)
            .GroupBy(r => r.TeamId!.Value)
            .Select(g => new
            {
                TeamId = g.Key,
                Name = TeamCatalog.Resolve(gameCode, g.Key).Name,
                Points = g.Sum(r => (long)r.Points),
                Wins = g.Count(r => IsMainRaceRow(r, mainRace) && r.Position == 1),
            });

        return teams
            .OrderByDescending(t => t.Points)
            .ThenByDescending(t => t.Wins)
            .ThenBy(t => t.Name, StringComparer.Ordinal)
            .ThenBy(t => t.TeamId)
            .Select((t, index) => new ConstructorStanding(index + 1, t.TeamId, PointTotals.ToInt(t.Points), t.Wins))
            .ToList();
    }
}
