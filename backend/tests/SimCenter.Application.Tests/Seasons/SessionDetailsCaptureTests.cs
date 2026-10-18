using System.Text.Json;
using SimCenter.Application.Seasons.Ingest;

namespace SimCenter.Application.Tests.Seasons;

/// <summary>SessionClassified 랩별 기록·순위 묶음(D-49): 받은 그대로 한 객체로, 저장할 수 없으면 버림.</summary>
public class SessionDetailsCaptureTests
{
    private static JsonElement Parse(string json) => JsonDocument.Parse(json).RootElement.Clone();

    [Fact]
    public void BothMissing_IsNull_WithoutReason()
    {
        Assert.Null(SessionDetailsCapture.Build(null, null, out var reason));
        Assert.Null(reason);
        Assert.Null(SessionDetailsCapture.Build(Parse("null"), Parse("null"), out reason));
        Assert.Null(reason);
    }

    [Fact]
    public void BothPresent_AreWrappedVerbatim()
    {
        var history = Parse("[{\"carIndex\":0,\"laps\":[{\"lapTimeMs\":83452,\"valid\":true}]}]");
        var positions = Parse("{\"numLaps\":2,\"positions\":[[1,2],[2,1]]}");

        var details = SessionDetailsCapture.Build(history, positions, out var reason);

        Assert.Null(reason);
        using var document = JsonDocument.Parse(details!);
        Assert.Equal(history.GetRawText(), document.RootElement.GetProperty("lapHistory").GetRawText());
        Assert.Equal(positions.GetRawText(), document.RootElement.GetProperty("lapPositions").GetRawText());
    }

    [Fact]
    public void HistoryFromResults_IsCollectedPerCar_WhenTopLevelMissing()
    {
        // Agent(D-49)는 랩 기록을 순위표 행마다 results[].lapHistory로 보낸다.
        var results = new[]
        {
            Result(carIndex: 0, lapHistory: Parse("[{\"lapNumber\":1,\"lapTimeMs\":83452}]")),
            Result(carIndex: 3, lapHistory: null),
            Result(carIndex: 5, lapHistory: Parse("[{\"lapNumber\":1,\"lapTimeMs\":84000}]")),
        };

        var history = SessionDetailsCapture.HistoryFromResults(results);

        Assert.Equal(
            "[{\"carIndex\":0,\"laps\":[{\"lapNumber\":1,\"lapTimeMs\":83452}]},{\"carIndex\":5,\"laps\":[{\"lapNumber\":1,\"lapTimeMs\":84000}]}]",
            history!.Value.GetRawText());
    }

    [Fact]
    public void HistoryFromResults_IsNull_WhenNoCarHasHistory()
    {
        Assert.Null(SessionDetailsCapture.HistoryFromResults([Result(carIndex: 0, lapHistory: null)]));
        Assert.Null(SessionDetailsCapture.HistoryFromResults(null));
    }

    private static ClassifiedResultDto Result(int carIndex, JsonElement? lapHistory) => new(
        carIndex, IsPlayer: carIndex == 0, Position: carIndex + 1, GridPosition: 1, NumLaps: 1, Points: 0, NumPitStops: 0,
        NumPenalties: 0, ResultStatus: "Finished", BestLapTimeMs: 83452, TotalRaceTimeMs: 83452, PenaltiesTimeMs: 0,
        DriverName: "Driver", GameDriverId: null, TeamId: 1, RaceNumber: 1, IsAiControlled: false, TyreStints: null,
        LapHistory: lapHistory);

    [Fact]
    public void OnlyHistory_HasOnlyThatProperty()
    {
        var details = SessionDetailsCapture.Build(Parse("[1]"), null, out _);

        using var document = JsonDocument.Parse(details!);
        Assert.Equal(["lapHistory"], document.RootElement.EnumerateObject().Select(p => p.Name));
    }

    [Fact]
    public void UnstorableString_IsDiscardedWithReason()
    {
        Assert.Null(SessionDetailsCapture.Build(Parse("[\"a\\u0000\"]"), null, out var reason));
        Assert.NotNull(reason);
    }
}
