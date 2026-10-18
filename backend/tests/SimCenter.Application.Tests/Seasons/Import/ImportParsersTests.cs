using SimCenter.Application.Common;
using SimCenter.Application.Seasons.Import;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.Import.ImportTestData;

namespace SimCenter.Application.Tests.Seasons.Import;

/// <summary>docs/15 §12(D-55) 가져오기 문서 파서: F1Laps 시즌 요약 · 인게임 순위표 · F1Laps 세션 · 여러 문서 나누기.</summary>
public sealed class ImportParsersTests
{
    [Fact]
    public void Summary_fixture_parses_header_rounds_and_standings()
    {
        var doc = F1LapsSeasonMarkdownParser.Parse(Summary);

        Assert.Equal("Driver Career", doc.Title);
        Assert.Equal(GameCodes.F1_25, doc.GameCode);
        Assert.Equal(GameMode.DriverCareer, doc.GameMode);
        Assert.Equal("Ferrari", doc.TeamName);
        Assert.Equal("GOM", doc.PlayerName);
        Assert.Equal(24, doc.Rounds.Count);

        var australia = doc.Rounds[0];
        Assert.Equal((1, "Australia", (int?)null, (int?)1, (int?)25, (int?)80_953, "Dry", (int?)100, (int?)105),
            (australia.Number, australia.TrackName, australia.QualifyingPosition, australia.RacePosition, australia.Points,
                australia.BestLapTimeMs, australia.Conditions, australia.RaceAiDifficulty, australia.QualifyingAiDifficulty));
        Assert.True(doc.Rounds[2].HasQualifying);
        Assert.False(doc.Rounds[2].HasRace);
        Assert.False(doc.Rounds[3].HasAnyValue);
        Assert.Equal([1, 2, 3, 5], doc.Rounds.Where(r => r.HasRace || r.HasQualifying).Select(r => r.Number));

        Assert.Equal(22, doc.Drivers.Count);
        Assert.Equal(new F1LapsDriverPoints(1, "Oscar Piastri", 52, false), doc.Drivers[0]);
        Assert.Equal(new F1LapsDriverPoints(2, "You", 50, true), doc.Drivers[1]);
    }

    [Fact]
    public void Summary_tolerates_extra_spaces_and_markers()
    {
        var markdown = Summary
            .Replace("| 1 | Australia | - | 1 |", "|  1  |   Australia   |  -  |  **1**  |", StringComparison.Ordinal)
            .Replace("**Name**: GOM", "**Name**:   GOM  ", StringComparison.Ordinal);

        var doc = F1LapsSeasonMarkdownParser.Parse(markdown);

        Assert.Equal("GOM", doc.PlayerName);
        Assert.Equal(1, doc.Rounds[0].RacePosition);
        Assert.Equal("Australia", doc.Rounds[0].TrackName);
    }

    [Fact]
    public void Summary_bad_lap_time_reports_line_number()
    {
        var markdown = Summary.Replace("1:20.953", "1:2x.953", StringComparison.Ordinal);

        var error = Assert.Throws<F1LapsFormatException>(() => F1LapsSeasonMarkdownParser.Parse(markdown));

        Assert.Equal(9, error.LineNumber);
        Assert.Contains("Best Lap", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Summary_unknown_game_is_rejected_on_header_line()
    {
        var error = Assert.Throws<F1LapsFormatException>(
            () => F1LapsSeasonMarkdownParser.Parse(Summary.Replace("F1 2025", "F1 2019", StringComparison.Ordinal)));

        Assert.Equal(3, error.LineNumber);
    }

    [Fact]
    public void InGame_fixture_parses_cells_totals_and_constructors()
    {
        var bundle = ImportDocumentReader.Read(InGame);
        var doc = Assert.IsType<InGameStandingsDocument>(bundle.InGame);

        Assert.Equal("Season 1", doc.Title);
        Assert.Equal("GOMDOL SUPER", doc.PlayerName);
        Assert.Equal([1, 2, 3, 4, 5], doc.Rounds);
        Assert.Equal(22, doc.Drivers.Count);

        var norris = doc.Drivers[0];
        Assert.Equal(("Lando NORRIS", "McLaren", 93), (norris.Name, norris.TeamName, norris.Total));
        Assert.Equal(new InGameRaceCell(3, 2, ResultStatus.Finished, FastestLap: true), norris.Cells[2]);

        var russell = doc.Drivers.Single(d => d.Name == "George RUSSELL");
        Assert.Equal(new InGameRaceCell(1, null, ResultStatus.DidNotFinish, FastestLap: false), russell.Cells[0]);

        var me = doc.Drivers.Single(d => d.IsPlayer);
        Assert.Equal(("GOMDOL SUPER", 75), (me.Name, me.Total));
        Assert.Equal(11, doc.Constructors.Count);
        Assert.Equal(new InGameConstructorRow("McLaren", 172), doc.Constructors[0]);
    }

    [Fact]
    public void Session_sample_parses_both_documents()
    {
        var bundle = ImportDocumentReader.Read(string.Join("\n", InGame, Sessions));

        Assert.Equal(2, bundle.Sessions.Count);
        var race = bundle.Sessions[0];
        Assert.Equal((1, "Australia", SessionType.Race, SessionKind.Race, false), (race.Round, race.TrackName, race.SessionType, race.SessionKind, race.IsSprint));
        Assert.Equal(("Dry", (int?)100, (int?)1, (int?)25, (int?)29), (race.Conditions, race.AiDifficulty, race.FinishPosition, race.Points, race.TotalLaps));
        Assert.Equal(25, race.Setup["frontWing"]);
        Assert.Equal(60, race.Setup["onThrottle"]);
        Assert.Equal(25, race.Setup["frontSuspensionHeight"]);
        Assert.Equal(24.200000762939453, race.Setup["tyrePressureFR"]);
        Assert.Equal(6, race.Laps.Count);
        Assert.Equal(new F1LapsLap(16, 2, TyreCompound.Medium, true, 96_899, 29_114, 18_034, 49_751), race.Laps[3]);
        Assert.True(race.Classification[0].IsPlayer);
        Assert.Equal(12_364, race.Classification[1].GapMs);
        Assert.Equal(551_820, race.Classification[5].GapMs);
        Assert.Equal(3, race.Penalties.Count);
        Assert.Equal([TyreCompound.Hard, TyreCompound.Medium], race.TyreStrategy);

        var shootout = bundle.Sessions[1];
        Assert.Equal((2, SessionType.Qualifying, SessionKind.SprintShootout3), (shootout.Round, shootout.SessionType, shootout.SessionKind));
        Assert.Equal(9, shootout.FinishPosition);
    }

    [Fact]
    public void Reader_combines_all_documents()
    {
        var bundle = ImportDocumentReader.Read(All);

        Assert.NotNull(bundle.InGame);
        Assert.NotNull(bundle.Summary);
        Assert.Equal(2, bundle.Sessions.Count);
        Assert.Equal("Season 1", bundle.Title);
        Assert.Equal("GOMDOL SUPER", bundle.PlayerName);
    }

    [Fact]
    public void Reader_rejects_documents_of_another_mode()
    {
        var other = Sessions.Replace("**Mode**: Driver Career | **Team**: Ferrari | **Conditions**: Dry | **Difficulty**: 103",
            "**Mode**: My Team | **Team**: Ferrari | **Conditions**: Dry | **Difficulty**: 103", StringComparison.Ordinal);

        var error = Assert.Throws<F1LapsFormatException>(() => ImportDocumentReader.Read(string.Join("\n", InGame, other)));

        Assert.Contains("China Sprint Shootout 3", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Reader_needs_a_season_document_and_reports_unknown_titles()
    {
        Assert.Throws<F1LapsFormatException>(() => ImportDocumentReader.Read(Sessions));

        var error = Assert.Throws<F1LapsFormatException>(() => ImportDocumentReader.Read(InGame + "\n# Random Notes\n\ntext"));
        Assert.Contains("Random Notes", error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("Australia", 1)]
    [InlineData("Saudi Arabia", 5)]
    [InlineData("United States (Miami)", 6)]
    [InlineData("Unites States (Las Vegas)", 22)]
    [InlineData("Italy (Monza)", 16)]
    [InlineData("Abu Dhabi", 24)]
    public void Calendar_maps_f1laps_names(string name, int round) => Assert.Equal(round, ImportCalendar.RoundOfName(name));

    [Theory]
    [InlineData("AUS", 1)]
    [InlineData("BHR", 4)]
    [InlineData("SAU", 5)]
    [InlineData("ABU", 24)]
    public void Calendar_maps_codes(string code, int round) => Assert.Equal(round, ImportCalendar.RoundOfCode(code));

    [Theory]
    [InlineData("Scuderia Ferrari HP", "Ferrari")]
    [InlineData("Ferrari", "Ferrari")]
    [InlineData("Mercedes-AMG F1 Team", "Mercedes")]
    [InlineData("Oracle Red Bull Racing", "Red Bull Racing")]
    [InlineData("Visa Cash App Racing Bulls", "Racing Bulls")]
    [InlineData("Atlassian Williams F1 Team", "Williams")]
    [InlineData("Aston Martin Aramco", "Aston Martin")]
    [InlineData("Cadillac Formula 1® Team", "Cadillac")]
    [InlineData("Audi Revolut F1 Team", "Audi")]
    [InlineData("McLaren", "McLaren")]
    public void Teams_map_in_game_names_to_2026_grid(string name, string expected)
    {
        var id = ImportTeams.Resolve(name);

        Assert.InRange(id!.Value, 220, 230);
        Assert.Equal(expected, TeamCatalog.Resolve(GameCodes.F1_25, id).Name);
    }

    [Fact]
    public void Teams_unknown_or_generic_is_null() => Assert.Null(ImportTeams.Resolve("F1 Generic"));

    [Theory]
    [InlineData("Sergio Perez", "PÉREZ", true)]
    [InlineData("Andrea-Kimi Antonelli", "ANTONELLI", true)]
    [InlineData("Nico Hulkenberg", "Nico HÜLKENBERG", true)]
    [InlineData("Lando Norris", "Oscar PIASTRI", false)]
    public void Names_match_by_surname_ignoring_case_and_accents(string imported, string game, bool expected)
        => Assert.Equal(expected, DriverNameMatcher.IsSurnameMatch(imported, game));

    [Fact]
    public void Names_full_match_ignores_case_and_accents()
        => Assert.True(DriverNameMatcher.IsFullMatch("Sergio Perez", "Sergio PÉREZ"));

    [Fact]
    public void Penalty_names_map_back_to_catalog_numbers()
    {
        Assert.Equal("Warning", PenaltyCatalog.PenaltyName(PenaltyCatalog.FindPenaltyType("Warning")));
        Assert.Equal("Small Collision", PenaltyCatalog.InfringementName(PenaltyCatalog.FindInfringementType("small collision")));
        Assert.Null(PenaltyCatalog.FindInfringementType("Something Else"));
    }
}
