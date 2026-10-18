using System.Text.Json;
using SimCenter.Application.Laps;

namespace SimCenter.Application.Tests.Laps;

/// <summary><c>car.details</c> → 어시스트 원시 값(docs/15 §10, D-51): TC·ABS = status, 나머지 = session.</summary>
public class LapAssistReaderTests
{
    private static JsonElement Json(string raw) => JsonDocument.Parse(raw).RootElement.Clone();

    [Fact]
    public void Read_FromStatusAndSession()
    {
        var details = Json("""
            { "status": { "tractionControl": 1, "antiLockBrakes": 1, "fuelMix": 2 },
              "session": { "steeringAssist": 0, "brakingAssist": 2, "gearboxAssist": 1, "dynamicRacingLine": 1, "dynamicRacingLineType": 1 } }
            """);

        Assert.Equal(new LapAssistValues(1, 1, 0, 2, 1, 1), LapAssistReader.Read(details));
    }

    [Fact]
    public void Read_MissingSectionsOrKeys_AreUnknown()
    {
        var onlySession = LapAssistReader.Read(Json("""{ "session": { "gearboxAssist": 3 } }"""));

        Assert.Equal(LapAssistValues.Unknown with { GearboxAssist = 3 }, onlySession);
        Assert.Equal(LapAssistValues.Unknown, LapAssistReader.Read(Json("{}")));
        Assert.Equal(LapAssistValues.Unknown, LapAssistReader.Read(null));
        Assert.False(LapAssistValues.Unknown.HasAny);
        Assert.True(onlySession.HasAny);
    }

    [Theory]
    [InlineData("\"1\"")]
    [InlineData("1.5")]
    [InlineData("-1")]
    [InlineData("256")]
    [InlineData("true")]
    [InlineData("null")]
    public void Read_NonIntegerOrOutOfRange_IsUnknown(string value)
    {
        var details = Json($$"""{ "status": { "tractionControl": {{value}}, "antiLockBrakes": 1 } }""");

        var read = LapAssistReader.Read(details);

        Assert.Null(read.TractionControl);
        Assert.Equal(1, read.AntiLockBrakes);
    }

    [Fact]
    public void Read_SectionNotObject_IsUnknown()
    {
        Assert.Equal(LapAssistValues.Unknown, LapAssistReader.Read(Json("""{ "status": [1, 2], "session": 5 }""")));
        Assert.Equal(LapAssistValues.Unknown, LapAssistReader.Read(Json("[1]")));
    }

    [Theory]
    [InlineData(0, "Off")]
    [InlineData(1, "Medium")]
    [InlineData(2, "Full")]
    [InlineData(3, null)]
    public void Names_TractionControl(int raw, string? expected)
        => Assert.Equal(expected, LapAssistNames.ToDto(LapAssistValues.Unknown with { TractionControl = raw })?.TractionControl);

    [Theory]
    [InlineData(0, null)]
    [InlineData(1, "Manual")]
    [InlineData(2, "ManualSuggested")]
    [InlineData(3, "Automatic")]
    public void Names_Gearbox_StartsAtOne(int raw, string? expected)
        => Assert.Equal(expected, LapAssistNames.ToDto(LapAssistValues.Unknown with { GearboxAssist = raw })?.Gearbox);

    [Fact]
    public void Names_AllUnknown_IsNull()
    {
        Assert.Null(LapAssistNames.ToDto(LapAssistValues.Unknown));
        Assert.Null(LapAssistNames.ToDto(LapAssistValues.Unknown with { GearboxAssist = 0, BrakingAssist = 7 }));
    }

    [Fact]
    public void Names_Braking_AndRacingLine()
    {
        var dto = LapAssistNames.ToDto(new LapAssistValues(0, 0, 1, 3, 1, 2))!;

        Assert.Equal(("Off", "Off", "On", "High", "Full"), (dto.TractionControl, dto.AntiLockBrakes, dto.SteeringAssist, dto.BrakingAssist, dto.RacingLine));
    }
}
