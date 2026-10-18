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
