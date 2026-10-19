using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons;

public class StandingsCalculatorTests
{
    private const string GameCode = "F1_25";

    private static SeasonStandings Calculate(params SeasonResultRow[] rows)
        => StandingsCalculator.Calculate(SeasonSessionSelector.Select(rows), GameCode);

    // ---- 점수 합산 · 이중 집계 · 우승 ----

    [Fact]
    public void Calculate_SumsPointsAcrossCountedSessions_OrdersDesc()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 25, hours: 10),
            Row(session: 1, weekend: 1, "b", 2, 18, hours: 10),
            Row(session: 2, weekend: 2, "a", 1, 8, kind: SessionKind.Race, hours: 20),    // 스프린트
            Row(session: 2, weekend: 2, "b", 2, 7, kind: SessionKind.Race, hours: 20),
            Row(session: 3, weekend: 2, "a", 2, 18, kind: SessionKind.Race2, hours: 24),  // 본 레이스
            Row(session: 3, weekend: 2, "b", 1, 25, kind: SessionKind.Race2, hours: 24));

        Assert.Equal(new[] { "a", "b" }, standings.Drivers.Select(d => d.DriverKey));
        Assert.Equal(new[] { 51, 50 }, standings.Drivers.Select(d => d.Points));
        Assert.Equal(new[] { 1, 2 }, standings.Drivers.Select(d => d.Position));
    }

    [Fact]
    public void Calculate_QualifyingCarryingWeekendPoints_IsNotCounted()
    {
        // F1 25는 스프린트 뒤 예선 결과에도 그 주말에 딴 점수(스프린트 8점)를 실어 보낸다 — 점수는 레이스에서만 센다.
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 8, kind: SessionKind.Race, hours: 10),   // 스프린트
            Row(session: 2, weekend: 1, "a", 6, 8, SessionType.Qualifying, SessionKind.Qualifying1, hours: 11),
            Row(session: 3, weekend: 1, "a", 2, 8, SessionType.Qualifying, SessionKind.Qualifying2, hours: 12),
            Row(session: 4, weekend: 1, "a", 1, 8, SessionType.Qualifying, SessionKind.Qualifying3, hours: 13));

        Assert.Equal(new[] { 8 }, standings.Drivers.Select(d => d.Points));
    }

    [Fact]
    public void Calculate_DuplicateSession_NotDoubleCounted()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 25, hours: 10),
            Row(session: 2, weekend: 1, "a", 1, 25, hours: 11));

        var driver = Assert.Single(standings.Drivers);
        Assert.Equal(25, driver.Points);
        Assert.Equal(1, driver.Wins);
    }

    [Fact]
    public void Calculate_SprintWin_IsNotAWin()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 8, kind: SessionKind.Race, hours: 10),    // 스프린트 우승
            Row(session: 1, weekend: 1, "b", 2, 7, kind: SessionKind.Race, hours: 10),
            Row(session: 2, weekend: 1, "b", 1, 25, kind: SessionKind.Race2, hours: 14),  // 본 레이스 우승
            Row(session: 2, weekend: 1, "a", 2, 18, kind: SessionKind.Race2, hours: 14));

        var a = standings.Drivers.Single(d => d.DriverKey == "a");
        var b = standings.Drivers.Single(d => d.DriverKey == "b");
        Assert.Equal(0, a.Wins);
        Assert.Equal(1, b.Wins);
        Assert.Equal(26, a.Points);
        Assert.Equal(32, b.Points);
    }

    [Fact]
    public void Calculate_Podiums_CountMainRaceTop3()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 25, hours: 10),
            Row(session: 2, weekend: 2, "a", 2, 8, kind: SessionKind.Race, hours: 20),    // 스프린트 2위 — 포디움 아님
            Row(session: 3, weekend: 2, "a", 3, 15, kind: SessionKind.Race2, hours: 24),
            Row(session: 4, weekend: 3, "a", 4, 12, hours: 30));

        var driver = Assert.Single(standings.Drivers);
        Assert.Equal(2, driver.Podiums);
        Assert.Equal(1, driver.Wins);
    }

    // ---- 동점 처리 ----

    [Fact]
    public void Calculate_Tie_BrokenByMainRaceCountback()
    {
        // 둘 다 10점. z는 1위 1회, a는 2위 2회 → 1위 횟수가 먼저 비교되어 z가 앞.
        // 이름·키 순으로는 a가 앞이고 입력 순서도 a가 먼저라, 카운트백이 없으면 이 기대가 깨진다.
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 2, 5, hours: 10),
            Row(session: 1, weekend: 1, "z", 1, 10, hours: 10),
            Row(session: 2, weekend: 2, "a", 2, 5, hours: 20),
            Row(session: 2, weekend: 2, "z", 4, 0, hours: 20));

        Assert.Equal(new[] { "z", "a" }, standings.Drivers.Select(d => d.DriverKey));
        Assert.All(standings.Drivers, d => Assert.Equal(10, d.Points));
    }

    [Fact]
    public void Calculate_Tie_CountbackContinuesPastFirstPlace()
    {
        // 1위 횟수는 둘 다 0. 2위 횟수는 b가 더 많다 → b가 앞(입력 순서는 a가 먼저).
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 2, 4, hours: 10),
            Row(session: 1, weekend: 1, "b", 2, 4, hours: 10),
            Row(session: 2, weekend: 2, "a", 3, 6, hours: 20),
            Row(session: 2, weekend: 2, "b", 2, 6, hours: 20));

        Assert.Equal(new[] { "b", "a" }, standings.Drivers.Select(d => d.DriverKey));
    }

    [Fact]
    public void Calculate_TieAfterCountback_BrokenByName()
    {
        // 기록이 완전히 같다. Ordinal 비교라 대문자 "ZETA"(90)가 소문자 "alpha"(97)보다 앞선다.
        var standings = Calculate(
            Row(session: 1, weekend: 1, "k1", 1, 25, name: "alpha", hours: 10),
            Row(session: 2, weekend: 2, "k1", 2, 18, name: "alpha", hours: 20),
            Row(session: 1, weekend: 1, "k2", 2, 18, name: "ZETA", hours: 10),
            Row(session: 2, weekend: 2, "k2", 1, 25, name: "ZETA", hours: 20));

        Assert.Equal(new[] { "ZETA", "alpha" }, standings.Drivers.Select(d => d.Name));
    }

    [Fact]
    public void Calculate_SameNameAndRecord_BrokenByDriverKey()
    {
        // 이름·기록이 같다. DriverKey Ordinal 비교: "driver:10" < "driver:2"(숫자 비교가 아님).
        var standings = Calculate(
            Row(session: 1, weekend: 1, "driver:2", 1, 25, name: "Car 5", hours: 10),
            Row(session: 2, weekend: 2, "driver:2", 2, 18, name: "Car 5", hours: 20),
            Row(session: 1, weekend: 1, "driver:10", 2, 18, name: "Car 5", hours: 10),
            Row(session: 2, weekend: 2, "driver:10", 1, 25, name: "Car 5", hours: 20));

        Assert.Equal(new[] { "driver:10", "driver:2" }, standings.Drivers.Select(d => d.DriverKey));
    }

    // ---- Standings 대상 ----

    [Fact]
    public void Calculate_PracticeOnlyDriver_IsNotInStandings()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 0, type: SessionType.Practice, kind: SessionKind.Practice1, hours: 1),
            Row(session: 1, weekend: 1, "practice-only", 2, 0, type: SessionType.Practice, kind: SessionKind.Practice1, hours: 1),
            Row(session: 2, weekend: 1, "a", 1, 25, hours: 10));

        var driver = Assert.Single(standings.Drivers);
        Assert.Equal("a", driver.DriverKey);
    }

    [Fact]
    public void Calculate_NonRaceRowWithPoints_IsNotScored()
    {
        // 예선 결과의 점수 칸은 그 주말에 이미 딴 점수를 다시 실어 보낸 값이다(F1 25 실제 데이터, 2026-10-19) — 점수로 세지 않는다.
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 3, type: SessionType.Qualifying, kind: SessionKind.Qualifying1, hours: 5));

        Assert.Empty(standings.Drivers);
    }

    [Fact]
    public void Calculate_ScoringRowsOnlyInput_EqualsFullInput()
    {
        // 두 주말 × (FP1 · 예선 · 레이스). d는 FP1에만 나온다. 모든 주말에서 레이스 행이 있는 드라이버만 Standings에 오른다.
        var full = new List<SeasonResultRow>();
        foreach (var (weekend, baseHours, racePoints) in new[] { (1, 0d, new[] { 25, 18, 15 }), (2, 10d, new[] { 18, 25, 15 }) })
        {
            var driverKeys = new[] { "player", "driver:2", "driver:3" };
            for (var i = 0; i < driverKeys.Length; i++)
            {
                var isPlayer = driverKeys[i] == "player";
                full.Add(Row(weekend * 10 + 1, weekend, driverKeys[i], i + 1, 0, SessionType.Practice, SessionKind.Practice1, baseHours + 1, isPlayer: isPlayer, teamId: i));
                full.Add(Row(weekend * 10 + 2, weekend, driverKeys[i], i + 1, 0, SessionType.Qualifying, SessionKind.Qualifying1, baseHours + 2, isPlayer: isPlayer, teamId: i));
                full.Add(Row(weekend * 10 + 3, weekend, driverKeys[i], i + 1, racePoints[i], SessionType.Race, SessionKind.Race, baseHours + 3, isPlayer: isPlayer, teamId: i));
            }

            full.Add(Row(weekend * 10 + 1, weekend, "driver:4", 4, 0, SessionType.Practice, SessionKind.Practice1, baseHours + 1));
        }

        var scoringOnly = full.Where(r => r.SessionType == SessionType.Race || r.Points > 0).ToList();

        var fromFull = StandingsCalculator.Calculate(SeasonSessionSelector.Select(full), GameCode);
        var fromScoring = StandingsCalculator.Calculate(SeasonSessionSelector.Select(scoringOnly), GameCode);

        Assert.Equal(3, fromFull.Drivers.Count);
        Assert.Equal(Describe(fromFull), Describe(fromScoring));
    }

    [Fact]
    public void Calculate_ScoringRowsOnlyInput_QualifyingOnlyRound_ChangesOnlyTheEmptyCell()
    {
        // 알려진 차이: 2라운드에는 예선 행(0점)만 있다. 전체 행 입력은 그 라운드의 빈 칸(순위·상태 null, 0점)을 담고,
        // 대상 행만 읽은 입력에는 그 행이 없어 칸도 없다. 순위·점수·우승·포디움·컨스트럭터는 같다(목록·상세가 같은 순위를 낸다).
        var full = new[]
        {
            Row(session: 1, weekend: 1, "a", 1, 25, hours: 10),
            Row(session: 1, weekend: 1, "b", 2, 18, hours: 10),
            Row(session: 2, weekend: 2, "a", 1, 0, SessionType.Qualifying, SessionKind.Qualifying1, 20),
            Row(session: 2, weekend: 2, "b", 2, 0, SessionType.Qualifying, SessionKind.Qualifying1, 20),
        };
        var scoringOnly = full.Where(r => r.SessionType == SessionType.Race || r.Points > 0).ToArray();

        var fromFull = StandingsCalculator.Calculate(SeasonSessionSelector.Select(full), GameCode);
        var fromScoring = StandingsCalculator.Calculate(SeasonSessionSelector.Select(scoringOnly), GameCode);

        Assert.Equal(DescribeWithoutCells(fromFull), DescribeWithoutCells(fromScoring));
        Assert.All(fromFull.Drivers, d => Assert.Equal(2, d.Cells.Count));
        Assert.All(fromScoring.Drivers, d => Assert.Single(d.Cells));
    }

    // ---- 표시 값 ----

    [Fact]
    public void Calculate_UsesLatestNameTeamAndAiFlag()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "driver:1", 1, 25, name: "OLD", teamId: 1, isAi: false, carIndex: 0, hours: 10),
            Row(session: 2, weekend: 2, "driver:1", 1, 25, name: "NEW", teamId: 2, isAi: true, carIndex: 3, hours: 20));

        var driver = Assert.Single(standings.Drivers);
        Assert.Equal("NEW", driver.Name);
        Assert.Equal(2, driver.TeamId);
        Assert.True(driver.IsAiControlled);
        Assert.False(driver.IsPlayer);
    }

    [Fact]
    public void Calculate_LatestValues_SameClassifiedAt_UseGreaterSessionId()
    {
        // 서로 다른 주말에서 시각이 같다. 시각이 같으면 Id가 큰 세션이 "가장 최근"이다(입력 순서·차 번호와 무관하게 결정적).
        var standings = Calculate(
            Row(session: 7, weekend: 2, "driver:1", 1, 25, name: "FROM7", carIndex: 5, hours: 10),
            Row(session: 3, weekend: 1, "driver:1", 1, 25, name: "FROM3", carIndex: 0, hours: 10));

        Assert.Equal("FROM7", Assert.Single(standings.Drivers).Name);
    }

    [Fact]
    public void Calculate_NullName_FallsBackToCarLabel()
    {
        var standings = Calculate(Unnamed(session: 1, weekend: 1, "car:s1:4", 1, 25, carIndex: 4, hours: 10));

        var driver = Assert.Single(standings.Drivers);
        Assert.Equal("Car 5", driver.Name);
    }

    [Fact]
    public void Calculate_PlayerRow_IsMarkedAsPlayer()
    {
        var standings = Calculate(Row(session: 1, weekend: 1, "player", 3, 15, isPlayer: true, isAi: false, hours: 10));

        var driver = Assert.Single(standings.Drivers);
        Assert.True(driver.IsPlayer);
        Assert.False(driver.IsAiControlled);
    }

    [Fact]
    public void Calculate_NoRows_ReturnsEmptyStandings()
    {
        var standings = Calculate();

        Assert.Empty(standings.Drivers);
        Assert.Empty(standings.Constructors);
    }

    // ---- 결과표 칸 ----

    [Fact]
    public void Calculate_Cells_OnlyRoundsWithResults()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 25, hours: 10),
            Row(session: 1, weekend: 1, "b", 2, 18, hours: 10),
            Row(session: 2, weekend: 2, "b", 1, 25, hours: 20));

        Assert.Single(standings.Drivers.Single(d => d.DriverKey == "a").Cells);
        Assert.Equal(2, standings.Drivers.Single(d => d.DriverKey == "b").Cells.Count);
    }

    [Fact]
    public void Calculate_Cells_AreOrderedByWeekendTime()
    {
        var standings = Calculate(
            Row(session: 2, weekend: 2, "a", 2, 18, hours: 20),
            Row(session: 1, weekend: 1, "a", 1, 25, hours: 10));

        var cells = standings.Drivers.Single().Cells;
        Assert.Equal(new[] { Id(1), Id(2) }, cells.Select(c => c.WeekendId));
        Assert.Equal(new int?[] { 1, 2 }, cells.Select(c => c.Position));
    }

    [Fact]
    public void Cells_SprintWeekend_UseMainRacePosition_AndSumWeekendPoints()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 3, 6, kind: SessionKind.Race, hours: 10),             // 스프린트 P3
            Row(session: 2, weekend: 1, "a", 1, 25, kind: SessionKind.Race2, hours: 14, status: ResultStatus.Finished));

        var cell = Assert.Single(standings.Drivers.Single().Cells);
        Assert.Equal(Id(1), cell.WeekendId);
        Assert.Equal(1, cell.Position);
        Assert.Equal(ResultStatus.Finished, cell.ResultStatus);
        Assert.Equal(31, cell.Points);
    }

    [Fact]
    public void Cells_WeekendWithoutRace_PositionAndStatusNull()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 25, hours: 10),
            Row(session: 2, weekend: 2, "a", 1, 0, type: SessionType.Qualifying, kind: SessionKind.Qualifying1, hours: 20));

        var cells = standings.Drivers.Single().Cells;
        Assert.Equal(2, cells.Count);
        Assert.Equal(1, cells[0].Position);
        Assert.Equal(Id(2), cells[1].WeekendId);
        Assert.Null(cells[1].Position);
        Assert.Null(cells[1].ResultStatus);
        Assert.Equal(0, cells[1].Points);
    }

    [Fact]
    public void Cells_DriverMissingFromMainRace_HasNullPositionButKeepsSprintPoints()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 8, kind: SessionKind.Race, hours: 10),             // a는 스프린트에만
            Row(session: 1, weekend: 1, "b", 2, 7, kind: SessionKind.Race, hours: 10),
            Row(session: 2, weekend: 1, "b", 1, 25, kind: SessionKind.Race2, hours: 14));

        var cell = Assert.Single(standings.Drivers.Single(d => d.DriverKey == "a").Cells);
        Assert.Null(cell.Position);
        Assert.Null(cell.ResultStatus);
        Assert.Equal(8, cell.Points);
    }

    [Fact]
    public void Cells_NotFinishedStatus_IsReportedFromMainRace()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 20, 0, status: ResultStatus.DidNotFinish, hours: 10));

        var cell = Assert.Single(standings.Drivers.Single().Cells);
        Assert.Equal(20, cell.Position);
        Assert.Equal(ResultStatus.DidNotFinish, cell.ResultStatus);
    }

    // ---- Constructors ----

    [Fact]
    public void Calculate_Constructors_SumByTeam_ExcludeNullTeam_TieByWinsThenNameThenTeamId()
    {
        var standings = Calculate(
            // 주말 1: 팀 2 우승(10), 팀 478 2위(0), 팀 8 두 명(5+4), 팀 없는 드라이버(99). 478이 입력에서 먼저 나온다.
            Row(session: 1, weekend: 1, "b", 2, 0, teamId: 478, hours: 10),
            Row(session: 1, weekend: 1, "a", 1, 10, teamId: 2, hours: 10),
            Row(session: 1, weekend: 1, "c", 3, 5, teamId: 8, hours: 10),
            Row(session: 1, weekend: 1, "d", 4, 4, teamId: 8, hours: 10),
            Row(session: 1, weekend: 1, "e", 5, 99, teamId: null, hours: 10),
            // 주말 2: 팀 478 우승(10), 팀 2 2위(0), 팀 8 3위(5)
            Row(session: 2, weekend: 2, "b", 1, 10, teamId: 478, hours: 20),
            Row(session: 2, weekend: 2, "a", 2, 0, teamId: 2, hours: 20),
            Row(session: 2, weekend: 2, "c", 3, 5, teamId: 8, hours: 20));

        // McLaren 14점 → Red Bull(2)와 Red Bull(478)은 10점·1승으로 동점, 이름도 같아 TeamId 순.
        Assert.Equal(
            new[] { (1, 8, 14, 0), (2, 2, 10, 1), (3, 478, 10, 1) },
            standings.Constructors.Select(c => (c.Position, c.TeamId, c.Points, c.Wins)));
        Assert.DoesNotContain(standings.Constructors, c => c.TeamId == 0);
        Assert.Equal(5, standings.Drivers.Count);
    }

    [Fact]
    public void Constructors_PointsTie_BrokenByWins()
    {
        // 이름 순으로는 Ferrari(1)가 앞이지만 McLaren(8)이 1승이라 먼저다.
        var standings = Calculate(
            Row(session: 1, weekend: 1, "f", 2, 10, teamId: 1, hours: 10),
            Row(session: 1, weekend: 1, "m", 1, 10, teamId: 8, hours: 10));

        Assert.Equal(new[] { 8, 1 }, standings.Constructors.Select(c => c.TeamId));
    }

    [Fact]
    public void Constructors_PointsAndWinsTie_BrokenByTeamName()
    {
        // Mercedes(0)와 Ferrari(1): ID 순으로는 Mercedes가 앞이지만 이름 순으로는 Ferrari가 앞이다.
        var standings = Calculate(
            Row(session: 1, weekend: 1, "m", 4, 10, teamId: 0, hours: 10),
            Row(session: 1, weekend: 1, "f", 5, 10, teamId: 1, hours: 10));

        Assert.Equal(new[] { 1, 0 }, standings.Constructors.Select(c => c.TeamId));
    }

    [Fact]
    public void Constructors_SprintPointsCount_ButSprintWinIsNotAWin()
    {
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, 8, teamId: 2, kind: SessionKind.Race, hours: 10),
            Row(session: 2, weekend: 1, "a", 2, 18, teamId: 2, kind: SessionKind.Race2, hours: 14));

        var team = Assert.Single(standings.Constructors);
        Assert.Equal(26, team.Points);
        Assert.Equal(0, team.Wins);
    }

    // ---- 큰 값 ----

    [Fact]
    public void Calculate_HugePoints_DoNotOverflow_AndOrderByTrueTotal()
    {
        const int Max = int.MaxValue;
        var standings = Calculate(
            Row(session: 1, weekend: 1, "a", 1, Max, kind: SessionKind.Race, hours: 10),            // 스프린트
            Row(session: 2, weekend: 1, "a", 1, Max, kind: SessionKind.Race2, hours: 14),
            Row(session: 2, weekend: 1, "b", 2, Max, kind: SessionKind.Race2, hours: 14),
            Row(session: 3, weekend: 2, "a", 1, Max, hours: 20),
            Row(session: 3, weekend: 2, "b", 2, Max - 1, hours: 20));

        // a = 3 * Max, b = 2 * Max - 1: 표시 값은 int 상한으로 자르지만 순서는 실제 합계로 정한다.
        Assert.Equal(new[] { "a", "b" }, standings.Drivers.Select(d => d.DriverKey));
        Assert.All(standings.Drivers, d => Assert.Equal(Max, d.Points));
        Assert.Equal(Max, standings.Drivers[0].Cells[0].Points);
        Assert.Equal(Max, Assert.Single(standings.Constructors).Points);
    }

    // ---- 우승자 이름 ----

    [Fact]
    public void WinnerNames_UseMainRaceWinner_WithCarFallback()
    {
        var selection = SeasonSessionSelector.Select(new[]
        {
            // 주말 1: 스프린트 우승자 X, 본 레이스 우승자는 이름이 없는 3번 차
            Row(session: 1, weekend: 1, "x", 1, 8, name: "SPRINTER", kind: SessionKind.Race, hours: 10),
            Unnamed(session: 2, weekend: 1, "car:s2:2", 1, 25, carIndex: 2, hours: 14) with { SessionKind = SessionKind.Race2 },
            // 주말 2: 이름 있는 우승자
            Row(session: 3, weekend: 2, "y", 1, 25, name: "NORRIS", hours: 20),
            // 주말 3: 예선만
            Row(session: 4, weekend: 3, "z", 1, 0, type: SessionType.Qualifying, kind: SessionKind.Qualifying1, hours: 30),
        });

        var winners = WinnerNames.ByWeekend(selection);

        Assert.Equal(2, winners.Count);
        Assert.Equal("Car 3", winners[Id(1)]);
        Assert.Equal("NORRIS", winners[Id(2)]);
        Assert.False(winners.ContainsKey(Id(3)));
    }

    // ---- 도우미 ----

    private static string Describe(SeasonStandings standings)
        => Describe(standings, includeCells: true);

    private static string DescribeWithoutCells(SeasonStandings standings)
        => Describe(standings, includeCells: false);

    private static string Describe(SeasonStandings standings, bool includeCells)
    {
        var drivers = standings.Drivers.Select(d =>
            $"{d.Position}|{d.DriverKey}|{d.Name}|{d.TeamId}|{d.IsPlayer}|{d.IsAiControlled}|{d.Points}|{d.Wins}|{d.Podiums}|"
            + (includeCells ? string.Join(",", d.Cells.Select(c => $"{c.WeekendId}:{c.Position}:{c.ResultStatus}:{c.Points}")) : string.Empty));
        var constructors = standings.Constructors.Select(c => $"{c.Position}|{c.TeamId}|{c.Points}|{c.Wins}");
        return string.Join("\n", drivers) + "\n--\n" + string.Join("\n", constructors);
    }
}
