using SimCenter.Application.Seasons.Import;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons.Import;

/// <summary>docs/15 §12(D-55) 가져온 시즌 Standings: 기준선 + 가져온 뒤 기록된 세션 점수, 이름 맞추기, 컨스트럭터.</summary>
public sealed class StandingsBaselineTests
{
    private const string GameCode = "F1_25";

    private static SeasonStandings Calculate(ImportedSeasonSnapshot snapshot, params SeasonResultRow[] rows)
        => StandingsCalculator.Calculate(SeasonSessionSelector.Select(rows), GameCode, snapshot);

    private static ImportedSeasonSnapshot Snapshot(IReadOnlyList<ImportedConstructorPoints>? constructors, params ImportedDriverPoints[] drivers)
        => new("Season 1", "GOM", "Ferrari", "InGame", drivers, constructors);

    [Fact]
    public void Imported_rows_do_not_add_points_but_later_sessions_do()
    {
        var snapshot = Snapshot(null,
            new ImportedDriverPoints("Oscar Piastri", 52, false),
            new ImportedDriverPoints("You", 50, true, 221));

        var standings = Calculate(snapshot,
            Row(1, 1, "player", 1, 25, isPlayer: true, isAi: false, teamId: 221, name: "GOM") with { IsImported = true },
            Row(2, 2, "player", 1, 25, hours: 48, isPlayer: true, isAi: false, teamId: 221, name: "GOM"),
            Row(2, 2, "driver:9", 2, 18, hours: 48, name: "PIASTRI", teamId: 228));

        Assert.Equal(("GOM", 75), (standings.Drivers[0].Name, standings.Drivers[0].Points));
        Assert.Equal(("PIASTRI", 70), (standings.Drivers[1].Name, standings.Drivers[1].Points));
        Assert.Equal(2, standings.Drivers[0].Wins);
        Assert.Equal(2, standings.Drivers.Count);
    }

    /// <summary>
    /// 기준선 = 1주말(가져온 세션) 뒤 순위표. 2주말 레이스는 가져오기 전에 기록됐지만(시각 2h ≤ 가져온 시각 3h)
    /// 넣으면 피아스트리가 기준선을 넘으므로 기준선에 없다고 보고 더한다(순위표를 찍은 뒤 레이스를 하고 가져온 경우).
    /// </summary>
    [Fact]
    public void Recorded_race_before_import_that_overshoots_the_baseline_is_added()
    {
        var snapshot = Snapshot(null,
            new ImportedDriverPoints("Oscar PIASTRI", 25, false),
            new ImportedDriverPoints("Lando NORRIS", 18, false),
            new ImportedDriverPoints("You", 15, true));

        var standings = StandingsCalculator.Calculate(SeasonSessionSelector.Select(
            [
                Row(1, 1, "name:OSCAR PIASTRI#", 1, 25, name: "Oscar PIASTRI") with { IsImported = true },
                Row(1, 1, "name:LANDO NORRIS#", 2, 18, name: "Lando NORRIS") with { IsImported = true },
                Row(1, 1, "player", 3, 15, isPlayer: true, isAi: false, name: "GOM") with { IsImported = true },
                Row(2, 2, "driver:112", 1, 25, hours: 2, name: "PIASTRI"),
                Row(2, 2, "driver:54", 2, 18, hours: 2, name: "NORRIS"),
                Row(2, 2, "player", 3, 15, hours: 2, isPlayer: true, isAi: false, name: "GOM"),
            ]), GameCode, snapshot, importedAt: At(3));

        Assert.Equal([("PIASTRI", 50), ("NORRIS", 36), ("GOM", 30)], standings.Drivers.Select(d => (d.Name, d.Points)));
    }

    /// <summary>가져오기 전에 기록된 세션이 기준선과 맞으면(가져온 세션만으론 모자람) 이미 들어 있다고 보고 더하지 않는다.</summary>
    [Fact]
    public void Recorded_race_before_import_that_fills_the_baseline_is_covered()
    {
        var snapshot = Snapshot(null, new ImportedDriverPoints("Oscar PIASTRI", 50, false));

        var standings = StandingsCalculator.Calculate(SeasonSessionSelector.Select(
            [
                Row(1, 1, "name:OSCAR PIASTRI#", 1, 25, name: "Oscar PIASTRI") with { IsImported = true },
                Row(2, 2, "driver:112", 1, 25, hours: 2, name: "PIASTRI"),
                Row(3, 3, "driver:112", 2, 18, hours: 5, name: "PIASTRI"),
            ]), GameCode, snapshot, importedAt: At(3));

        // 2주말(가져오기 전)은 기준선에 들어 있고, 3주말(가져온 뒤)만 더한다.
        Assert.Equal(68, Assert.Single(standings.Drivers).Points);
    }

    /// <summary>가져온 뒤에 기록된 세션은 점수가 기준선과 맞아도 기준선에 넣지 않는다.</summary>
    [Fact]
    public void Recorded_race_after_import_is_never_covered()
    {
        var snapshot = Snapshot(null, new ImportedDriverPoints("Oscar PIASTRI", 50, false));

        var standings = StandingsCalculator.Calculate(SeasonSessionSelector.Select(
            [
                Row(1, 1, "name:OSCAR PIASTRI#", 1, 25, name: "Oscar PIASTRI") with { IsImported = true },
                Row(2, 2, "driver:112", 1, 25, hours: 5, name: "PIASTRI"),
            ]), GameCode, snapshot, importedAt: At(3));

        Assert.Equal(75, Assert.Single(standings.Drivers).Points);
    }

    [Fact]
    public void Unmatched_baseline_drivers_appear_without_records()
    {
        var standings = Calculate(Snapshot(null, new ImportedDriverPoints("Valtteri Bottas", 3, false, 230)),
            Row(1, 1, "player", 5, 10, isPlayer: true, isAi: false) with { IsImported = true });

        var bottas = standings.Drivers.Single(d => d.Name == "Valtteri Bottas");
        Assert.Equal((3, 230, true), (bottas.Points, bottas.TeamId, bottas.Cells.Count == 0));
        Assert.Equal(0, standings.Drivers.Single(d => d.IsPlayer).Points);
    }

    [Fact]
    public void Imported_and_game_rows_of_same_driver_are_merged()
    {
        var snapshot = Snapshot(null, new ImportedDriverPoints("Lando NORRIS", 93, false, 228));

        var standings = Calculate(snapshot,
            Row(1, 1, "name:LANDO NORRIS#", 1, 25, name: "Lando NORRIS", teamId: 228) with { IsImported = true },
            Row(2, 2, "driver:5", 3, 15, hours: 48, name: "NORRIS", teamId: 228));

        var norris = Assert.Single(standings.Drivers);
        Assert.Equal((108, "driver:5", 2), (norris.Points, norris.DriverKey, norris.Cells.Count));
    }

    [Fact]
    public void Constructor_baseline_adds_later_points_by_session_team()
    {
        var snapshot = Snapshot(
            [new ImportedConstructorPoints(228, 172), new ImportedConstructorPoints(220, 127)],
            new ImportedDriverPoints("Lando NORRIS", 93, false, 228));

        var standings = Calculate(snapshot,
            Row(1, 1, "name:LANDO NORRIS#", 1, 25, name: "Lando NORRIS", teamId: 228) with { IsImported = true },
            Row(2, 2, "driver:7", 1, 25, hours: 48, name: "RUSSELL", teamId: 220),
            Row(2, 2, "driver:5", 2, 18, hours: 48, name: "NORRIS", teamId: 228));

        Assert.Equal([(228, 190), (220, 152)], standings.Constructors.Select(c => (c.TeamId, c.Points)));
        Assert.Equal(1, standings.Constructors[0].Wins);
    }

    [Fact]
    public void Without_constructor_baseline_teams_are_summed_from_drivers()
    {
        var snapshot = Snapshot(null,
            new ImportedDriverPoints("Oscar Piastri", 52, false),
            new ImportedDriverPoints("You", 50, true, 221));

        var standings = Calculate(snapshot,
            Row(1, 1, "player", 1, 25, isPlayer: true, isAi: false, teamId: 221, name: "GOM") with { IsImported = true });

        var ferrari = Assert.Single(standings.Constructors);
        Assert.Equal((221, 50), (ferrari.TeamId, ferrari.Points));
    }

    [Fact]
    public void Calendar_rounds_use_track_display_order_for_imported_seasons()
    {
        var rounds = RoundNumbering.Assign(
        [
            new WeekendRow(Id(1), Id(9), "Melbourne", At(1), DisplayOrder: 1, CalendarRounds: true),
            new WeekendRow(Id(2), Id(9), "Jeddah", At(2), DisplayOrder: 5, CalendarRounds: true),
            new WeekendRow(Id(3), Id(9), "Miami", At(3), DisplayOrder: 6, CalendarRounds: true),
            new WeekendRow(Id(4), Id(9), "Madrid", At(4), DisplayOrder: 0, CalendarRounds: true),
        ]);

        Assert.Equal([1, 5, 6, 7], [rounds[Id(1)], rounds[Id(2)], rounds[Id(3)], rounds[Id(4)]]);
    }

    [Fact]
    public void Imported_flag_defaults_off_for_recorded_seasons()
    {
        var rounds = RoundNumbering.Assign([new WeekendRow(Id(2), Id(9), "Jeddah", At(2), DisplayOrder: 5)]);

        Assert.Equal(1, rounds[Id(2)]);
        Assert.False(Row(1, 1, "a", 1, 1).IsImported);
        Assert.Equal(ResultStatus.Finished, Row(1, 1, "a", 1, 1).ResultStatus);
    }
}
