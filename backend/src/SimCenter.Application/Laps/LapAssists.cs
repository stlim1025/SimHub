using System.Text.Json;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Laps;

/// <summary>
/// 드라이버 어시스트 원시 값(게임 정수, docs/15 §10, D-51). 모르면 null.
/// 인입 때 <c>car.details</c>에서 뽑아 스냅샷 열에 두고, 상세 표시·비교 필터(같은 어시스트)가 같은 값을 쓴다.
/// </summary>
public sealed record LapAssistValues(
    int? TractionControl,
    int? AntiLockBrakes,
    int? SteeringAssist,
    int? BrakingAssist,
    int? GearboxAssist,
    int? DynamicRacingLine)
{
    public static readonly LapAssistValues Unknown = new(null, null, null, null, null, null);

    /// <summary>값이 하나라도 있는지.</summary>
    public bool HasAny
        => TractionControl.HasValue || AntiLockBrakes.HasValue || SteeringAssist.HasValue
            || BrakingAssist.HasValue || GearboxAssist.HasValue || DynamicRacingLine.HasValue;

    /// <summary>스냅샷 열 → 값. 스냅샷이 없으면 <see cref="Unknown"/>.</summary>
    public static LapAssistValues From(LapSnapshot? snapshot)
        => snapshot is null
            ? Unknown
            : new LapAssistValues(
                snapshot.TractionControl,
                snapshot.AntiLockBrakes,
                snapshot.SteeringAssist,
                snapshot.BrakingAssist,
                snapshot.GearboxAssist,
                snapshot.DynamicRacingLine);

    /// <summary>값 → 스냅샷 열(인입).</summary>
    public void ApplyTo(LapSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        snapshot.TractionControl = TractionControl;
        snapshot.AntiLockBrakes = AntiLockBrakes;
        snapshot.SteeringAssist = SteeringAssist;
        snapshot.BrakingAssist = BrakingAssist;
        snapshot.GearboxAssist = GearboxAssist;
        snapshot.DynamicRacingLine = DynamicRacingLine;
    }
}

/// <summary>
/// <c>car.details</c>(D-49) → 어시스트 원시 값(D-51). TC·ABS = <c>status</c>, 나머지 = <c>session</c>(F1 25 UDP 스펙 §7).
/// 정수가 아니거나 0~255 밖이면 그 값만 모름(null)으로 둔다 — details는 구조 검사 없이 저장되는 덤이다.
/// </summary>
public static class LapAssistReader
{
    private const string StatusSection = "status";
    private const string SessionSection = "session";
    private const int MaxRawValue = byte.MaxValue;

    public static LapAssistValues Read(JsonElement? details)
    {
        if (details is not { ValueKind: JsonValueKind.Object } root)
        {
            return LapAssistValues.Unknown;
        }

        return new LapAssistValues(
            ReadInt(root, StatusSection, "tractionControl"),
            ReadInt(root, StatusSection, "antiLockBrakes"),
            ReadInt(root, SessionSection, "steeringAssist"),
            ReadInt(root, SessionSection, "brakingAssist"),
            ReadInt(root, SessionSection, "gearboxAssist"),
            ReadInt(root, SessionSection, "dynamicRacingLine"));
    }

    private static int? ReadInt(JsonElement root, string section, string key)
        => root.TryGetProperty(section, out var group)
            && group.ValueKind == JsonValueKind.Object
            && group.TryGetProperty(key, out var value)
            && value.ValueKind == JsonValueKind.Number
            && value.TryGetInt32(out var number)
            && number is >= 0 and <= MaxRawValue
                ? number
                : null;
}

/// <summary>
/// 어시스트 원시 값 → 표시 이름(D-51, <c>assists</c> 응답). 모르는 값·없는 값은 null.
/// </summary>
public static class LapAssistNames
{
    public const string Off = "Off";
    public const string On = "On";

    private static readonly string[] TractionControl = [Off, "Medium", "Full"];
    private static readonly string[] OnOff = [Off, On];
    private static readonly string[] BrakingAssist = [Off, "Low", "Medium", "High"];
    private static readonly string[] RacingLine = [Off, "CornersOnly", "Full"];

    /// <summary>게임 기어 값은 1부터다(1 Manual · 2 ManualSuggested · 3 Automatic). 0은 모름.</summary>
    private static readonly string?[] Gearbox = [null, "Manual", "ManualSuggested", "Automatic"];

    /// <summary>값이 하나도 없으면 null — 화면은 Driver Assists 영역을 숨긴다.</summary>
    public static LapAssistsDto? ToDto(LapAssistValues values)
    {
        ArgumentNullException.ThrowIfNull(values);
        var dto = new LapAssistsDto(
            Name(TractionControl, values.TractionControl),
            Name(OnOff, values.AntiLockBrakes),
            Name(OnOff, values.SteeringAssist),
            Name(BrakingAssist, values.BrakingAssist),
            Name(Gearbox, values.GearboxAssist),
            Name(RacingLine, values.DynamicRacingLine));

        return dto is { TractionControl: null, AntiLockBrakes: null, SteeringAssist: null, BrakingAssist: null, Gearbox: null, RacingLine: null }
            ? null
            : dto;
    }

    private static string? Name(IReadOnlyList<string?> names, int? raw)
        => raw is { } value && value >= 0 && value < names.Count ? names[value] : null;
}
