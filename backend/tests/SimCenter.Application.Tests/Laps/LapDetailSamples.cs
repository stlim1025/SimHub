using System.Text.Json;
using SimCenter.Application.Laps.Ingest;

namespace SimCenter.Application.Tests.Laps;

/// <summary>
/// 랩 상세 시험 표본(15 §4.2·§4.3). 와이어 모양(<c>*Wire</c>)은 계약 이름을 손으로 적은 익명 객체다 — 이름이 어긋나면 해석 시험이 실패한다.
/// </summary>
internal static class LapDetailSamples
{
    public static readonly JsonSerializerOptions WireOptions = new(JsonSerializerDefaults.Web);

    public static LapCarPayload ValidCar() => new(
        TeamId: 1,
        VisualTyreCompound: 16,
        ActualTyreCompound: 18,
        TyreAgeLaps: 3,
        TyreWearStart: new(27, 14, 20, 15),
        TyreWearEnd: new(31, 18, 24, 19),
        TyreDamage: new(5, 6, 7, 8),
        BrakeDamage: new(1, 2, 3, 4),
        FrontLeftWingDamage: 0,
        FrontRightWingDamage: 10,
        RearWingDamage: 0,
        FloorDamage: 0,
        DiffuserDamage: 0,
        SidepodDamage: 20,
        GearboxDamage: 10,
        EngineDamage: 30,
        FuelStartKg: 24.4,
        FuelEndKg: 22.7,
        FuelRemainingLaps: 13.1,
        ErsStoreStartJ: 1_494_000,
        ErsStoreEndJ: 988_000,
        ErsDeployedJ: 2_100_000,
        ErsHarvestedJ: 1_600_000);

    public static LapConditionsPayload ValidConditions() => new("Clear", 21, 31, 4);

    public static LapTracePayload ValidTrace(int samples = 10, int resolutionM = 5) => new(
        resolutionM,
        Enumerable.Range(0, samples).Select(i => i * 100).ToArray(),
        Enumerable.Range(0, samples).Select(i => 100 + i % 200).ToArray(),
        Enumerable.Repeat(100, samples).ToArray(),
        Enumerable.Repeat(0, samples).ToArray(),
        Enumerable.Range(0, samples).Select(i => i % 2 == 0 ? -12 : 12).ToArray(),
        Enumerable.Repeat(7, samples).ToArray(),
        Enumerable.Repeat(11_000, samples).ToArray());

    public static object CarWire() => new
    {
        teamId = 1,
        visualTyreCompound = 16,
        actualTyreCompound = 18,
        tyreAgeLaps = 3,
        tyreWearStart = new { frontLeft = 27.0, frontRight = 14.0, rearLeft = 20.0, rearRight = 15.0 },
        tyreWearEnd = new { frontLeft = 31.0, frontRight = 18.0, rearLeft = 24.0, rearRight = 19.0 },
        tyreDamage = new { frontLeft = 5.0, frontRight = 6.0, rearLeft = 7.0, rearRight = 8.0 },
        brakeDamage = new { frontLeft = 1.0, frontRight = 2.0, rearLeft = 3.0, rearRight = 4.0 },
        frontLeftWingDamage = 0,
        frontRightWingDamage = 10,
        rearWingDamage = 0,
        floorDamage = 0,
        diffuserDamage = 0,
        sidepodDamage = 20,
        gearboxDamage = 10,
        engineDamage = 30,
        fuelStartKg = 24.4,
        fuelEndKg = 22.7,
        fuelRemainingLaps = 13.1,
        ersStoreStartJ = 1494000.0,
        ersStoreEndJ = 988000.0,
        ersDeployedJ = 2100000.0,
        ersHarvestedJ = 1600000.0,
    };

    public static object ConditionsWire() => new { weather = "Clear", airTempC = 21, trackTempC = 31, rainForecastPercent = 4 };

    public static object TraceWire(int samples = 10, int resolutionM = 5)
    {
        var t = ValidTrace(samples, resolutionM);
        return new
        {
            resolutionM,
            timeMs = t.TimeMs,
            speedKph = t.SpeedKph,
            throttle = t.Throttle,
            brake = t.Brake,
            steer = t.Steer,
            gear = t.Gear,
            rpm = t.Rpm,
        };
    }

    public static JsonElement ToElement(object value) => JsonSerializer.SerializeToElement(value, WireOptions);
}
