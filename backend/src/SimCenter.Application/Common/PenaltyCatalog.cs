namespace SimCenter.Application.Common;

/// <summary>
/// F1 25 UDP 패널티 이벤트(PENA)의 벌칙 종류(0~17)·침해 종류(0~54) 영어 이름 정적 표(docs/15 §11.4, D-53 — D-33과 같은 원칙).
/// 이름은 F1 25 UDP 스펙 표의 문구(F1Laps 표시와 같게)다. 불변 상수 표라 "Global Static 금지"(가변 전역 상태)에 해당하지 않는다.
/// 모르는 번호는 <c>Unknown ({n})</c>.
/// </summary>
public static class PenaltyCatalog
{
    private static readonly string[] PenaltyTypes =
    [
        "Drive through",
        "Stop Go",
        "Grid penalty",
        "Penalty reminder",
        "Time penalty",
        "Warning",
        "Disqualified",
        "Removed from formation lap",
        "Parked too long timer",
        "Tyre regulations",
        "This lap invalidated",
        "This and next lap invalidated",
        "This lap invalidated without reason",
        "This and next lap invalidated without reason",
        "This and previous lap invalidated",
        "This and previous lap invalidated without reason",
        "Retired",
        "Black flag timer",
    ];

    private static readonly string[] InfringementTypes =
    [
        "Blocking by slow driving",
        "Blocking by wrong way driving",
        "Reversing off the start line",
        "Big Collision",
        "Small Collision",
        "Collision failed to hand back position single",
        "Collision failed to hand back position multiple",
        "Corner cutting gained time",
        "Corner cutting overtake single",
        "Corner cutting overtake multiple",
        "Crossed pit exit lane",
        "Ignoring blue flags",
        "Ignoring yellow flags",
        "Ignoring drive through",
        "Too many drive throughs",
        "Drive through reminder serve within n laps",
        "Drive through reminder serve this lap",
        "Pit lane speeding",
        "Parked for too long",
        "Ignoring tyre regulations",
        "Too many penalties",
        "Multiple warnings",
        "Approaching disqualification",
        "Tyre regulations select single",
        "Tyre regulations select multiple",
        "Lap invalidated corner cutting",
        "Lap invalidated running wide",
        "Corner cutting ran wide gained time minor",
        "Corner cutting ran wide gained time significant",
        "Corner cutting ran wide gained time extreme",
        "Lap invalidated wall riding",
        "Lap invalidated flashback used",
        "Lap invalidated reset to track",
        "Blocking the pitlane",
        "Jump start",
        "Safety car to car collision",
        "Safety car illegal overtake",
        "Safety car exceeding allowed pace",
        "Virtual safety car exceeding allowed pace",
        "Formation lap below allowed speed",
        "Formation lap parking",
        "Retired mechanical failure",
        "Retired terminally damaged",
        "Safety car falling too far back",
        "Black flag timer",
        "Unserved stop go penalty",
        "Unserved drive through penalty",
        "Engine component change",
        "Gearbox change",
        "Parc Fermé change",
        "League grid penalty",
        "Retry penalty",
        "Illegal time gain",
        "Mandatory pitstop",
        "Attribute assigned",
    ];

    /// <summary>벌칙 종류 수(0부터).</summary>
    public static int PenaltyTypeCount => PenaltyTypes.Length;

    /// <summary>침해 종류 수(0부터).</summary>
    public static int InfringementTypeCount => InfringementTypes.Length;

    /// <summary>벌칙 종류 이름. 모르거나 없으면 <c>Unknown ({n})</c>.</summary>
    public static string PenaltyName(int? penaltyType) => NameOf(PenaltyTypes, penaltyType);

    /// <summary>침해 종류 이름. 모르거나 없으면 <c>Unknown ({n})</c>.</summary>
    public static string InfringementName(int? infringementType) => NameOf(InfringementTypes, infringementType);

    private static string NameOf(string[] names, int? value)
        => value is { } index && index >= 0 && index < names.Length
            ? names[index]
            : $"Unknown ({value?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "-"})";
}
