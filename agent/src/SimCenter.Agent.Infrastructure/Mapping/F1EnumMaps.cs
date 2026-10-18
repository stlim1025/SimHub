using SimCenter.Agent.Core.Telemetry;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// F1Game.UDP enum → Agent.Core 게임중립 enum 변환(D-20 경계, 12 §5.2).
/// 모르는 값은 항상 0번 대체값(<c>Other</c>/<c>Unknown</c>)이나 null로 바꾼다 — 게임 업데이트로 새 값이 생겨도 예외 없이 보낸다(12 §0 실패 원칙).
/// </summary>
internal static class F1EnumMaps
{
    /// <summary>예전 연식의 Grand Prix 원시 값. 라이브러리 enum에는 이름이 없고(F1 25는 <c>GrandPrix23</c>=4) 12 §5.2가 Grand Prix로 본다.</summary>
    private const int LegacyGrandPrixValue = 3;

    /// <summary>
    /// F1 25 v1.26(2026 시즌팩) Driver Career의 원시 값. 라이브러리 enum(25.1.1·26.0.0)에 없다 — 실제 게임 랩 스냅샷으로 확인(docs/15 §11.1, D-52).
    /// </summary>
    private const int DriverCareer2026Value = 78;

    public static GameMode ToGameMode(F1Enums.GameMode mode)
    {
        switch ((int)mode)
        {
            case LegacyGrandPrixValue:
                return GameMode.GrandPrix;
            case DriverCareer2026Value:
                return GameMode.DriverCareer;
        }

        return mode switch
        {
            F1Enums.GameMode.GrandPrix23 => GameMode.GrandPrix,
            F1Enums.GameMode.TimeTrial => GameMode.TimeTrial,
            F1Enums.GameMode.OnlineCustom or F1Enums.GameMode.OnlineWeeklyEvent => GameMode.Online,
            F1Enums.GameMode.StoryMode or F1Enums.GameMode.StoryModeApxGp => GameMode.Story,
            F1Enums.GameMode.MyTeamCareer25 => GameMode.MyTeamCareer,
            F1Enums.GameMode.DriverCareer25 => GameMode.DriverCareer,
            F1Enums.GameMode.Career25Online => GameMode.OnlineCareer,
            F1Enums.GameMode.ChallengeCareer25 => GameMode.ChallengeCareer,
            _ => GameMode.Other,   // SplitScreen · Benchmark · 모르는 값
        };
    }

    public static SessionKind ToSessionKind(F1Enums.SessionType type) => type switch
    {
        F1Enums.SessionType.Practice1 => SessionKind.Practice1,
        F1Enums.SessionType.Practice2 => SessionKind.Practice2,
        F1Enums.SessionType.Practice3 => SessionKind.Practice3,
        F1Enums.SessionType.ShortPractice => SessionKind.ShortPractice,
        F1Enums.SessionType.Qualifying1 => SessionKind.Qualifying1,
        F1Enums.SessionType.Qualifying2 => SessionKind.Qualifying2,
        F1Enums.SessionType.Qualifying3 => SessionKind.Qualifying3,
        F1Enums.SessionType.ShortQualifying => SessionKind.ShortQualifying,
        F1Enums.SessionType.OneShotQualifying => SessionKind.OneShotQualifying,
        F1Enums.SessionType.SprintShootout1 => SessionKind.SprintShootout1,
        F1Enums.SessionType.SprintShootout2 => SessionKind.SprintShootout2,
        F1Enums.SessionType.SprintShootout3 => SessionKind.SprintShootout3,
        F1Enums.SessionType.ShortSprintShootout => SessionKind.ShortSprintShootout,
        F1Enums.SessionType.OneShotSprintShootout => SessionKind.OneShotSprintShootout,
        F1Enums.SessionType.Race => SessionKind.Race,
        F1Enums.SessionType.Race2 => SessionKind.Race2,
        F1Enums.SessionType.Race3 => SessionKind.Race3,
        F1Enums.SessionType.TimeTrial => SessionKind.TimeTrial,
        _ => SessionKind.Unknown,
    };

    public static ResultStatus ToResultStatus(F1Enums.ResultStatus status) => status switch
    {
        F1Enums.ResultStatus.Active => ResultStatus.Active,
        F1Enums.ResultStatus.Finished => ResultStatus.Finished,
        F1Enums.ResultStatus.DidNotFinish => ResultStatus.DidNotFinish,
        F1Enums.ResultStatus.Disqualified => ResultStatus.Disqualified,
        F1Enums.ResultStatus.NotClassified => ResultStatus.NotClassified,
        F1Enums.ResultStatus.Retired => ResultStatus.Retired,
        _ => ResultStatus.Unknown,   // Invalid · Inactive · 모르는 값
    };

    public static TyreCompound ToVisualCompound(F1Enums.VisualCompound compound) => compound switch
    {
        F1Enums.VisualCompound.F1Soft => TyreCompound.Soft,
        F1Enums.VisualCompound.F1Medium => TyreCompound.Medium,
        F1Enums.VisualCompound.F1Hard => TyreCompound.Hard,
        F1Enums.VisualCompound.F1Inter => TyreCompound.Intermediate,
        F1Enums.VisualCompound.F1Wet => TyreCompound.Wet,
        _ => TyreCompound.Unknown,   // 클래식 · F2 · 모르는 값
    };

    /// <summary>세션 날씨(docs/15 §3.1). 게임 0~5와 같은 이름. 모르는 값은 null.</summary>
    public static Weather? ToWeather(F1Enums.Weather weather) => weather switch
    {
        F1Enums.Weather.Clear => Weather.Clear,
        F1Enums.Weather.LightCloud => Weather.LightCloud,
        F1Enums.Weather.Overcast => Weather.Overcast,
        F1Enums.Weather.LightRain => Weather.LightRain,
        F1Enums.Weather.HeavyRain => Weather.HeavyRain,
        F1Enums.Weather.Storm => Weather.Storm,
        _ => null,
    };

    /// <summary>게임 고유 라벨(F1 C0~C6, Inter, Wet). 그 밖(클래식·F2·모르는 값)은 null.</summary>
    public static string? ToActualCompoundLabel(F1Enums.ActualCompound compound) => compound switch
    {
        F1Enums.ActualCompound.F1C0 => "C0",
        F1Enums.ActualCompound.F1C1 => "C1",
        F1Enums.ActualCompound.F1C2 => "C2",
        F1Enums.ActualCompound.F1C3 => "C3",
        F1Enums.ActualCompound.F1C4 => "C4",
        F1Enums.ActualCompound.F1C5 => "C5",
        F1Enums.ActualCompound.F1C6 => "C6",
        F1Enums.ActualCompound.F1Inter => "Inter",
        F1Enums.ActualCompound.F1Wet => "Wet",
        _ => null,
    };
}
