using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

/// <summary>
/// 트레이스 <c>extra</c> 채널(D-49, docs/15 §8): 기존 7채널과 같은 칸·같은 덮어쓰기, 빈 칸은 앞 값(맨 앞은 첫 값),
/// 유한하지 않은 값은 앞 값 유지, 소수 둘째 자리 반올림, 이름·개수 검증, 랩을 넘는 최신 값 유지와 세션 변경 시 초기화.
/// </summary>
public class LapTraceExtraChannelsTests
{
    private readonly LapTraceRecorder _sut = new();

    private static ExtraChannelsFrame Extra(params (string Name, double Value)[] channels) =>
        new("s", channels.ToDictionary(channel => channel.Name, channel => channel.Value));

    private void SampleAt(float distanceM, params (string Name, double Value)[] channels)
    {
        if (channels.Length > 0)
        {
            _sut.OnExtraChannels(Extra(channels));
        }

        _sut.UpdatePosition(distanceM, (int)distanceM * 10);
        _sut.Record(new CarTelemetryFrame("s", 200, 1f, 0f, 0f, 7, 11_000));
    }

    private LapTrace FlushTrace() => Assert.IsType<LapTrace>(_sut.Flush());

    [Fact]
    public void Flush_ExtraChannels_HaveSameLengthAndBucketsAsBaseChannels()
    {
        SampleAt(0f, ("clutch", 10), ("tyreSurfaceTempFL", 90));
        SampleAt(5f, ("clutch", 20));
        SampleAt(9f, ("clutch", 30));   // 같은 칸(1) — 나중 값이 이긴다

        var trace = FlushTrace();

        var extra = Assert.IsAssignableFrom<IReadOnlyDictionary<string, IReadOnlyList<double>>>(trace.Extra);
        Assert.Equal(new[] { 10d, 30d }, extra["clutch"]);
        Assert.Equal(new[] { 90d, 90d }, extra["tyreSurfaceTempFL"]);   // 이후 값이 안 와도 최신 값이 칸마다 찍힌다
        Assert.All(extra.Values, channel => Assert.Equal(trace.TimeMs.Count, channel.Count));
    }

    [Fact]
    public void Flush_ChannelFirstSeenMidLap_LeadingBucketsUseFirstValue()
    {
        SampleAt(0f);
        SampleAt(5f);
        SampleAt(10f, ("fuelInTank", 12.5));

        var extra = FlushTrace().Extra!;

        Assert.Equal(new[] { 12.5, 12.5, 12.5 }, extra["fuelInTank"]);
    }

    [Fact]
    public void Flush_EmptyBuckets_AreFilledWithPreviousValue()
    {
        SampleAt(0f, ("drs", 0));
        SampleAt(5f, ("drs", 1));
        SampleAt(15f, ("drs", 0));   // 칸 2는 비었다(3/4 = 75%)

        var extra = FlushTrace().Extra!;

        Assert.Equal(new[] { 0d, 1d, 1d, 0d }, extra["drs"]);
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void Update_NonFiniteValue_KeepsPreviousValue(double broken)
    {
        SampleAt(0f, ("engineTemp", 105));
        SampleAt(5f, ("engineTemp", broken));

        var extra = FlushTrace().Extra!;

        Assert.Equal(new[] { 105d, 105d }, extra["engineTemp"]);
    }

    [Fact]
    public void Update_ChannelNeverFinite_IsOmitted()
    {
        SampleAt(0f, ("gForceLateral", double.NaN), ("clutch", 0));
        SampleAt(5f);

        var extra = FlushTrace().Extra!;

        Assert.False(extra.ContainsKey("gForceLateral"));
        Assert.True(extra.ContainsKey("clutch"));
    }

    [Fact]
    public void Update_RoundsToTwoDecimals()
    {
        SampleAt(0f, ("tyrePressureFL", 23.456789), ("wheelSlipRatioRL", -0.005));
        SampleAt(5f);

        var extra = FlushTrace().Extra!;

        Assert.Equal(23.46, extra["tyrePressureFL"][0]);
        Assert.Equal(-0.01, extra["wheelSlipRatioRL"][0]);   // 0에서 먼 쪽
    }

    [Theory]
    [InlineData("")]
    [InlineData("tyre_temp")]
    [InlineData("tyre temp")]
    [InlineData("타이어")]
    [InlineData("a12345678901234567890123456789012345678901")]   // 41자
    public void Update_InvalidChannelName_IsIgnored(string name)
    {
        SampleAt(0f, (name, 1), ("ok", 2));
        SampleAt(5f);

        var extra = FlushTrace().Extra!;

        Assert.Equal(new[] { "ok" }, extra.Keys);
    }

    [Fact]
    public void Update_MoreThanMaxChannels_KeepsFirstMax()
    {
        var many = Enumerable.Range(0, TraceExtraChannels.MaxChannels + 5).Select(i => ($"c{i}", (double)i)).ToArray();
        SampleAt(0f, many);
        SampleAt(5f);

        var extra = FlushTrace().Extra!;

        Assert.Equal(TraceExtraChannels.MaxChannels, extra.Count);
        Assert.False(extra.ContainsKey($"c{TraceExtraChannels.MaxChannels}"));
    }

    [Fact]
    public void Flush_WithoutExtraFrames_ExtraIsNull()
    {
        SampleAt(0f);
        SampleAt(5f);

        Assert.Null(FlushTrace().Extra);
    }

    [Fact]
    public void Flush_KeepsLatestValuesForNextLap()
    {
        SampleAt(0f, ("ersDeployMode", 2));
        SampleAt(5f);
        _ = FlushTrace();

        SampleAt(0f);
        SampleAt(5f);

        Assert.Equal(new[] { 2d, 2d }, FlushTrace().Extra!["ersDeployMode"]);
    }

    [Fact]
    public void Clear_ForgetsChannels()
    {
        SampleAt(0f, ("ersDeployMode", 2));
        _sut.Clear();

        SampleAt(0f);
        SampleAt(5f);

        Assert.Null(FlushTrace().Extra);
    }

    [Fact]
    public void Downsample_KeepsEveryOtherExtraSample()
    {
        var values = new[] { 1, 2, 3, 4, 5 };
        var trace = new LapTrace(5, values, values, values, values, values, values, values,
            new Dictionary<string, IReadOnlyList<double>> { ["clutch"] = new[] { 0.5, 1.5, 2.5, 3.5, 4.5 } });

        var halved = trace.Downsample();

        Assert.Equal(new[] { 0.5, 2.5, 4.5 }, halved.Extra!["clutch"]);
        Assert.Equal(new[] { 0.5, 1.5, 2.5, 3.5, 4.5 }, trace.Extra!["clutch"]);   // 원본은 그대로
    }
}
