using System.Text.Json;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 세션에 연결된 내 저장 랩 1건의 읽기 행(<c>(UserId, GameCode, SessionKey)</c>로 잇는다 — docs/15 §11.4). 저장소가 한 쿼리로 만든다.
/// 스냅샷이 없는 옛 랩은 스냅샷 값이 모두 null이다.
/// </summary>
public sealed record SessionLapRow(
    Guid LapId,
    int LapNumber,
    int LapTimeMs,
    bool IsValid,
    DateTime SetAt,
    IReadOnlyList<int?> Sectors,
    string? SnapshotDetails,
    Weather? Weather,
    double? TyreWearEndFrontLeft,
    double? TyreWearEndFrontRight,
    double? TyreWearEndRearLeft,
    double? TyreWearEndRearRight,
    int? GearboxDamage,
    int? EngineDamage,
    double? ErsStoreEndJ = null,
    double? ErsDeployedJ = null,
    double? ErsHarvestedJ = null);

/// <summary>PENA 이벤트 한 건(f1_25_udp_spec §7 이벤트 표). 모르는 칸은 null.</summary>
public sealed record PenaltyEvent(
    int? PenaltyType,
    int? InfringementType,
    int? VehicleIndex,
    int? OtherVehicleIndex,
    int? TimeS,
    int? LapNumber);

/// <summary>엔진 부품 마모(%) — <c>details.damage</c>의 <c>engine*Wear</c> 키(f1_25_udp_spec §7).</summary>
public sealed record EngineComponentWear(int? Ice, int? TurboCharger, int? MguH, int? MguK, int? EnergyStore, int? ControlElectronics)
{
    public bool HasAny => Ice.HasValue || TurboCharger.HasValue || MguH.HasValue || MguK.HasValue || EnergyStore.HasValue || ControlElectronics.HasValue;
}

/// <summary>
/// 세션 상세가 쓰는 내 랩 1건 = 읽기 행 + 스냅샷 <c>details</c>(D-49)에서 뽑은 값. <see cref="From"/>이 jsonb를 한 번만 연다.
/// </summary>
public sealed record MySessionLap(
    SessionLapRow Row,
    JsonElement? Setup,
    EngineComponentWear? EngineWear,
    int? PitStatus,
    int? PlayerCarIndex,
    IReadOnlyList<PenaltyEvent> Penalties,
    double? TyreLifeRemaining)
{
    private const string PenaltyEventCode = "PENA";
    private const double FullLifePercent = 100d;
    private const int LifeDecimals = 1;

    public int LapNumber => Row.LapNumber;

    public static MySessionLap From(SessionLapRow row)
    {
        ArgumentNullException.ThrowIfNull(row);
        var life = TyreLife(row);

        using var document = JsonReads.ParseObject(row.SnapshotDetails);
        if (document is null)
        {
            return new MySessionLap(row, null, null, null, null, [], life);
        }

        var root = document.RootElement;
        var lapData = JsonReads.Object(root, "lapData");
        var participant = JsonReads.Object(root, "participant");

        return new MySessionLap(
            row,
            JsonReads.Object(root, "setup")?.Clone(),
            ReadWear(root),
            lapData is { } lap ? JsonReads.Int(lap, "pitStatus") : null,
            (lapData is { } l ? JsonReads.Int(l, "carIndex") : null) ?? (participant is { } p ? JsonReads.Int(p, "carIndex") : null),
            ReadPenalties(root),
            life);
    }

    private static EngineComponentWear? ReadWear(JsonElement root)
    {
        if (JsonReads.Object(root, "damage") is not { } damage)
        {
            return null;
        }

        var wear = new EngineComponentWear(
            JsonReads.Int(damage, "engineIceWear"),
            JsonReads.Int(damage, "engineTcWear"),
            JsonReads.Int(damage, "engineMguhWear"),
            JsonReads.Int(damage, "engineMgukWear"),
            JsonReads.Int(damage, "engineEsWear"),
            JsonReads.Int(damage, "engineCeWear"));
        return wear.HasAny ? wear : null;
    }

    private static List<PenaltyEvent> ReadPenalties(JsonElement root)
    {
        var penalties = new List<PenaltyEvent>();
        if (JsonReads.Array(root, "events") is not { } events)
        {
            return penalties;
        }

        foreach (var item in events.EnumerateArray())
        {
            if (JsonReads.String(item, "code") != PenaltyEventCode || JsonReads.Object(item, "details") is not { } details)
            {
                continue;
            }

            penalties.Add(new PenaltyEvent(
                JsonReads.Int(details, "penaltyType"),
                JsonReads.Int(details, "infringementType"),
                JsonReads.Int(details, "vehicleIndex"),
                JsonReads.Int(details, "otherVehicleIndex"),
                JsonReads.Int(details, "timeS"),
                JsonReads.Int(details, "lapNumber")));
        }

        return penalties;
    }

    /// <summary>100 − 네 바퀴 끝 마모 평균(있는 바퀴만, 0~100으로 자르고 소수 첫째 자리). 하나도 없으면 null(docs/15 §11.3).</summary>
    private static double? TyreLife(SessionLapRow row)
    {
        double?[] wears = [row.TyreWearEndFrontLeft, row.TyreWearEndFrontRight, row.TyreWearEndRearLeft, row.TyreWearEndRearRight];
        var known = wears.Where(w => w is { } value && double.IsFinite(value)).Select(w => w!.Value).ToList();
        if (known.Count == 0)
        {
            return null;
        }

        var remaining = Math.Clamp(FullLifePercent - known.Average(), 0d, FullLifePercent);
        return Math.Round(remaining, LifeDecimals, MidpointRounding.AwayFromZero);
    }
}
