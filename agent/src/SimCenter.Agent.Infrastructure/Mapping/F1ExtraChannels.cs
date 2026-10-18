using F1Game.UDP.Data;
using F1Game.UDP.Packets;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// F1 25 플레이어 차의 트레이스 extra 채널(D-49, docs/15 §8). 이름·단위·배율의 진실 원천은 <c>shared/telemetry/f1_25_udp_spec.md</c> §6 카탈로그다 —
/// 여기를 바꾸면 카탈로그도 같이 바꾼다. 각도는 라디안 → 도, 높이는 m → mm, 슬립 비는 × 100(%)로 바꿔 소수 둘째 자리에서도 해상도를 지킨다.
/// 힘(N)·에너지(J)·출력(W)·가속도처럼 큰 값은 정수로 둔다(봉투 크기).
/// </summary>
internal static class F1ExtraChannels
{
    private const int Integer = 0;
    private const int OneDecimal = 1;
    private const double DegreesPerRadian = 180.0 / Math.PI;
    private const double MillimetresPerMetre = 1000.0;
    private const double PercentPerRatio = 100.0;
    private const int MillisecondsPerMinute = 60_000;

    /// <summary>Car Telemetry(6) — 클러치·DRS·온도·공기압·노면, 패킷의 추천 기어.</summary>
    public static IReadOnlyDictionary<string, double> FromCarTelemetry(CarTelemetryData car, byte suggestedGear) => new ChannelBag()
        .Add("clutch", car.Clutch, Integer)
        .Add("drs", car.IsDrsOn)
        .Add("revLightsPercent", car.RevLightsPercent, Integer)
        .AddWheels("brakeTemp", car.BrakesTemperature, value => value, Integer)
        .AddWheels("tyreSurfaceTemp", car.TyresSurfaceTemperature, value => value, Integer)
        .AddWheels("tyreInnerTemp", car.TyresInnerTemperature, value => value, Integer)
        .Add("engineTemp", car.EngineTemperature, Integer)
        .AddWheels("tyrePressure", car.TyresPressure, value => value)
        .AddWheels("surfaceType", car.SurfaceType, value => (int)value, Integer)
        .Add("suggestedGear", suggestedGear, Integer)
        .Build();

    /// <summary>Car Status(7) — 랩 중 바뀌는 값(보조 장치·연료·ERS·출력·FIA 깃발).</summary>
    public static IReadOnlyDictionary<string, double> FromCarStatus(CarStatusData car) => new ChannelBag()
        .Add("tractionControl", (int)car.TractionControl, Integer)
        .Add("antiLockBrakes", (int)car.AntiLockBrakes, Integer)
        .Add("fuelMix", (int)car.FuelMix, Integer)
        .Add("frontBrakeBias", car.FrontBrakeBias, Integer)
        .Add("pitLimiter", car.IsPitLimiterOn)
        .Add("fuelInTank", car.FuelInTank)
        .Add("fuelRemainingLaps", car.FuelRemainingLaps)
        .Add("drsAllowed", car.DrsAllowed)
        .Add("vehicleFiaFlag", (int)car.VehicleFiaFlags, Integer)
        .Add("enginePowerIce", car.EnginePowerICE, Integer)
        .Add("enginePowerMguk", car.EnginePowerMGUK, Integer)
        .Add("ersStoreEnergy", car.ErsStoreEnergy, Integer)
        .Add("ersDeployMode", (int)car.ErsDeployMode, Integer)
        .Add("ersHarvestedThisLapMguk", car.ErsHarvestedThisLapMGUK, Integer)
        .Add("ersHarvestedThisLapMguh", car.ErsHarvestedThisLapMGUH, Integer)
        .Add("ersDeployedThisLap", car.ErsDeployedThisLap, Integer)
        .Build();

    /// <summary>Motion(0)의 플레이어 칸 — 월드 위치·속도, G-force, 자세(다른 차 Motion은 읽지 않는다 — 헌장).</summary>
    public static IReadOnlyDictionary<string, double> FromMotion(CarMotionData car) => new ChannelBag()
        .Add("worldPosX", car.WorldPositionX, OneDecimal)
        .Add("worldPosY", car.WorldPositionY, OneDecimal)
        .Add("worldPosZ", car.WorldPositionZ, OneDecimal)
        .Add("worldVelX", car.WorldVelocityX)
        .Add("worldVelY", car.WorldVelocityY)
        .Add("worldVelZ", car.WorldVelocityZ)
        .Add("gForceLateral", car.GForceLateral)
        .Add("gForceLongitudinal", car.GForceLongitudinal)
        .Add("gForceVertical", car.GForceVertical)
        .Add("yawDeg", car.Yaw * DegreesPerRadian)
        .Add("pitchDeg", car.Pitch * DegreesPerRadian)
        .Add("rollDeg", car.Roll * DegreesPerRadian)
        .Build();

    /// <summary>Motion Ex(13, 플레이어 전용) — 서스펜션·휠·차체 동역학.</summary>
    public static IReadOnlyDictionary<string, double> FromMotionEx(MotionExDataPacket motion) => new ChannelBag()
        .AddWheels("suspensionPosition", motion.SuspensionPosition, value => value)
        .AddWheels("suspensionVelocity", motion.SuspensionVelocity, value => value)
        .AddWheels("suspensionAcceleration", motion.SuspensionAcceleration, value => value, Integer)
        .AddWheels("wheelSpeed", motion.WheelSpeed, value => value)
        .AddWheels("wheelSlipRatioPct", motion.WheelSlipRatio, value => value * PercentPerRatio)
        .AddWheels("wheelSlipAngleDeg", motion.WheelSlipAngle, value => value * DegreesPerRadian)
        .AddWheels("wheelLatForce", motion.WheelLateralForce, value => value, Integer)
        .AddWheels("wheelLongForce", motion.WheelLongitudinalForce, value => value, Integer)
        .AddWheels("wheelVertForce", motion.WheelVerticalForce, value => value, Integer)
        .AddWheels("wheelCamberDeg", motion.WheelsCamper, value => value * DegreesPerRadian)
        .AddWheels("wheelCamberGainDeg", motion.WheelsCamperGain, value => value * DegreesPerRadian)
        .Add("heightOfCogMm", motion.HeightOfCOGAboveGround * MillimetresPerMetre, OneDecimal)
        .Add("localVelX", motion.LocalVelocityX)
        .Add("localVelY", motion.LocalVelocityY)
        .Add("localVelZ", motion.LocalVelocityZ)
        .Add("angularVelX", motion.AngularVelocityX)
        .Add("angularVelY", motion.AngularVelocityY)
        .Add("angularVelZ", motion.AngularVelocityZ)
        .Add("angularAccX", motion.AngularAccelerationX)
        .Add("angularAccY", motion.AngularAccelerationY)
        .Add("angularAccZ", motion.AngularAccelerationZ)
        .Add("frontWheelsAngleDeg", motion.FrontWheelsAngle * DegreesPerRadian)
        .Add("frontAeroHeightMm", motion.FrontAeroHeight * MillimetresPerMetre, OneDecimal)
        .Add("rearAeroHeightMm", motion.RearAeroHeight * MillimetresPerMetre, OneDecimal)
        .Add("frontRollAngleDeg", motion.FrontRollAngle * DegreesPerRadian)
        .Add("rearRollAngleDeg", motion.RearRollAngle * DegreesPerRadian)
        .Add("chassisYawDeg", motion.ChassisYaw * DegreesPerRadian)
        .Add("chassisPitchDeg", motion.ChassisPitch * DegreesPerRadian)
        .Build();

    /// <summary>Lap Data(2)의 플레이어 칸 — 순위·간격·세이프티카 델타.</summary>
    public static IReadOnlyDictionary<string, double> FromLapData(LapData lap) => new ChannelBag()
        .Add("carPosition", lap.CarPosition, Integer)
        .Add("deltaToCarInFrontMs", (lap.DeltaToCarInFrontInMinutes * MillisecondsPerMinute) + lap.DeltaToCarInFrontInMS, Integer)
        .Add("deltaToRaceLeaderMs", (lap.DeltaToRaceLeaderInMinutes * MillisecondsPerMinute) + lap.DeltaToRaceLeaderInMS, Integer)
        .Add("safetyCarDelta", lap.SafetyCarDelta)
        .Build();
}
