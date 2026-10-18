using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Infrastructure.Mapping;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Tests;

public class F1EnumMapsTests
{
    // 예전 연식의 Grand Prix 원시 값(라이브러리 enum에는 이름이 없다) — 스펙 12 §5.2.
    private const byte LegacyGrandPrixRawValue = 3;

    // 라이브러리에 정의되지 않은 원시 값(게임 업데이트로 새 모드가 생긴 경우).
    private const byte UndefinedRawValue = 200;

    [Theory]
    [InlineData(F1Enums.GameMode.GrandPrix23, GameMode.GrandPrix)]
    [InlineData(F1Enums.GameMode.TimeTrial, GameMode.TimeTrial)]
    [InlineData(F1Enums.GameMode.OnlineCustom, GameMode.Online)]
    [InlineData(F1Enums.GameMode.OnlineWeeklyEvent, GameMode.Online)]
    [InlineData(F1Enums.GameMode.StoryMode, GameMode.Story)]
    [InlineData(F1Enums.GameMode.StoryModeApxGp, GameMode.Story)]
    [InlineData(F1Enums.GameMode.MyTeamCareer25, GameMode.MyTeamCareer)]
    [InlineData(F1Enums.GameMode.DriverCareer25, GameMode.DriverCareer)]
    [InlineData(F1Enums.GameMode.Career25Online, GameMode.OnlineCareer)]
    [InlineData(F1Enums.GameMode.ChallengeCareer25, GameMode.ChallengeCareer)]
    [InlineData(F1Enums.GameMode.SplitScreen, GameMode.Other)]
    [InlineData(F1Enums.GameMode.Benchmark, GameMode.Other)]
    public void ToGameMode_Maps(F1Enums.GameMode input, GameMode expected)
    {
        Assert.Equal(expected, F1EnumMaps.ToGameMode(input));
    }

    [Fact]
    public void ToGameMode_2026SeasonPackDriverCareer_IsDriverCareer()
    {
        // F1 25 v1.26(2026 시즌팩) Driver Career는 라이브러리 enum에 없는 78로 온다(실제 게임 스냅샷, docs/15 §11.1, D-52).
        Assert.Equal(GameMode.DriverCareer, F1EnumMaps.ToGameMode((F1Enums.GameMode)78));
    }

    [Fact]
    public void ToGameMode_UnknownValue_IsOther()
    {
        Assert.Equal(GameMode.Other, F1EnumMaps.ToGameMode((F1Enums.GameMode)UndefinedRawValue));
    }

    [Fact]
    public void ToGameMode_LegacyGrandPrixValue3_IsGrandPrix()
    {
        Assert.Equal(GameMode.GrandPrix, F1EnumMaps.ToGameMode((F1Enums.GameMode)LegacyGrandPrixRawValue));
    }

    [Fact]
    public void ToSessionKind_MapsAllNineteenByName()
    {
        var values = Enum.GetValues<F1Enums.SessionType>();

        Assert.Equal(19, values.Length);
        foreach (var value in values)
        {
            // 같은 이름의 SessionKind가 없으면 Enum.Parse가 던진다 — 라이브러리 enum이 바뀌면 여기서 드러난다.
            var expected = Enum.Parse<SessionKind>(value.ToString());
            Assert.Equal(expected, F1EnumMaps.ToSessionKind(value));
        }
    }

    [Fact]
    public void ToSessionKind_UndefinedValue_IsUnknown()
    {
        Assert.Equal(SessionKind.Unknown, F1EnumMaps.ToSessionKind((F1Enums.SessionType)UndefinedRawValue));
    }

    [Theory]
    [InlineData(F1Enums.ResultStatus.Invalid, ResultStatus.Unknown)]
    [InlineData(F1Enums.ResultStatus.Inactive, ResultStatus.Unknown)]
    [InlineData(F1Enums.ResultStatus.Active, ResultStatus.Active)]
    [InlineData(F1Enums.ResultStatus.Finished, ResultStatus.Finished)]
    [InlineData(F1Enums.ResultStatus.DidNotFinish, ResultStatus.DidNotFinish)]
    [InlineData(F1Enums.ResultStatus.Disqualified, ResultStatus.Disqualified)]
    [InlineData(F1Enums.ResultStatus.NotClassified, ResultStatus.NotClassified)]
    [InlineData(F1Enums.ResultStatus.Retired, ResultStatus.Retired)]
    public void ToResultStatus_Maps(F1Enums.ResultStatus input, ResultStatus expected)
    {
        Assert.Equal(expected, F1EnumMaps.ToResultStatus(input));
    }

    [Fact]
    public void ToResultStatus_UndefinedValue_IsUnknown()
    {
        Assert.Equal(ResultStatus.Unknown, F1EnumMaps.ToResultStatus((F1Enums.ResultStatus)UndefinedRawValue));
    }

    [Theory]
    [InlineData(F1Enums.VisualCompound.F1Soft, TyreCompound.Soft)]
    [InlineData(F1Enums.VisualCompound.F1Medium, TyreCompound.Medium)]
    [InlineData(F1Enums.VisualCompound.F1Hard, TyreCompound.Hard)]
    [InlineData(F1Enums.VisualCompound.F1Inter, TyreCompound.Intermediate)]
    [InlineData(F1Enums.VisualCompound.F1Wet, TyreCompound.Wet)]
    [InlineData(F1Enums.VisualCompound.F2Soft, TyreCompound.Unknown)]
    public void ToVisualCompound_Maps(F1Enums.VisualCompound input, TyreCompound expected)
    {
        Assert.Equal(expected, F1EnumMaps.ToVisualCompound(input));
    }

    [Theory]
    [InlineData(F1Enums.ActualCompound.F1C0, "C0")]
    [InlineData(F1Enums.ActualCompound.F1C1, "C1")]
    [InlineData(F1Enums.ActualCompound.F1C2, "C2")]
    [InlineData(F1Enums.ActualCompound.F1C3, "C3")]
    [InlineData(F1Enums.ActualCompound.F1C4, "C4")]
    [InlineData(F1Enums.ActualCompound.F1C5, "C5")]
    [InlineData(F1Enums.ActualCompound.F1C6, "C6")]
    [InlineData(F1Enums.ActualCompound.F1Inter, "Inter")]
    [InlineData(F1Enums.ActualCompound.F1Wet, "Wet")]
    [InlineData(F1Enums.ActualCompound.F2Hard, null)]
    public void ToActualCompoundLabel_Maps(F1Enums.ActualCompound input, string? expected)
    {
        Assert.Equal(expected, F1EnumMaps.ToActualCompoundLabel(input));
    }
}
