using SimCenter.Application.Seasons.Import;
using SimCenter.Application.Seasons.Import.Building;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.Import.ImportTestData;

namespace SimCenter.Application.Tests.Seasons.Import;

/// <summary>docs/15 §12(D-55) 가져오기 그래프·미리보기: 라운드·세션 만들기, 기록 세션 연결, 스탠딩 기준선.</summary>
public sealed class SeasonImportBuilderTests
{
    private static readonly Guid UserId = Id(1);

    private static (SeasonImportGraph Graph, SeasonImportPreviewDto Preview) Build(string markdown, bool withMiami = false)
    {
        var bundle = ImportDocumentReader.Read(markdown);
        var tracks = Tracks();
        var linked = withMiami ? MiamiQualifying(tracks[6], UserId) : [];
        var counter = 10_000;
        var graph = SeasonImportBuilder.Build(new SeasonImportInput(
            UserId, bundle, tracks, linked, withMiami ? MiamiSeasonLink : -5, Now, () => Id(counter++)));
        var names = tracks.Values.ToDictionary(t => t.Id, t => t.Name);
        return (graph, SeasonImportPreviewMapper.Map(bundle, graph, names, withMiami ? MiamiSeasonLink : null, alreadyImported: false));
    }

    [Fact]
    public void Summary_only_creates_valued_rounds_with_player_rows()
    {
        var (graph, preview) = Build(Summary);

        Assert.Equal([1, 2, 3, 5], preview.Rounds.Select(r => r.Round));
        Assert.Equal(["Race"], preview.Rounds[0].Sessions.Select(s => s.SessionType));
        Assert.Equal(["ShortQualifying", "Race"], preview.Rounds[1].Sessions.Select(s => s.SessionKind));
        Assert.Equal(["Qualifying"], preview.Rounds[2].Sessions.Select(s => s.SessionType));
        Assert.All(graph.Sessions, s => Assert.True(s.IsImported));
        Assert.All(graph.Sessions, s => Assert.Null(s.AgentDeviceId));

        var australia = graph.Sessions.Single(s => s.ClassifiedAt == graph.Sessions.Min(x => x.ClassifiedAt));
        var me = Assert.Single(australia.Results);
        Assert.Equal((1, 25, 80_953, "GOM", true, 221), (me.Position, me.Points, me.BestLapTimeMs, me.DriverName, me.IsPlayer, me.TeamId));
        Assert.Equal((Weather?)Weather.Clear, australia.Weather);
        Assert.Equal(100, australia.AiDifficulty);

        Assert.Equal(("Oscar Piastri", 52), (preview.Drivers[0].Name, preview.Drivers[0].Points));
        Assert.Equal(("GOM", 50, true), (preview.Drivers[1].Name, preview.Drivers[1].Points, preview.Drivers[1].IsPlayer));
    }

    [Fact]
    public void Synthetic_times_follow_rounds_and_come_before_now()
    {
        var (graph, _) = Build(Summary);

        var ordered = graph.Sessions.OrderBy(s => s.ClassifiedAt).Select(s => graph.RoundByWeekend[s.RaceWeekendId!.Value]).ToList();
        Assert.Equal(ordered.Order(), ordered);
        Assert.All(graph.Sessions, s => Assert.True(s.ClassifiedAt < Now));
        Assert.Equal(graph.Sessions.Min(s => s.ClassifiedAt), graph.Season.FirstSessionAt);
    }

    [Fact]
    public void Linked_miami_sessions_become_round_six_without_summary_values()
    {
        var (graph, preview) = Build(Summary, withMiami: true);

        Assert.Equal([1, 2, 3, 5, 6], preview.Rounds.Select(r => r.Round));
        Assert.Equal(3, graph.Attachments.Count);
        Assert.All(graph.Attachments, a => Assert.Equal(MiamiWeekendLink, a.Weekend.WeekendLinkId));
        Assert.Equal(["Recorded", "Recorded", "Recorded"], preview.Rounds[^1].Sessions.Select(s => s.Source));
        Assert.Equal(MiamiSeasonLink, preview.LinkCandidate!.SeasonLinkId);
        Assert.True(graph.Sessions.Max(s => s.ClassifiedAt) < graph.Attachments.Min(a => a.Session.ClassifiedAt));
    }

    [Fact]
    public void In_game_standings_are_authoritative_for_drivers_and_constructors()
    {
        var (_, preview) = Build(All, withMiami: true);

        Assert.Equal(("Lando NORRIS", 93), (preview.Drivers[0].Name, preview.Drivers[0].Points));
        Assert.Equal(("Oscar PIASTRI", 79), (preview.Drivers[1].Name, preview.Drivers[1].Points));
        Assert.Equal(("GOMDOL SUPER", 75, true), (preview.Drivers[2].Name, preview.Drivers[2].Points, preview.Drivers[2].IsPlayer));
        Assert.Equal(22, preview.Drivers.Count);
        Assert.Equal(("McLaren", 172), (preview.Constructors[0].TeamName, preview.Constructors[0].Points));
        Assert.Equal(("Mercedes", 127), (preview.Constructors[1].TeamName, preview.Constructors[1].Points));
        Assert.Equal(("Ferrari", 109), (preview.Constructors[2].TeamName, preview.Constructors[2].Points));
        Assert.Equal(["InGameStandings", "F1LapsSeason", "F1LapsSession", "F1LapsSession"], preview.Documents.Select(d => d.Kind));
        Assert.Equal([1, 2, 3, 4, 5, 6], preview.Rounds.Select(r => r.Round));
    }

    [Fact]
    public void Main_race_merges_in_game_positions_with_f1laps_race_export()
    {
        var (graph, _) = Build(All);
        var australia = graph.Sessions.Single(s => graph.RoundByWeekend[s.RaceWeekendId!.Value] == 1 && s.SessionType == SessionType.Race);

        Assert.Equal(22, australia.Results.Count);
        Assert.Equal(29, australia.TotalLaps);
        var me = australia.Results.Single(r => r.IsPlayer);
        Assert.Equal((1, 25, 80_953, 1), (me.Position, me.Points, me.BestLapTimeMs, me.NumPitStops));
        Assert.Equal([(15, TyreCompound.Hard), (29, TyreCompound.Medium)], me.TyreStints.Select(s => (s.EndLap, s.VisualCompound)));

        var hamilton = australia.Results.Single(r => r.DriverName == "Lewis HAMILTON");
        Assert.Equal((2, 81_417, 221), (hamilton.Position, hamilton.BestLapTimeMs, hamilton.TeamId));

        var russell = australia.Results.Single(r => r.DriverName == "George RUSSELL");
        Assert.Equal((ResultStatus.DidNotFinish, 21), (russell.ResultStatus, russell.Position));

        var imported = ImportedSessionDetails.TryRead(australia.Details)!;
        var verstappen = australia.Results.Single(r => r.DriverName == "Max VERSTAPPEN");
        Assert.Equal(verstappen.CarIndex, imported.FastestLapCarIndex);
        Assert.Equal(12_364, imported.Gaps.Single(g => g.CarIndex == hamilton.CarIndex).GapMs);
        Assert.Equal(3, imported.Penalties.Count);
        Assert.Equal(25, imported.Setup!.Value.GetProperty("frontWing").GetInt32());
        Assert.Equal(6, SessionHistory.Parse(australia.Details).LapsOf(me.CarIndex).Count);
    }

    [Fact]
    public void Sprint_shootout_export_keeps_positions_and_ignores_buggy_points()
    {
        var (graph, preview) = Build(All);
        var china = preview.Rounds.Single(r => r.Round == 2);
        Assert.Equal(["SprintShootout3", "ShortQualifying", "Race2"], china.Sessions.Select(s => s.SessionKind));

        var shootout = graph.Sessions.Single(s => s.SessionKind == SessionKind.SprintShootout3);
        Assert.All(shootout.Results, r => Assert.Equal(0, r.Points));
        Assert.Equal(9, shootout.Results.Single(r => r.IsPlayer).Position);
        Assert.Empty(ImportedSessionDetails.TryRead(shootout.Details)!.Gaps);
    }

    [Fact]
    public void Round_without_f1laps_export_uses_in_game_results_only()
    {
        var (graph, _) = Build(All);
        var bahrain = graph.Sessions.Single(s => graph.RoundByWeekend[s.RaceWeekendId!.Value] == 4);

        Assert.Equal(22, bahrain.Results.Count);
        Assert.Equal(("Lando NORRIS", 25), bahrain.Results.Where(r => r.Position == 1).Select(r => (r.DriverName!, r.Points)).Single());
        Assert.Equal(22, bahrain.Results.Single(r => r.IsPlayer).Position);
    }

    [Fact]
    public void Recorded_session_wins_over_export_of_same_kind()
    {
        var miamiQ1 = """

            # Miami Qualifying 1

            **Game**: F1 2025 | **Session**: Qualifying 1 | **Mode**: Driver Career | **Finish Position**: P3

            ## Classification

            | Pos | Driver | Team | Best Lap | Gap | Points |
            | --- | --- | --- | --- | --- | --- |
            | 3 | You | F1 Generic | 1:27.000 | - | - |
            """;
        var (graph, _) = Build(Summary + miamiQ1, withMiami: true);

        Assert.DoesNotContain(graph.Sessions, s => s.SessionKind == SessionKind.Qualifying1);
    }
}
