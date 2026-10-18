using SimCenter.Application.Laps.Ingest;

namespace SimCenter.Application.Tests.Laps;

/// <summary>트레이스 추가 채널 맵 검증(D-49, 15 §8): 이름 ^[A-Za-z0-9]{1,40}$, 채널 ≤ 150, 길이 = 표본 수, 유한 숫자.</summary>
public class LapTraceExtraValidatorTests
{
    private const int Samples = 4;

    private static double[] Series(double value = 1.25) => Enumerable.Repeat(value, Samples).ToArray();

    [Fact]
    public void ValidChannels_Pass()
    {
        var extra = new Dictionary<string, double[]?>
        {
            ["clutch"] = Series(),
            ["brakeTempFL"] = Series(512.37),
            ["worldPositionX"] = Series(-1234.56),
            [new string('a', 40)] = Series(),
        };

        Assert.Empty(LapTraceExtraValidator.Validate(extra, Samples));
    }

    [Fact]
    public void EmptyMap_Passes()
    {
        Assert.Empty(LapTraceExtraValidator.Validate(new Dictionary<string, double[]?>(), Samples));
    }

    [Theory]
    [InlineData("")]
    [InlineData("brake-temp")]
    [InlineData("tyre temp")]
    [InlineData("온도")]
    [InlineData("a_b")]
    public void BadChannelName_IsReported(string name)
    {
        var errors = LapTraceExtraValidator.Validate(new Dictionary<string, double[]?> { [name] = Series() }, Samples);

        Assert.Contains("채널 이름", Assert.Single(errors));
    }

    [Fact]
    public void TooLongChannelName_IsReported()
    {
        var errors = LapTraceExtraValidator.Validate(
            new Dictionary<string, double[]?> { [new string('a', 41)] = Series() }, Samples);

        Assert.Single(errors);
    }

    [Fact]
    public void TooManyChannels_IsReported()
    {
        var extra = Enumerable.Range(0, 151).ToDictionary(i => $"ch{i}", _ => (double[]?)Series());

        Assert.Contains("채널 수", Assert.Single(LapTraceExtraValidator.Validate(extra, Samples)));
        Assert.Empty(LapTraceExtraValidator.Validate(extra.Take(150).ToDictionary(), Samples));
    }

    [Fact]
    public void LengthMismatch_IsReported()
    {
        var errors = LapTraceExtraValidator.Validate(new Dictionary<string, double[]?> { ["drs"] = [1, 0] }, Samples);

        Assert.Contains("길이", Assert.Single(errors));
    }

    [Fact]
    public void NullArray_IsReported()
    {
        Assert.Single(LapTraceExtraValidator.Validate(new Dictionary<string, double[]?> { ["drs"] = null }, Samples));
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    public void NonFiniteValue_IsReported(double value)
    {
        var values = Series();
        values[2] = value;

        Assert.Contains("drs[2]", Assert.Single(LapTraceExtraValidator.Validate(new Dictionary<string, double[]?> { ["drs"] = values }, Samples)));
    }
}
