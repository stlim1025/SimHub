using F1Game.UDP.Data;
using F1Game.UDP.Packets;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// F1 25 플레이어 차·세션의 <c>car.details</c> 묶음(D-49, docs/15 §8). 키·뜻의 진실 원천은 <c>shared/telemetry/f1_25_udp_spec.md</c> §7이다 —
/// 여기를 바꾸면 그 표도 같이 바꾼다. 스냅샷 본체(<c>car</c>)와 트레이스 extra에 이미 있는 값은 되풀이하지 않는 것을 원칙으로 하되,
/// 셋업·설정처럼 랩 단위로 보는 값은 여기에 둔다. 열거형은 게임 원시 정수다.
/// </summary>
internal static class F1DetailSections
{
    public const string Setup = "setup";
    public const string Damage = "damage";
    public const string Status = "status";
    public const string TyreSets = "tyreSets";
    public const string TimeTrial = "timeTrial";
    public const string Session = "session";
    public const string Participant = "participant";
    public const string LapData = "lapData";

    private const int MillisecondsPerMinute = 60_000;

    /// <summary>Car Setups(5)의 플레이어 칸 + 패킷의 다음 앞날개 값.</summary>
    public static IReadOnlyDictionary<string, object?> FromSetup(CarSetupData car, float nextFrontWingValue) => new DetailBag()
        .Add("frontWing", car.FrontWing)
        .Add("rearWing", car.RearWing)
        .Add("onThrottle", car.OnThrottle)
        .Add("offThrottle", car.OffThrottle)
        .Add("frontCamber", car.FrontCamber)
        .Add("rearCamber", car.RearCamber)
        .Add("frontToe", car.FrontToe)
        .Add("rearToe", car.RearToe)
        .Add("frontSuspension", car.FrontSuspension)
        .Add("rearSuspension", car.RearSuspension)
        .Add("frontAntiRollBar", car.FrontAntiRollBar)
        .Add("rearAntiRollBar", car.RearAntiRollBar)
        .Add("frontSuspensionHeight", car.FrontSuspensionHeight)
        .Add("rearSuspensionHeight", car.RearSuspensionHeight)
        .Add("brakePressure", car.BrakePressure)
        .Add("brakeBias", car.BrakeBias)
        .Add("engineBraking", car.EngineBraking)
        .AddWheels("tyrePressure", car.TyresPressure, value => value)
        .Add("ballast", car.Ballast)
        .Add("fuelLoad", car.FuelLoad)
        .Add("nextFrontWingValue", nextFrontWingValue)
        .Build();

    /// <summary>Car Damage(10)의 나머지 — 블리스터·고장·엔진 부품 마모(%).</summary>
    public static IReadOnlyDictionary<string, object?> FromDamage(CarDamageData car) => new DetailBag()
        .AddWheels("tyreBlisters", car.TyresBlisters, value => value)
        .Add("drsFault", car.DrsFault)
        .Add("ersFault", car.ErsFault)
        .Add("engineMguhWear", car.EngineMGUHWear)
        .Add("engineEsWear", car.EngineESWear)
        .Add("engineCeWear", car.EngineCEWear)
        .Add("engineIceWear", car.EngineICEWear)
        .Add("engineMgukWear", car.EngineMGUKWear)
        .Add("engineTcWear", car.EngineTCWear)
        .Add("engineBlown", car.EngineBlown)
        .Add("engineSeized", car.EngineSeized)
        .Build();

    /// <summary>Car Status(7)의 나머지 — 보조 장치·한계값·출력·깃발(연료·ERS·타이어는 <c>car</c> 본체에 있다).</summary>
    public static IReadOnlyDictionary<string, object?> FromStatus(CarStatusData car) => new DetailBag()
        .Add("tractionControl", (int)car.TractionControl)
        .Add("antiLockBrakes", (int)car.AntiLockBrakes)
        .Add("fuelMix", (int)car.FuelMix)
        .Add("frontBrakeBias", car.FrontBrakeBias)
        .Add("pitLimiter", car.IsPitLimiterOn)
        .Add("fuelCapacity", car.FuelCapacity)
        .Add("maxRpm", car.MaxRPM)
        .Add("idleRpm", car.IdleRPM)
        .Add("maxGears", car.MaxGears)
        .Add("drsAllowed", car.DrsAllowed)
        .Add("drsActivationDistance", car.DrsActivationDistance)
        .Add("vehicleFiaFlag", (int)car.VehicleFiaFlags)
        .Add("enginePowerIce", car.EnginePowerICE)
        .Add("enginePowerMguk", car.EnginePowerMGUK)
        .Add("ersDeployMode", (int)car.ErsDeployMode)
        .Add("networkPaused", car.NetworkPaused)
        .Build();

    /// <summary>Tyre Sets(12) — 플레이어 차의 세트 20개와 지금 낀 세트 번호.</summary>
    public static IReadOnlyDictionary<string, object?> FromTyreSets(TyreSetsDataPacket packet)
    {
        var sets = packet.TyreSetDatas.AsReadOnlySpan();
        var mapped = new object?[sets.Length];
        for (var i = 0; i < sets.Length; i++)
        {
            mapped[i] = FromTyreSet(sets[i]);
        }

        return new DetailBag().Add("fittedIndex", packet.FittedIndex).Add("sets", mapped).Build();
    }

    /// <summary>Time Trial(14) — 이 세션 베스트·개인 베스트·라이벌 데이터 세트.</summary>
    public static IReadOnlyDictionary<string, object?> FromTimeTrial(TimeTrialDataPacket packet) => new DetailBag()
        .Add("playerSessionBest", FromTimeTrialSet(packet.PlayerSessionBestDataSet))
        .Add("personalBest", FromTimeTrialSet(packet.PersonalBestDataSet))
        .Add("rival", FromTimeTrialSet(packet.RivalDataSet))
        .Build();

    /// <summary>Participants(4)의 플레이어 칸. 이름은 NUL을 자른 값을 받는다.</summary>
    public static IReadOnlyDictionary<string, object?> FromParticipant(ParticipantData player, int carIndex, string name) => new DetailBag()
        .Add("carIndex", carIndex)
        .Add("aiControlled", player.IsAiControlled)
        .Add("driverId", (int)player.Driver)
        .Add("networkId", player.NetworkId)
        .Add("teamId", (int)player.Team)
        .Add("myTeam", player.IsMyTeam)
        .Add("raceNumber", player.RaceNumber)
        .Add("nationality", (int)player.Nationality)
        .Add("name", name)
        .Add("telemetryPublic", player.IsTelemetryPublic)
        .Add("showOnlineNames", player.ShowOnlineNames)
        .Add("techLevel", player.TechLevel)
        .Add("platform", (int)player.Platform)
        .Build();

    /// <summary>Lap Data(2)의 플레이어 칸 나머지(순위·패널티·경고·피트·스피드 트랩) + 패킷의 타임 트라이얼 고스트 번호.</summary>
    public static IReadOnlyDictionary<string, object?> FromLapData(LapData lap, int carIndex, LapDataPacket packet) => new DetailBag()
        .Add("carIndex", carIndex)
        .Add("lapDistance", lap.LapDistance)
        .Add("totalDistance", lap.TotalDistance)
        .Add("carPosition", lap.CarPosition)
        .Add("currentLapNum", lap.CurrentLapNum)
        .Add("pitStatus", (int)lap.PitStatus)
        .Add("numPitStops", lap.NumPitStops)
        .Add("sector", (int)lap.Sector)
        .Add("currentLapInvalid", lap.IsCurrentLapInvalid)
        .Add("penaltiesS", lap.Penalties)
        .Add("totalWarnings", lap.TotalWarnings)
        .Add("cornerCuttingWarnings", lap.CornerCuttingWarnings)
        .Add("numUnservedDriveThroughPens", lap.NumUnservedDriveThroughPens)
        .Add("numUnservedStopGoPens", lap.NumUnservedStopGoPens)
        .Add("gridPosition", lap.GridPosition)
        .Add("driverStatus", (int)lap.DriverStatus)
        .Add("resultStatus", (int)lap.ResultStatus)
        .Add("pitLaneTimerActive", lap.PitLaneTimerActive)
        .Add("pitLaneTimeInLaneMs", lap.PitLaneTimeInLaneInMS)
        .Add("pitStopTimerMs", lap.PitStopTimerInMS)
        .Add("pitStopShouldServePen", lap.PitStopShouldServePen)
        .Add("speedTrapFastestSpeedKph", lap.SpeedTrapFastestSpeed)
        .Add("speedTrapFastestLap", lap.SpeedTrapFastestLap)
        .Add("timeTrialPbCarIndex", packet.TimeTrialPBCarIdx)
        .Add("timeTrialRivalCarIndex", packet.TimeTrialRivalCarIdx)
        .Build();

    private static IReadOnlyDictionary<string, object?> FromTyreSet(TyreSetData set) => new DetailBag()
        .Add("actualCompound", (int)set.ActualTyreCompound)
        .Add("visualCompound", (int)set.VisualTyreCompound)
        .Add("wearPercent", set.Wear)
        .Add("available", set.IsAvailable)
        .Add("recommendedSession", (int)set.RecommendedSession)
        .Add("lifeSpanLaps", set.LifeSpan)
        .Add("usableLifeLaps", set.UsableLife)
        .Add("lapDeltaTimeMs", set.LapDeltaTime)
        .Add("fitted", set.IsFitted)
        .Build();

    private static IReadOnlyDictionary<string, object?> FromTimeTrialSet(TimeTrialDataSet set) => new DetailBag()
        .Add("carIndex", set.CarIndex)
        .Add("teamId", (int)set.Team)
        .Add("lapTimeMs", set.LapTimeInMS)
        .Add("sector1TimeMs", set.Sector1TimeInMS)
        .Add("sector2TimeMs", set.Sector2TimeInMS)
        .Add("sector3TimeMs", set.Sector3TimeInMS)
        .Add("tractionControl", (int)set.TractionControl)
        .Add("gearboxAssist", (int)set.GearboxAssist)
        .Add("antiLockBrakes", (int)set.AntiLockBrakes)
        .Add("equalCarPerformance", set.IsEqualCarPerformance)
        .Add("customSetup", set.IsCustomSetupEnabled)
        .Add("valid", set.IsValid)
        .Build();

    /// <summary>분 칸 + 밀리초 칸 → 밀리초.</summary>
    internal static int ToMilliseconds(byte minutes, ushort milliseconds) => (minutes * MillisecondsPerMinute) + milliseconds;
}
