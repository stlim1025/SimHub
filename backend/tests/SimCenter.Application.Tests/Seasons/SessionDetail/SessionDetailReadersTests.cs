using SimCenter.Application.Common;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;
using static SimCenter.Application.Tests.Seasons.SessionDetail.SessionDetailSamples;

namespace SimCenter.Application.Tests.Seasons.SessionDetail;

/// <summary>저장된 jsonb 읽기(docs/15 §11.4): 세션 기록·스냅샷 details·카탈로그·번호 매기기.</summary>
public class SessionDetailReadersTests
{
    // ---- SessionHistory ----

    [Fact]
    public void SessionHistory_ParsesLapHistoryAndPositions()
    {
        var history = SessionHistory.Parse(SessionDetailsJson);

        var mine = history.LapsOf(0);
        Assert.Equal(new[] { 1, 2, 3, 4 }, mine.Select(l => l.LapNumber));
        Assert.Equal((92044, 30903, 31870, 29271), (mine[1].LapTimeMs, mine[1].Sector1TimeMs, mine[1].Sector2TimeMs, mine[1].Sector3TimeMs));
        Assert.False(mine[2].LapValid);
        Assert.False(mine[2].Sector2Valid);
        Assert.Single(history.LapsOf(1));
        Assert.Empty(history.LapsOf(7));
        Assert.Empty(history.LapsOf(null));

        Assert.Equal(3, history.PositionOf(0, 2));
        Assert.Null(history.PositionOf(0, 9));
        Assert.Null(history.PositionOf(40, 1));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("not json")]
    [InlineData("[1,2]")]
    [InlineData("""{"lapHistory": "x", "lapPositions": [{"lapNumber": "1"}]}""")]
    public void SessionHistory_BrokenOrMissing_IsEmpty(string? json)
    {
        var history = SessionHistory.Parse(json);

        Assert.Empty(history.LapsByCar);
        Assert.Empty(history.PositionsByLap);
    }

    [Fact]
    public void SessionHistory_ZeroPosition_IsNull()
    {
        var history = SessionHistory.Parse("""{"lapPositions":[{"lapNumber":1,"positions":[0,2]}]}""");

        Assert.Null(history.PositionOf(0, 1));
        Assert.Equal(2, history.PositionOf(1, 1));
    }

    // ---- MySessionLap (스냅샷 details 키) ----

    [Fact]
    public void MySessionLap_ReadsAgentDetailKeys()
    {
        var lap = Lap(2, 92_044, details: SnapshotDetailsJson(pitStatus: 1), wear: 10);

        Assert.NotNull(lap.Setup);
        Assert.Equal(8, lap.Setup!.Value.GetProperty("frontWing").GetInt32());
        Assert.Equal(new EngineComponentWear(Ice: 12, TurboCharger: 10, MguH: 9, MguK: 8, EnergyStore: 7, ControlElectronics: 6), lap.EngineWear);
        Assert.Equal(1, lap.PitStatus);
        Assert.Equal(0, lap.PlayerCarIndex);
        Assert.Equal(3, lap.Penalties.Count);                  // OVTK는 빠진다
        Assert.Equal(new PenaltyEvent(4, 7, 1, 255, 5, 2), lap.Penalties[2]);
        Assert.Equal(89.0, lap.TyreLifeRemaining);              // 100 − 평균(10, 10, 12, 12)
    }

    [Theory]
    [InlineData(null)]
    [InlineData("{broken")]
    [InlineData("""{"damage": {"engineIceWear": "x"}, "events": {"code": "PENA"}, "lapData": []}""")]
    public void MySessionLap_BrokenOrMissingDetails_AllNull(string? details)
    {
        var lap = Lap(1, 90_000, details: details);

        Assert.Null(lap.Setup);
        Assert.Null(lap.EngineWear);
        Assert.Null(lap.PitStatus);
        Assert.Null(lap.PlayerCarIndex);
        Assert.Empty(lap.Penalties);
        Assert.Null(lap.TyreLifeRemaining);
    }

    [Fact]
    public void MySessionLap_ParticipantCarIndex_WhenNoLapData()
    {
        var lap = Lap(1, 90_000, details: """{"participant": {"carIndex": 7}}""");

        Assert.Equal(7, lap.PlayerCarIndex);
    }

    // ---- 최신 랩 값 ----

    [Fact]
    public void LatestLapValues_UseHighestLapThatHasTheValue()
    {
        var laps = new[]
        {
            Lap(1, 91_000, details: SnapshotDetailsJson(iceWear: 11)),
            Lap(2, 90_000, details: SnapshotDetailsJson(iceWear: 13), gearbox: 4, engine: 2),
            Lap(3, 89_000, details: """{"lapData": {"pitStatus": 0}}"""),
            MySessionLap.From(LapRow(4, 0, weather: Weather.Overcast)),
        };

        var wear = LatestLapValues.EngineWear(laps);

        Assert.Equal(new EngineWearDto(13, 10, 9, 8, 7, 6, 4, 2), wear);
        Assert.Equal(8, LatestLapValues.Setup(laps)!.Value.GetProperty("frontWing").GetInt32());
        Assert.Equal("Overcast", LatestLapValues.Weather(laps));
    }

    [Fact]
    public void LatestLapValues_ColumnsOnly_StillGivesEngineWear()
    {
        var wear = LatestLapValues.EngineWear([Lap(1, 90_000, gearbox: 3, engine: 1)]);

        Assert.Equal(new EngineWearDto(null, null, null, null, null, null, 3, 1), wear);
    }

    [Fact]
    public void LatestLapValues_NoData_Null()
    {
        var laps = new[] { Lap(1, 90_000) };

        Assert.Null(LatestLapValues.EngineWear(laps));
        Assert.Null(LatestLapValues.Setup(laps));
        Assert.Null(LatestLapValues.Weather(laps));
        Assert.Null(LatestLapValues.EngineWear([]));
    }

    // ---- 카탈로그·번호 ----

    [Theory]
    [InlineData(0, "Drive through")]
    [InlineData(4, "Time penalty")]
    [InlineData(5, "Warning")]
    [InlineData(12, "This lap invalidated without reason")]
    [InlineData(17, "Black flag timer")]
    [InlineData(18, "Unknown (18)")]
    [InlineData(-1, "Unknown (-1)")]
    public void PenaltyCatalog_PenaltyNames(int type, string name)
        => Assert.Equal(name, PenaltyCatalog.PenaltyName(type));

    [Theory]
    [InlineData(0, "Blocking by slow driving")]
    [InlineData(4, "Small Collision")]
    [InlineData(7, "Corner cutting gained time")]
    [InlineData(26, "Lap invalidated running wide")]
    [InlineData(54, "Attribute assigned")]
    [InlineData(55, "Unknown (55)")]
    public void PenaltyCatalog_InfringementNames(int type, string name)
        => Assert.Equal(name, PenaltyCatalog.InfringementName(type));

    [Fact]
    public void PenaltyCatalog_TableSizesMatchSpec()
    {
        Assert.Equal(18, PenaltyCatalog.PenaltyTypeCount);
        Assert.Equal(55, PenaltyCatalog.InfringementTypeCount);
        Assert.Equal("Unknown (-)", PenaltyCatalog.PenaltyName(null));
    }

    [Fact]
    public void SeasonNumbering_CountsPerGameAndMode_ByFirstSession()
    {
        var numbers = SeasonNumbering.Assign(
        [
            new SeasonOrderRow(Id(3), "F1_25", GameMode.DriverCareer, At(30)),
            new SeasonOrderRow(Id(1), "F1_25", GameMode.DriverCareer, At(10)),
            new SeasonOrderRow(Id(2), "F1_25", GameMode.MyTeamCareer, At(20)),
            new SeasonOrderRow(Id(4), "F1_24", GameMode.DriverCareer, At(5)),
        ]);

        Assert.Equal(1, SeasonNumbering.Of(numbers, Id(1)));
        Assert.Equal(2, SeasonNumbering.Of(numbers, Id(3)));
        Assert.Equal(1, SeasonNumbering.Of(numbers, Id(2)));
        Assert.Equal(1, SeasonNumbering.Of(numbers, Id(4)));
        Assert.Null(SeasonNumbering.Of(numbers, Id(9)));
        Assert.Null(SeasonNumbering.Of(numbers, null));
    }
}
