namespace SimCenter.Application.Laps.Ingest;

/// <summary>
/// 랩 스냅샷 검증(15 §5): 퍼센트 0~100, 기온 −50~80, 연료 0~200kg, ERS 0~10,000,000J, 컴파운드·나이 0~255.
/// 틀린 값의 설명 목록을 돌려준다(비면 통과). 영역(car·conditions)마다 따로 검증해 틀린 영역만 버린다.
/// 날씨 이름은 검증하지 않는다 — 모르는 이름은 저장만 하지 않는다(<see cref="LapDetailExtractor"/>).
/// </summary>
public static class LapSnapshotValidator
{
    public const double MinPercent = 0;
    public const double MaxPercent = 100;
    public const int MinTemperatureC = -50;
    public const int MaxTemperatureC = 80;
    public const double MaxFuelKg = 200;

    /// <summary>남은 랩(MFD 값)은 연료가 모자라면 음수다 — 연료 한도와 같은 크기로 ± 범위를 둔다.</summary>
    public const double MaxAbsFuelRemainingLaps = 200;

    public const double MaxErsJ = 10_000_000;
    public const int MaxByteValue = 255;

    /// <summary>게임 팀 ID 상한(F1 25 시즌팩 ID 476~가 있어 1바이트를 넘는다).</summary>
    public const int MaxTeamId = ushort.MaxValue;

    public static IReadOnlyList<string> Validate(LapCarPayload car)
    {
        ArgumentNullException.ThrowIfNull(car);
        var errors = new List<string>();

        Range(errors, "teamId", car.TeamId, 0, MaxTeamId);
        Range(errors, "visualTyreCompound", car.VisualTyreCompound, 0, MaxByteValue);
        Range(errors, "actualTyreCompound", car.ActualTyreCompound, 0, MaxByteValue);
        Range(errors, "tyreAgeLaps", car.TyreAgeLaps, 0, MaxByteValue);

        Wheels(errors, "tyreWearStart", car.TyreWearStart);
        Wheels(errors, "tyreWearEnd", car.TyreWearEnd);
        Wheels(errors, "tyreDamage", car.TyreDamage);
        Wheels(errors, "brakeDamage", car.BrakeDamage);

        Range(errors, "frontLeftWingDamage", car.FrontLeftWingDamage, MinPercent, MaxPercent);
        Range(errors, "frontRightWingDamage", car.FrontRightWingDamage, MinPercent, MaxPercent);
        Range(errors, "rearWingDamage", car.RearWingDamage, MinPercent, MaxPercent);
        Range(errors, "floorDamage", car.FloorDamage, MinPercent, MaxPercent);
        Range(errors, "diffuserDamage", car.DiffuserDamage, MinPercent, MaxPercent);
        Range(errors, "sidepodDamage", car.SidepodDamage, MinPercent, MaxPercent);
        Range(errors, "gearboxDamage", car.GearboxDamage, MinPercent, MaxPercent);
        Range(errors, "engineDamage", car.EngineDamage, MinPercent, MaxPercent);

        Range(errors, "fuelStartKg", car.FuelStartKg, 0, MaxFuelKg);
        Range(errors, "fuelEndKg", car.FuelEndKg, 0, MaxFuelKg);
        Range(errors, "fuelRemainingLaps", car.FuelRemainingLaps, -MaxAbsFuelRemainingLaps, MaxAbsFuelRemainingLaps);

        Range(errors, "ersStoreStartJ", car.ErsStoreStartJ, 0, MaxErsJ);
        Range(errors, "ersStoreEndJ", car.ErsStoreEndJ, 0, MaxErsJ);
        Range(errors, "ersDeployedJ", car.ErsDeployedJ, 0, MaxErsJ);
        Range(errors, "ersHarvestedJ", car.ErsHarvestedJ, 0, MaxErsJ);

        return errors;
    }

    public static IReadOnlyList<string> Validate(LapConditionsPayload conditions)
    {
        ArgumentNullException.ThrowIfNull(conditions);
        var errors = new List<string>();

        Range(errors, "airTempC", conditions.AirTempC, MinTemperatureC, MaxTemperatureC);
        Range(errors, "trackTempC", conditions.TrackTempC, MinTemperatureC, MaxTemperatureC);
        Range(errors, "rainForecastPercent", conditions.RainForecastPercent, MinPercent, MaxPercent);

        return errors;
    }

    /// <summary>값이 있으면 유한한 수이고 [min, max] 안이어야 한다. null은 통과(받지 못한 값).</summary>
    private static void Range(List<string> errors, string field, double? value, double min, double max)
    {
        if (value is not { } number)
        {
            return;
        }

        if (!double.IsFinite(number) || number < min || number > max)
        {
            errors.Add($"{field}={number}(허용 {min}~{max})");
        }
    }

    /// <summary>바퀴 묶음은 오면 4개가 모두 있어야 하고, 각각 퍼센트 범위다.</summary>
    private static void Wheels(List<string> errors, string field, WheelValuesPayload? wheels)
    {
        if (wheels is null)
        {
            return;
        }

        if (wheels.FrontLeft is null || wheels.FrontRight is null || wheels.RearLeft is null || wheels.RearRight is null)
        {
            errors.Add($"{field}: 바퀴 4개 값이 모두 있어야 합니다");
            return;
        }

        Range(errors, $"{field}.frontLeft", wheels.FrontLeft, MinPercent, MaxPercent);
        Range(errors, $"{field}.frontRight", wheels.FrontRight, MinPercent, MaxPercent);
        Range(errors, $"{field}.rearLeft", wheels.RearLeft, MinPercent, MaxPercent);
        Range(errors, $"{field}.rearRight", wheels.RearRight, MinPercent, MaxPercent);
    }
}
