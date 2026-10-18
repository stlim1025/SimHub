using SimCenter.Agent.Core.Telemetry.Events;

namespace SimCenter.Agent.Core.Tests;

/// <summary>크기 한도용 해상도 낮추기(D-45): 표본을 하나 걸러 버리고 해상도를 두 배로.</summary>
public class LapTraceTests
{
    private static LapTrace Trace(int resolutionM, params int[] values) =>
        new(resolutionM, values, values, values, values, values, values, values);

    [Fact]
    public void Downsample_KeepsEveryOtherSample_AndDoublesResolution()
    {
        var trace = Trace(5, 10, 11, 12, 13, 14);

        var halved = trace.Downsample();

        Assert.Equal(10, halved.ResolutionM);
        Assert.Equal(new[] { 10, 12, 14 }, halved.TimeMs);
        Assert.Equal(new[] { 10, 12, 14 }, halved.SpeedKph);
        Assert.Equal(new[] { 10, 12, 14 }, halved.Throttle);
        Assert.Equal(new[] { 10, 12, 14 }, halved.Brake);
        Assert.Equal(new[] { 10, 12, 14 }, halved.Steer);
        Assert.Equal(new[] { 10, 12, 14 }, halved.Gear);
        Assert.Equal(new[] { 10, 12, 14 }, halved.Rpm);
    }

    [Fact]
    public void Downsample_DoesNotChangeOriginal()
    {
        var trace = Trace(5, 1, 2, 3, 4);

        _ = trace.Downsample();

        Assert.Equal(5, trace.ResolutionM);
        Assert.Equal(new[] { 1, 2, 3, 4 }, trace.TimeMs);
    }
}
