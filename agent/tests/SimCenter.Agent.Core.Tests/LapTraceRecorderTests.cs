using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

/// <summary>1랩 거리 기준 트레이스(D-45, docs/15 §3.3): 칸 덮어쓰기·음수 거리·빈 칸 채우기·50% 미만 생략·랩 경계 비움.</summary>
public class LapTraceRecorderTests
{
    private const int Resolution = LapTraceRecorder.DefaultResolutionM;
    private readonly LapTraceRecorder _sut = new();

    private static CarTelemetryFrame Telemetry(
        int speed = 200, float throttle = 1f, float brake = 0f, float steer = 0f, int gear = 7, int rpm = 11_000)
        => new("s", speed, throttle, brake, steer, gear, rpm);

    private void SampleAt(float distanceM, int timeMs, int speed = 200)
    {
        _sut.UpdatePosition(distanceM, timeMs);
        _sut.Record(Telemetry(speed));
    }

    [Fact]
    public void Flush_BucketsByFiveMetres_InDistanceOrder()
    {
        SampleAt(0.0f, 0, speed: 100);
        SampleAt(5.2f, 90, speed: 110);
        SampleAt(9.9f, 160, speed: 120);   // 같은 칸(1) — 나중 값이 이긴다

        var trace = Assert.IsType<LapTrace>(_sut.Flush());

        Assert.Equal(Resolution, trace.ResolutionM);
        Assert.Equal(new[] { 0, 160 }, trace.TimeMs);
        Assert.Equal(new[] { 100, 120 }, trace.SpeedKph);
    }

    [Fact]
    public void Record_FlashbackToEarlierDistance_OverwritesBucket()
    {
        SampleAt(0f, 0, speed: 100);
        SampleAt(5f, 100, speed: 110);
        SampleAt(10f, 200, speed: 120);
        SampleAt(6f, 120, speed: 90);    // 플래시백으로 칸 1에 되돌아와 다시 달림

        var trace = Assert.IsType<LapTrace>(_sut.Flush());

        Assert.Equal(new[] { 100, 90, 120 }, trace.SpeedKph);
        Assert.Equal(new[] { 0, 120, 200 }, trace.TimeMs);
    }

    [Fact]
    public void Record_NegativeDistance_IsIgnored()
    {
        SampleAt(-12f, 0, speed: 50);    // 출발선 전
        SampleAt(0f, 100, speed: 100);
        SampleAt(5f, 200, speed: 110);

        var trace = Assert.IsType<LapTrace>(_sut.Flush());

        Assert.Equal(new[] { 100, 110 }, trace.SpeedKph);
    }

    [Fact]
    public void Record_WithoutPosition_IsIgnored()
    {
        _sut.Record(Telemetry(speed: 99));

        Assert.Null(_sut.Flush());
    }

    [Fact]
    public void Record_AfterClearPosition_IsIgnored()
    {
        SampleAt(0f, 0, speed: 100);
        SampleAt(5f, 100, speed: 110);
        _sut.ClearPosition();

        _sut.Record(Telemetry(speed: 255));

        var trace = Assert.IsType<LapTrace>(_sut.Flush());
        Assert.Equal(new[] { 100, 110 }, trace.SpeedKph);
    }

    [Fact]
    public void Flush_FillsGapsWithPreviousValue_AndLeadingGapWithFirstValue()
    {
        SampleAt(5f, 100, speed: 110);   // 칸 1
        SampleAt(10f, 200, speed: 120);  // 칸 2
        SampleAt(20f, 400, speed: 140);  // 칸 4 — 칸 0·3은 비었다(3/5 = 60%)

        var trace = Assert.IsType<LapTrace>(_sut.Flush());

        Assert.Equal(new[] { 110, 110, 120, 120, 140 }, trace.SpeedKph);
        Assert.Equal(new[] { 100, 100, 200, 200, 400 }, trace.TimeMs);
    }

    [Fact]
    public void Flush_LessThanHalfFilled_ReturnsNull()
    {
        SampleAt(0f, 0);
        SampleAt(45f, 900);   // 칸 9 — 2/10 = 20%

        Assert.Null(_sut.Flush());
    }

    [Fact]
    public void Flush_ExactlyHalfFilled_ReturnsTrace()
    {
        SampleAt(0f, 0);
        SampleAt(15f, 300);   // 칸 3 — 2/4 = 50%

        var trace = Assert.IsType<LapTrace>(_sut.Flush());

        Assert.Equal(4, trace.TimeMs.Count);
    }

    [Fact]
    public void Flush_SingleSample_ReturnsNull()
    {
        SampleAt(0f, 0);

        Assert.Null(_sut.Flush());
    }

    [Fact]
    public void Flush_ClearsBufferAndPosition()
    {
        SampleAt(0f, 0, speed: 100);
        SampleAt(5f, 100, speed: 110);
        Assert.NotNull(_sut.Flush());

        _sut.Record(Telemetry(speed: 255));   // 위치를 비웠으므로 버려진다
        Assert.Null(_sut.Flush());

        SampleAt(0f, 0, speed: 150);
        SampleAt(5f, 100, speed: 160);
        var next = Assert.IsType<LapTrace>(_sut.Flush());
        Assert.Equal(new[] { 150, 160 }, next.SpeedKph);
    }

    [Fact]
    public void Record_ConvertsChannelsToIntegers()
    {
        _sut.UpdatePosition(0f, 1_234);
        _sut.Record(Telemetry(speed: 287, throttle: 0.456f, brake: 1f, steer: -0.5f, gear: -1, rpm: 11_250));
        _sut.UpdatePosition(5f, 1_300);
        _sut.Record(Telemetry(speed: 0, throttle: 0f, brake: 0.004f, steer: 0.996f, gear: 0, rpm: 4_000));

        var trace = Assert.IsType<LapTrace>(_sut.Flush());

        Assert.Equal(new[] { 1_234, 1_300 }, trace.TimeMs);
        Assert.Equal(new[] { 287, 0 }, trace.SpeedKph);
        Assert.Equal(new[] { 46, 0 }, trace.Throttle);
        Assert.Equal(new[] { 100, 0 }, trace.Brake);
        Assert.Equal(new[] { -50, 100 }, trace.Steer);
        Assert.Equal(new[] { -1, 0 }, trace.Gear);
        Assert.Equal(new[] { 11_250, 4_000 }, trace.Rpm);
    }

    [Fact]
    public void Record_OutOfContractValues_AreClamped()
    {
        // 백엔드는 범위를 벗어난 값이 하나라도 있으면 트레이스 전체를 버린다(docs/15 §5) — 깨진 표본 하나로 트레이스를 잃지 않게 다듬는다.
        _sut.UpdatePosition(0f, -5);
        _sut.Record(Telemetry(speed: 650, throttle: 1.3f, brake: -0.2f, steer: -1.7f, gear: 11, rpm: 30_000));
        _sut.UpdatePosition(5f, 4_000_000);
        _sut.Record(Telemetry(speed: 10, throttle: float.NaN, brake: float.NaN, steer: float.NaN, gear: -3, rpm: -1));

        var trace = Assert.IsType<LapTrace>(_sut.Flush());

        Assert.Equal(new[] { 0, 3_600_000 }, trace.TimeMs);
        Assert.Equal(new[] { 500, 10 }, trace.SpeedKph);
        Assert.Equal(new[] { 100, 0 }, trace.Throttle);
        Assert.Equal(new[] { 0, 0 }, trace.Brake);
        Assert.Equal(new[] { -100, 0 }, trace.Steer);
        Assert.Equal(new[] { 8, -1 }, trace.Gear);
        Assert.Equal(new[] { 25_000, 0 }, trace.Rpm);
    }

    [Theory]
    [InlineData(float.NaN)]
    [InlineData(float.PositiveInfinity)]
    [InlineData((float)(LapTraceRecorder.MaxSamples * Resolution))]   // 계약 상한(5,000칸) 밖
    public void Record_UnusableDistance_IsIgnored(float distanceM)
    {
        SampleAt(0f, 0, speed: 100);
        SampleAt(5f, 100, speed: 110);
        SampleAt(distanceM, 200, speed: 255);

        var trace = Assert.IsType<LapTrace>(_sut.Flush());

        Assert.Equal(new[] { 100, 110 }, trace.SpeedKph);
    }

    [Fact]
    public void Clear_DropsSamples()
    {
        SampleAt(0f, 0);
        SampleAt(5f, 100);

        _sut.Clear();

        Assert.Null(_sut.Flush());
    }
}
