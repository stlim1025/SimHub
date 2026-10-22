using SimCenter.Application.Common;
using SimCenter.Application.Seasons.Import;
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
/// <para>
/// <b>가져온 시즌</b>(docs/15 §12, D-55, <c>imported</c>가 있을 때): 드라이버 점수 = 가져온 포인트 + 가져온 것이 아닌 세션의 점수
/// (가져온 세션의 점수는 기준선에 이미 들어 있다). 기준선 드라이버는 <see cref="DriverAliasing"/>로 기록된 드라이버와 묶고,
/// 못 맞춘 기준선 드라이버는 기록 없이(기준선의 팀) 오른다. 컨스트럭터 = 가져온 컨스트럭터 기준값 + 가져온 것이 아닌 행의 팀별 점수,
/// 기준값이 없으면(F1Laps 요약만) 드라이버의 최신 팀별 합 — 팀을 모르는 드라이버는 컨스트럭터에서 빠진다.
/// </para>
/// 합계는 <c>long</c>으로 구해 정렬하고 표시 값만 <c>int</c> 상한으로 자른다(점수는 0 이상 <c>int</c>까지 검증을 통과하므로).
/// </summary>
public static class StandingsCalculator
{
    private const int PodiumPositions = 3;
    private const string ImportedDriverKeyPrefix = "imported:";

    public static SeasonStandings Calculate(
        SeasonSelection selection, string gameCode, ImportedSeasonSnapshot? imported = null)
    {
        ArgumentNullException.ThrowIfNull(selection);
        ArgumentNullException.ThrowIfNull(gameCode);

        if (imported is { Drivers.Count: > 0 })
        {
            var aliased = DriverAliasing.Apply(selection, imported.Drivers, out var keyByEntry);
            var rows = aliased.CountedRows.Where(IsScoringRow).ToList();
            var drivers = BuildDrivers(aliased, rows, new Baseline(imported.Drivers, keyByEntry));
            var constructors = imported.Constructors is { Count: > 0 } teams
                ? BuildConstructorsWithBaseline(rows, aliased.MainRaceSessionByWeekend, gameCode, teams)
                : BuildConstructorsFromDrivers(drivers, gameCode);
            return new SeasonStandings(drivers, constructors);
        }

        var scoringRows = selection.CountedRows.Where(IsScoringRow).ToList();

        if (scoringRows.Count == 0)
        {
            return new SeasonStandings([], []);
        }

        var mainRace = selection.MainRaceSessionByWeekend;
        return new SeasonStandings(
            BuildDrivers(selection, scoringRows, baseline: null),
            BuildConstructors(scoringRows, mainRace, gameCode));
    }

    private static bool IsScoringRow(SeasonResultRow row) => SessionPositions.CountsForPoints(row.SessionType);

    private static bool IsMainRaceRow(SeasonResultRow row, IReadOnlyDictionary<Guid, Guid> mainRace)
        => mainRace.TryGetValue(row.WeekendId, out var mainSessionId) && row.SessionId == mainSessionId;

    // ---- 드라이버 ----

    private sealed record DriverTally(
        string DriverKey,
        string Name,
        int? TeamId,
        bool IsPlayer,
        bool IsAiControlled,
        long Points,
        int Wins,
        int Podiums,
        int[] PositionCounts,
        string? TeamName = null);

    private static bool HasTeam(DriverTally tally) => tally.TeamId is not null || tally.TeamName is not null;

    /// <summary>가져온 드라이버 기준값과 <see cref="DriverAliasing"/>이 묶은 키(기준선 순번 → 키).</summary>
    private sealed record Baseline(IReadOnlyList<ImportedDriverPoints> Entries, IReadOnlyDictionary<int, string> KeyByEntry);

    private static List<DriverStanding> BuildDrivers(
        SeasonSelection selection, List<SeasonResultRow> scoringRows, Baseline? baseline)
    {
        var mainRace = selection.MainRaceSessionByWeekend;
        var positionIndex = MainRacePositionIndex(scoringRows, mainRace);

        var tallies = scoringRows
            .GroupBy(r => r.DriverKey)
            .Select(group => Tally(group.ToList(), mainRace, positionIndex, excludeImportedPoints: baseline is not null))
            .ToList();

        if (baseline is not null)
        {
            tallies = ApplyBaseline(tallies, baseline, positionIndex.Count);
        }

        var cellsByDriver = selection.CountedRows.ToLookup(r => r.DriverKey);
        var weekendStart = selection.CountedRows
            .GroupBy(r => r.WeekendId)
            .ToDictionary(g => g.Key, g => g.Min(r => r.ClassifiedAt));

        return Rank(tallies, positionIndex.Count)
            .Select((tally, index) => new DriverStanding(
                index + 1,
                tally.DriverKey,
                tally.Name,
                tally.TeamId,
                tally.IsPlayer,
                tally.IsAiControlled,
                PointTotals.ToInt(tally.Points),
                tally.Wins,
                tally.Podiums,
                BuildCells(cellsByDriver[tally.DriverKey], mainRace, weekendStart),
                tally.TeamName))
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
        List<SeasonResultRow> rows,
        IReadOnlyDictionary<Guid, Guid> mainRace,
        Dictionary<int, int> positionIndex,
        bool excludeImportedPoints)
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
            latest.DriverKey,
            DriverLabels.Name(latest.DriverName, latest.CarIndex),
            latest.TeamId,
            latest.IsPlayer,
            latest.IsAiControlled,
            rows.Where(r => !(excludeImportedPoints && r.IsImported)).Sum(r => (long)r.Points),
            mainRaceRows.Count(r => r.Position == 1),
            mainRaceRows.Count(r => r.Position <= PodiumPositions),
            counts,
            latest.TeamName);
    }

    /// <summary>
    /// 가져온 포인트를 기록된 드라이버에 더한다(D-55). 묶인 키(<see cref="DriverAliasing"/>)가 있으면 그 줄에, 없으면
    /// 기록 없는 줄(<c>imported:{이름}</c>, 기준선의 팀)로 더한다. 기록된 줄의 팀이 없으면 기준선의 팀을 쓴다.
    /// </summary>
    private static List<DriverTally> ApplyBaseline(List<DriverTally> tallies, Baseline baseline, int positionCount)
    {
        var merged = tallies.ToDictionary(t => t.DriverKey, StringComparer.Ordinal);
        for (var i = 0; i < baseline.Entries.Count; i++)
        {
            var entry = baseline.Entries[i];
            var key = baseline.KeyByEntry.TryGetValue(i, out var bound)
                ? bound
                : ImportedDriverKeyPrefix + DriverNameMatcher.Normalize(entry.Name);
            merged[key] = merged.TryGetValue(key, out var tally)
                ? HasTeam(tally)
                    ? tally with { Points = tally.Points + entry.Points }
                    : tally with { Points = tally.Points + entry.Points, TeamId = entry.TeamId, TeamName = entry.TeamName }
                : new DriverTally(
                    key,
                    entry.Name,
                    entry.TeamId,
                    entry.IsPlayer,
                    IsAiControlled: !entry.IsPlayer,
                    entry.Points,
                    Wins: 0,
                    Podiums: 0,
                    new int[positionCount],
                    entry.TeamName);
        }

        return merged.Values.ToList();
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
            .ThenBy(t => t.DriverKey, StringComparer.Ordinal);
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
            .Select(g => NewTeamTotal(
                gameCode,
                g.Key,
                g.Select(r => r.TeamName).FirstOrDefault(n => n is not null),
                g.Sum(r => (long)r.Points),
                g.Count(r => IsMainRaceRow(r, mainRace) && r.Position == 1)));

        return RankTeams(teams);
    }

    /// <summary>가져온 시즌(D-55): 드라이버 최종 점수를 그 드라이버의 최신 팀별로 더한다. 팀을 모르는 드라이버는 뺀다.</summary>
    private static List<ConstructorStanding> BuildConstructorsFromDrivers(List<DriverStanding> drivers, string gameCode)
    {
        var teams = drivers
            .Where(d => d.TeamId is not null)
            .GroupBy(d => d.TeamId!.Value)
            .Select(g => NewTeamTotal(
                gameCode,
                g.Key,
                g.Select(d => d.TeamName).FirstOrDefault(n => n is not null),
                g.Sum(d => (long)d.Points),
                g.Sum(d => d.Wins)));

        return RankTeams(teams);
    }

    /// <summary>
    /// 가져온 시즌의 컨스트럭터(D-55): 인게임 기준값 + 가져온 것이 아닌 대상 행의 팀별 점수(그 세션의 팀). 우승 = 본 레이스 1위(가져온 행 포함).
    /// </summary>
    private static List<ConstructorStanding> BuildConstructorsWithBaseline(
        List<SeasonResultRow> scoringRows,
        IReadOnlyDictionary<Guid, Guid> mainRace,
        string gameCode,
        IReadOnlyList<ImportedConstructorPoints> baseline)
    {
        var points = baseline.GroupBy(t => t.TeamId).ToDictionary(g => g.Key, g => g.Sum(t => (long)t.Points));
        var names = baseline.Where(t => t.TeamName is not null).GroupBy(t => t.TeamId).ToDictionary(g => g.Key, g => g.First().TeamName);
        var wins = new Dictionary<int, int>();
        foreach (var row in scoringRows.Where(r => r.TeamId is not null))
        {
            var teamId = row.TeamId!.Value;
            if (row.TeamName is not null)
            {
                names.TryAdd(teamId, row.TeamName);
            }

            if (!row.IsImported)
            {
                points[teamId] = points.GetValueOrDefault(teamId) + row.Points;
            }

            if (IsMainRaceRow(row, mainRace) && row.Position == 1)
            {
                wins[teamId] = wins.GetValueOrDefault(teamId) + 1;
            }
        }

        return RankTeams(points.Select(p => NewTeamTotal(
            gameCode, p.Key, names.GetValueOrDefault(p.Key), p.Value, wins.GetValueOrDefault(p.Key))));
    }

    /// <summary><see cref="TeamName"/> = 저장된 사용자 팀 이름(My Team), <see cref="Name"/> = 표시 이름(동점 정렬용).</summary>
    private sealed record TeamTotal(int TeamId, string Name, long Points, int Wins, string? TeamName);

    private static TeamTotal NewTeamTotal(string gameCode, int teamId, string? teamName, long points, int wins)
        => new(teamId, TeamCatalog.Resolve(gameCode, teamId, teamName).Name, points, wins, teamName);

    private static List<ConstructorStanding> RankTeams(IEnumerable<TeamTotal> teams)
        => teams
            .OrderByDescending(t => t.Points)
            .ThenByDescending(t => t.Wins)
            .ThenBy(t => t.Name, StringComparer.Ordinal)
            .ThenBy(t => t.TeamId)
            .Select((t, index) => new ConstructorStanding(index + 1, t.TeamId, PointTotals.ToInt(t.Points), t.Wins, t.TeamName))
            .ToList();
}
