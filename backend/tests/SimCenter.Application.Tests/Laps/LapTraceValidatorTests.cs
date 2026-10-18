using SimCenter.Application.Laps.Ingest;

namespace SimCenter.Application.Tests.Laps;

/// <summary>
/// 트레이스 검증 규칙(15 §5): resolutionM 1~50, 7채널 모두·같은 길이·2~5,000,
/// 값 범위(시간 0~3.6M · 속도 0~500 · 페달 0~100 · 스티어 ±100 · 기어 −1~9 · RPM 0~25,000).
/// </summary>
public class LapTraceValidatorTests
{
    [Fact]
    public void ValidTrace_Passes()
    {
        Assert.Empty(LapTraceValidator.Validate(LapDetailSamples.ValidTrace()));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(50)]
    public void ResolutionBoundaries_Pass(int resolutionM)
    {
        Assert.Empty(LapTraceValidator.Validate(LapDetailSamples.ValidTrace(resolutionM: resolutionM)));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(51)]
    public void ResolutionOutOfRange_IsReported(int resolutionM)
    {
        var errors = LapTraceValidator.Validate(LapDetailSamples.ValidTrace(resolutionM: resolutionM));

        Assert.StartsWith("resolutionM", Assert.Single(errors));
    }

    [Fact]
    public void MissingResolution_IsReported()
    {
        var trace = LapDetailSamples.ValidTrace() with { ResolutionM = null };

        Assert.StartsWith("resolutionM", Assert.Single(LapTraceValidator.Validate(trace)));
    }

    [Fact]
    public void MissingChannel_IsReported()
    {
        var trace = LapDetailSamples.ValidTrace() with { Rpm = null, Gear = null };

        var error = Assert.Single(LapTraceValidator.Validate(trace));
        Assert.Contains("gear", error);
        Assert.Contains("rpm", error);
    }

    [Fact]
    public void DifferentLengths_AreReported()
    {
        var trace = LapDetailSamples.ValidTrace(samples: 10) with { Brake = new int[9] };

        Assert.Contains("길이", Assert.Single(LapTraceValidator.Validate(trace)));
    }

    [Theory]
    [InlineData(1, false)]
    [InlineData(2, true)]
    [InlineData(5_000, true)]
    [InlineData(5_001, false)]
    public void SampleCountBounds(int samples, bool valid)
    {
        var errors = LapTraceValidator.Validate(LapDetailSamples.ValidTrace(samples));

        Assert.Equal(valid, errors.Count == 0);
    }

    public static TheoryData<string, Func<LapTracePayload, LapTracePayload>> OutOfRangeChannels() => new()
    {
        { "timeMs", t => t with { TimeMs = Replace(t.TimeMs!, 3_600_001) } },
        { "timeMs", t => t with { TimeMs = Replace(t.TimeMs!, -1) } },
        { "speedKph", t => t with { SpeedKph = Replace(t.SpeedKph!, 501) } },
        { "throttle", t => t with { Throttle = Replace(t.Throttle!, 101) } },
        { "brake", t => t with { Brake = Replace(t.Brake!, -1) } },
        { "steer", t => t with { Steer = Replace(t.Steer!, -101) } },
        { "gear", t => t with { Gear = Replace(t.Gear!, -2) } },
        { "gear", t => t with { Gear = Replace(t.Gear!, 10) } },
        { "rpm", t => t with { Rpm = Replace(t.Rpm!, 25_001) } },
    };

    [Theory]
    [MemberData(nameof(OutOfRangeChannels))]
    public void OutOfRangeValue_IsReported(string channel, Func<LapTracePayload, LapTracePayload> mutate)
    {
        var errors = LapTraceValidator.Validate(mutate(LapDetailSamples.ValidTrace()));

        Assert.StartsWith($"{channel}[3]", Assert.Single(errors));
    }

    [Fact]
    public void ChannelBoundaries_Pass()
    {
        var trace = LapDetailSamples.ValidTrace(samples: 2) with
        {
            TimeMs = [0, 3_600_000],
            SpeedKph = [0, 500],
            Throttle = [0, 100],
            Brake = [100, 0],
            Steer = [-100, 100],
            Gear = [-1, 9],
            Rpm = [0, 25_000],
        };

        Assert.Empty(LapTraceValidator.Validate(trace));
    }

    /// <summary>4번째 표본(index 3)만 바꾼 복사본.</summary>
    private static int[] Replace(int[] values, int value)
    {
        var copy = values.ToArray();
        copy[3] = value;
        return copy;
    }
}
