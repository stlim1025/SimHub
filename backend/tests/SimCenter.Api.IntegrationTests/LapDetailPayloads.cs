using SimCenter.Domain.Constants;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 랩 상세 E2E용 LapFinished 봉투(15 §4.3). 계약 이름을 손으로 적은 익명 객체다 — Agent가 보낼 JSON과 같은 모양.
/// </summary>
internal static class LapDetailPayloads
{
    public const int JeddahGameTrackId = 29;
    public const int TraceSamples = 1_235;

    /// <summary>
    /// LapFinished 봉투. <paramref name="car"/>·<paramref name="conditions"/>·<paramref name="trace"/>가 null이면 그 영역을 싣지 않는다(옛 Agent).
    /// </summary>
    public static object LapFinished(
        int lapNumber,
        int lapTimeMs,
        bool isValid,
        DateTime occurredAt,
        string sessionRef = "0xDETAIL",
        object? car = null,
        object? conditions = null,
        object? trace = null,
        int gameTrackId = JeddahGameTrackId,
        string sessionType = "TimeTrial")
    {
        var payload = new Dictionary<string, object?>
        {
            ["sessionRef"] = sessionRef,
            ["lapNumber"] = lapNumber,
            ["lapTimeMs"] = lapTimeMs,
            ["sectors"] = new[]
            {
                new { sectorNumber = 1, sectorTimeMs = lapTimeMs / 3 },
                new { sectorNumber = 2, sectorTimeMs = lapTimeMs / 3 },
                new { sectorNumber = 3, sectorTimeMs = lapTimeMs - (2 * (lapTimeMs / 3)) },
            },
            ["isValid"] = isValid,
            ["isOutOrInLap"] = false,
            ["trackId"] = gameTrackId,
            ["sessionType"] = sessionType,
            ["gameMode"] = "DriverCareer",
            ["seasonLinkId"] = 11L,
            ["weekendLinkId"] = 22L,
            ["sessionLinkId"] = 33L,
        };

        if (car is not null)
        {
            payload["car"] = car;
        }

        if (conditions is not null)
        {
            payload["conditions"] = conditions;
        }

        if (trace is not null)
        {
            payload["trace"] = trace;
        }

        return new
        {
            eventId = Guid.NewGuid(),
            gameCode = GameCodes.F1_25,
            occurredAt,
            type = "LapFinished",
            payload,
        };
    }

    public static object Car() => new
    {
        teamId = 1, // Ferrari
        visualTyreCompound = 16,
        actualTyreCompound = 18,
        tyreAgeLaps = 3,
        tyreWearStart = new { frontLeft = 27.0, frontRight = 14.0, rearLeft = 20.0, rearRight = 14.5 },
        tyreWearEnd = new { frontLeft = 31.0, frontRight = 18.0, rearLeft = 24.0, rearRight = 18.5 },
        tyreDamage = new { frontLeft = 3.0, frontRight = 2.0, rearLeft = 1.0, rearRight = 0.0 },
        brakeDamage = new { frontLeft = 0.0, frontRight = 0.0, rearLeft = 5.0, rearRight = 6.0 },
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

    public static object Conditions() => new { weather = "LightCloud", airTempC = 21, trackTempC = 31, rainForecastPercent = 4 };

    /// <summary>5m 간격 트레이스(Jeddah 약 6.2km = 1,235칸). 값은 결정적이다.</summary>
    public static TraceChannels Trace(int samples = TraceSamples)
        => new(
            5,
            Enumerable.Range(0, samples).Select(i => i * 79).ToArray(),
            Enumerable.Range(0, samples).Select(i => 80 + (i * 7 % 250)).ToArray(),
            Enumerable.Range(0, samples).Select(i => i * 3 % 101).ToArray(),
            Enumerable.Range(0, samples).Select(i => i % 9 == 0 ? 100 : 0).ToArray(),
            Enumerable.Range(0, samples).Select(i => (i * 13 % 201) - 100).ToArray(),
            Enumerable.Range(0, samples).Select(i => (i % 10) - 1).ToArray(),
            Enumerable.Range(0, samples).Select(i => 4_000 + (i * 37 % 8_500)).ToArray());

    /// <summary>와이어 모양 트레이스(15 §4.3).</summary>
    public sealed record TraceChannels(
        int ResolutionM, int[] TimeMs, int[] SpeedKph, int[] Throttle, int[] Brake, int[] Steer, int[] Gear, int[] Rpm)
    {
        public object ToWire() => new
        {
            resolutionM = ResolutionM,
            timeMs = TimeMs,
            speedKph = SpeedKph,
            throttle = Throttle,
            brake = Brake,
            steer = Steer,
            gear = Gear,
            rpm = Rpm,
        };
    }
}
