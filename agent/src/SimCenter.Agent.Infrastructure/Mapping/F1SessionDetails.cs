using F1Game.UDP.Data;
using F1Game.UDP.Packets;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// Session(1) 패킷 전체 → <c>car.details.session</c>(D-49, docs/15 §8, 키는 <c>f1_25_udp_spec.md</c> §7). 랩 끝의 최신 값이다 —
/// 설정(보조 장치·규칙·손상 설정 등)·마셜 구역 깃발·날씨 예보·주말 구성. 열거형은 게임 원시 정수. 개수 칸을 넘는 배열 칸은 쓰레기라 싣지 않는다.
/// 2인 화면 보조 플레이어 단위 설정은 싣지 않는다(개인 모드).
/// </summary>
internal static class F1SessionDetails
{
    public static IReadOnlyDictionary<string, object?> From(SessionDataPacket packet) => new DetailBag()
        .Add("trackId", (int)packet.Track)
        .Add("sessionType", (int)packet.SessionType)
        .Add("formula", (int)packet.Formula)
        .Add("weather", (int)packet.Weather)
        .Add("trackTemperature", packet.TrackTemperature)
        .Add("airTemperature", packet.AirTemperature)
        .Add("totalLaps", packet.TotalLaps)
        .Add("trackLength", packet.TrackLength)
        .Add("sessionTimeLeftS", packet.SessionTimeLeft)
        .Add("sessionDurationS", packet.SessionDuration)
        .Add("pitSpeedLimitKph", packet.PitSpeedLimit)
        .Add("gamePaused", packet.GamePaused)
        .Add("spectating", packet.IsSpectating)
        .Add("spectatorCarIndex", packet.SpectatorCarIndex)
        .Add("sliProNativeSupport", packet.IsSliProNativeSupportActive)
        .Add("marshalZones", MarshalZones(packet))
        .Add("safetyCarStatus", (int)packet.SafetyCarStatus)
        .Add("networkGame", packet.IsNetworkGame)
        .Add("forecastAccuracy", (int)packet.ForecastAccuracy)
        .Add("weatherForecast", Forecast(packet))
        .Add("aiDifficulty", packet.AIDifficulty)
        .Add("pitStopWindowIdealLap", packet.PitStopWindowIdealLap)
        .Add("pitStopWindowLatestLap", packet.PitStopWindowLatestLap)
        .Add("pitStopRejoinPosition", packet.PitStopRejoinPosition)
        .Add("steeringAssist", packet.IsSteeringAssistOn)
        .Add("brakingAssist", (int)packet.BrakingAssist)
        .Add("gearboxAssist", (int)packet.GearboxAssist)
        .Add("pitAssist", packet.PitAssist)
        .Add("pitReleaseAssist", packet.PitReleaseAssist)
        .Add("ersAssist", packet.ERSAssist)
        .Add("drsAssist", packet.DRSAssist)
        .Add("dynamicRacingLine", (int)packet.DynamicRacingLine)
        .Add("dynamicRacingLineType", (int)packet.DynamicRacingLineType)
        .Add("gameMode", (int)packet.GameMode)
        .Add("ruleSet", (int)packet.RuleSet)
        .Add("timeOfDayMin", packet.TimeOfDay)
        .Add("sessionLength", (int)packet.SessionLength)
        .Add("speedUnits", (int)packet.SpeedUnitsLeadPlayer)
        .Add("temperatureUnits", (int)packet.TemperatureUnitsLeadPlayer)
        .Add("numSafetyCarPeriods", packet.NumSafetyCarPeriods)
        .Add("numVirtualSafetyCarPeriods", packet.NumVirtualSafetyCarPeriods)
        .Add("numRedFlagPeriods", packet.NumRedFlagPeriods)
        .Add("equalCarPerformance", packet.IsEqualCarPerformance)
        .Add("recoveryMode", (int)packet.RecoveryMode)
        .Add("flashbackLimit", (int)packet.FlashbackLimit)
        .Add("surfaceType", (int)packet.SurfaceTypeSettings)
        .Add("lowFuelMode", (int)packet.LowFuelMode)
        .Add("raceStarts", (int)packet.RaceStarts)
        .Add("tyreTemperature", (int)packet.TyreTemperature)
        .Add("pitLaneTyreSim", packet.PitLaneTyreSimEnabled)
        .Add("carDamage", (int)packet.CarDamage)
        .Add("carDamageRate", (int)packet.CarDamageRate)
        .Add("collisions", (int)packet.Collisions)
        .Add("collisionsOffForFirstLapOnly", packet.IsCollisionsOffForFirstLapOnlyEnabled)
        .Add("unsafePitRelease", packet.UnsafePitReleaseEnabled)
        .Add("collisionsOffForGriefing", packet.OffForGriefing)
        .Add("cornerCuttingStringency", (int)packet.CornerCuttingStringency)
        .Add("parcFermeRules", packet.ParcFermeRules)
        .Add("pitStopExperience", (int)packet.PitStopExperience)
        .Add("safetyCar", (int)packet.SafetyCarSetting)
        .Add("safetyCarExperience", (int)packet.SafetyCarExperience)
        .Add("formationLap", packet.FormationLap)
        .Add("formationLapExperience", (int)packet.FormationLapExperience)
        .Add("redFlags", (int)packet.RedFlags)
        .Add("affectsLicenceLevelSolo", packet.AffectsLicenseLevelSolo)
        .Add("affectsLicenceLevelMp", packet.AffectsLicenseLevelMP)
        .Add("weekendStructure", WeekendStructure(packet))
        .Add("sector2LapDistanceStart", packet.Sector2LapDistanceStart)
        .Add("sector3LapDistanceStart", packet.Sector3LapDistanceStart)
        .Build();

    private static object?[] MarshalZones(SessionDataPacket packet)
    {
        var zones = packet.MarshalZones.AsReadOnlySpan();
        var count = Math.Min((int)packet.NumMarshalZones, zones.Length);
        var mapped = new object?[count];
        for (var i = 0; i < count; i++)
        {
            mapped[i] = new DetailBag().Add("zoneStart", zones[i].ZoneStart).Add("zoneFlag", (int)zones[i].ZoneFlag).Build();
        }

        return mapped;
    }

    private static object?[] Forecast(SessionDataPacket packet)
    {
        var samples = packet.WeatherForecastSamples.AsReadOnlySpan();
        var count = Math.Min((int)packet.NumWeatherForecastSamples, samples.Length);
        var mapped = new object?[count];
        for (var i = 0; i < count; i++)
        {
            mapped[i] = FromForecastSample(samples[i]);
        }

        return mapped;
    }

    private static IReadOnlyDictionary<string, object?> FromForecastSample(WeatherForecastSample sample) => new DetailBag()
        .Add("sessionType", (int)sample.SessionType)
        .Add("timeOffsetMin", sample.TimeOffset)
        .Add("weather", (int)sample.Weather)
        .Add("trackTemperature", sample.TrackTemperature)
        .Add("trackTemperatureChange", (int)sample.TrackTemperatureChange)
        .Add("airTemperature", sample.AirTemperature)
        .Add("airTemperatureChange", (int)sample.AirTemperatureChange)
        .Add("rainPercentage", sample.RainPercentage)
        .Build();

    private static object?[] WeekendStructure(SessionDataPacket packet)
    {
        var sessions = packet.WeekendStructure.AsReadOnlySpan();
        var count = Math.Min((int)packet.NumSessionsInWeekend, sessions.Length);
        var mapped = new object?[count];
        for (var i = 0; i < count; i++)
        {
            mapped[i] = (int)sessions[i];
        }

        return mapped;
    }
}
