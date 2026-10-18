using F1Game.UDP.Data;
using F1Game.UDP.Packets;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Tests;

/// <summary>
/// 랩 상세용으로 새로 읽는 필드(docs/15 §3.1): Session 날씨·기온·비 예보, Lap Data 거리·시간, Car Telemetry·Status·Damage(플레이어 차).
/// 바퀴 4개 값은 라이브러리의 이름(RL·RR·FL·FR 순서 구조체)에서 이름으로 옮긴다 — 바이트 순서는 <see cref="F1WireLayoutTests"/>가 고정한다.
/// </summary>
public class F1PacketMapperCarStateTests
{
    private const int Format = 2025;
    private const int CarSlotCount = 22;
    private const int ForecastSlotCount = 64;
    private const byte PlayerIndex = 3;

    private readonly F1PacketMapper _sut = new(expectedPacketFormat: Format, NullLogger<F1PacketMapper>.Instance);

    private static PacketHeader Header(ulong uid = 1001, byte playerIndex = PlayerIndex) =>
        new() { PacketFormat = Format, SessionUID = uid, PlayerCarIndex = playerIndex };

    private static T[] Slots<T>(int count, int index, T value)
    {
        var array = new T[count];
        array[index] = value;
        return array;
    }

    private static Tyres<T> RlRrFlFr<T>(T rearLeft, T rearRight, T frontLeft, T frontRight) =>
        new() { RearLeft = rearLeft, RearRight = rearRight, FrontLeft = frontLeft, FrontRight = frontRight };

    // ---- Session: 날씨·기온·트랙 길이·비 예보 ----

    [Fact]
    public void MapSession_MapsConditions()
    {
        var packet = new SessionDataPacket
        {
            Header = Header(),
            SessionType = F1Enums.SessionType.Race,
            Weather = F1Enums.Weather.LightRain,
            AirTemperature = -3,
            TrackTemperature = 31,
            TrackLength = 7004,
        };

        var frame = _sut.MapSession(packet);

        Assert.Equal(Weather.LightRain, frame.Weather);
        Assert.Equal(-3, frame.AirTemperatureC);
        Assert.Equal(31, frame.TrackTemperatureC);
        Assert.Equal(7004, frame.TrackLengthM);
    }

    [Theory]
    [InlineData(F1Enums.Weather.Clear, Weather.Clear)]
    [InlineData(F1Enums.Weather.LightCloud, Weather.LightCloud)]
    [InlineData(F1Enums.Weather.Overcast, Weather.Overcast)]
    [InlineData(F1Enums.Weather.LightRain, Weather.LightRain)]
    [InlineData(F1Enums.Weather.HeavyRain, Weather.HeavyRain)]
    [InlineData(F1Enums.Weather.Storm, Weather.Storm)]
    public void MapSession_MapsEveryWeather(F1Enums.Weather input, Weather expected)
    {
        var frame = _sut.MapSession(new SessionDataPacket { Header = Header(), Weather = input });

        Assert.Equal(expected, frame.Weather);
    }

    [Fact]
    public void MapSession_UnknownWeather_IsNull()
    {
        var frame = _sut.MapSession(new SessionDataPacket { Header = Header(), Weather = (F1Enums.Weather)9 });

        Assert.Null(frame.Weather);
    }

    private static WeatherForecastSample Forecast(F1Enums.SessionType type, byte offsetMinutes, byte rain) =>
        new() { SessionType = type, TimeOffset = offsetMinutes, RainPercentage = rain };

    private static SessionDataPacket WithForecast(F1Enums.SessionType sessionType, params WeatherForecastSample[] samples)
    {
        var slots = new WeatherForecastSample[ForecastSlotCount];
        samples.CopyTo(slots, 0);
        return new SessionDataPacket
        {
            Header = Header(),
            SessionType = sessionType,
            NumWeatherForecastSamples = (byte)samples.Length,
            WeatherForecastSamples = slots,
        };
    }

    [Fact]
    public void MapSession_RainForecast_IsEarliestFutureSampleOfThisSessionType()
    {
        var packet = WithForecast(
            F1Enums.SessionType.Race,
            Forecast(F1Enums.SessionType.Qualifying3, 5, 90),   // 다른 세션 종류
            Forecast(F1Enums.SessionType.Race, 0, 10),          // 지금(offset 0)
            Forecast(F1Enums.SessionType.Race, 15, 40),
            Forecast(F1Enums.SessionType.Race, 5, 20));          // offset > 0 중 가장 이른 것

        Assert.Equal(20, _sut.MapSession(packet).RainForecastPercent);
    }

    [Fact]
    public void MapSession_RainForecast_FallsBackToFirstSampleOfThisSessionType()
    {
        var packet = WithForecast(
            F1Enums.SessionType.TimeTrial,
            Forecast(F1Enums.SessionType.Race, 5, 90),
            Forecast(F1Enums.SessionType.TimeTrial, 0, 7));

        Assert.Equal(7, _sut.MapSession(packet).RainForecastPercent);
    }

    [Fact]
    public void MapSession_RainForecast_NoSampleOfThisSessionType_IsNull()
    {
        var packet = WithForecast(F1Enums.SessionType.TimeTrial, Forecast(F1Enums.SessionType.Race, 5, 90));

        Assert.Null(_sut.MapSession(packet).RainForecastPercent);
    }

    [Fact]
    public void MapSession_RainForecast_IgnoresSlotsBeyondSampleCount()
    {
        var slots = new WeatherForecastSample[ForecastSlotCount];
        slots[0] = Forecast(F1Enums.SessionType.Race, 0, 10);
        slots[1] = Forecast(F1Enums.SessionType.Race, 5, 80);   // 개수(1) 밖 — 쓰레기 칸
        var packet = new SessionDataPacket
        {
            Header = Header(),
            SessionType = F1Enums.SessionType.Race,
            NumWeatherForecastSamples = 1,
            WeatherForecastSamples = slots,
        };

        Assert.Equal(10, _sut.MapSession(packet).RainForecastPercent);
    }

    // ---- Lap Data: 랩 거리·현재 랩 시간 ----

    [Fact]
    public void MapLap_MapsDistanceAndCurrentLapTime()
    {
        var lap = new LapData { CurrentLapNum = 2, LapDistance = 1234.5f, CurrentLapTimeInMS = 45_678 };

        var frame = _sut.MapLap(lap, Header());

        Assert.Equal(1234.5f, frame.LapDistanceM);
        Assert.Equal(45_678, frame.CurrentLapTimeMs);
    }

    [Fact]
    public void MapLap_NegativeDistanceBeforeStartLine_IsKept()
    {
        // 출발선 전 음수 거리는 트레이스 쪽에서 버린다(Core) — 매퍼는 그대로 옮긴다.
        var frame = _sut.MapLap(new LapData { LapDistance = -42.25f }, Header());

        Assert.Equal(-42.25f, frame.LapDistanceM);
    }

    // ---- Car Telemetry / Status / Damage (플레이어 차) ----

    [Fact]
    public void Map_CarTelemetry_MapsPlayerCar()
    {
        var car = new CarTelemetryData { Speed = 312, Throttle = 0.75f, Brake = 0.1f, Steer = -0.25f, Gear = 7, EngineRPM = 11_850 };
        var packet = new CarTelemetryDataPacket { Header = Header(uid: 77), CarTelemetryData = Slots(CarSlotCount, PlayerIndex, car) };

        var frame = Assert.IsType<CarTelemetryFrame>(Assert.Single(_sut.Map(packet)));

        Assert.Equal(new CarTelemetryFrame("77", 312, 0.75f, 0.1f, -0.25f, 7, 11_850), frame);
    }

    [Fact]
    public void Map_CarTelemetry_ReverseGear_IsMinusOne()
    {
        var car = new CarTelemetryData { Gear = -1 };
        var packet = new CarTelemetryDataPacket { Header = Header(), CarTelemetryData = Slots(CarSlotCount, PlayerIndex, car) };

        var frame = Assert.IsType<CarTelemetryFrame>(Assert.Single(_sut.Map(packet)));

        Assert.Equal(-1, frame.Gear);
    }

    [Fact]
    public void Map_CarStatus_MapsPlayerCar()
    {
        var car = new CarStatusData
        {
            FuelInTank = 24.4f,
            FuelRemainingLaps = 13.1f,
            ErsStoreEnergy = 1_494_000f,
            ErsDeployedThisLap = 2_100_000f,
            ErsHarvestedThisLapMGUK = 1_000_000f,
            ErsHarvestedThisLapMGUH = 600_000f,
            ActualTyreCompound = F1Enums.ActualCompound.F1C3,
            VisualTyreCompound = F1Enums.VisualCompound.F1Soft,
            TyresAgeLaps = 3,
        };
        var packet = new CarStatusDataPacket { Header = Header(uid: 77), CarStatusData = Slots(CarSlotCount, PlayerIndex, car) };

        var frame = Assert.IsType<CarStatusFrame>(Assert.Single(_sut.Map(packet)));

        Assert.Equal(new CarStatusFrame("77", 24.4f, 13.1f, 1_494_000f, 2_100_000f, 1_000_000f, 600_000f, 18, 16, 3), frame);
    }

    [Fact]
    public void Map_CarDamage_MapsWheelsByName()
    {
        var car = new CarDamageData
        {
            TyresWear = RlRrFlFr(20.5f, 14.25f, 27f, 14f),             // RL, RR, FL, FR
            TyresDamage = RlRrFlFr<byte>(3, 4, 1, 2),
            BrakesDamage = RlRrFlFr<byte>(7, 8, 5, 6),
            FrontLeftWingDamage = 10,
            FrontRightWingDamage = 11,
            RearWingDamage = 12,
            FloorDamage = 13,
            DiffuserDamage = 14,
            SidepodDamage = 15,
            GearBoxDamage = 16,
            EngineDamage = 17,
        };
        var packet = new CarDamageDataPacket { Header = Header(uid: 77), CarDamageData = Slots(CarSlotCount, PlayerIndex, car) };

        var frame = Assert.IsType<CarDamageFrame>(Assert.Single(_sut.Map(packet)));

        Assert.Equal(new WheelSet<float>(FrontLeft: 27f, FrontRight: 14f, RearLeft: 20.5f, RearRight: 14.25f), frame.TyreWearPercent);
        Assert.Equal(new WheelSet<int>(FrontLeft: 1, FrontRight: 2, RearLeft: 3, RearRight: 4), frame.TyreDamagePercent);
        Assert.Equal(new WheelSet<int>(FrontLeft: 5, FrontRight: 6, RearLeft: 7, RearRight: 8), frame.BrakeDamagePercent);
        Assert.Equal("77", frame.SessionRef);
        Assert.Equal(10, frame.FrontLeftWingDamage);
        Assert.Equal(11, frame.FrontRightWingDamage);
        Assert.Equal(12, frame.RearWingDamage);
        Assert.Equal(13, frame.FloorDamage);
        Assert.Equal(14, frame.DiffuserDamage);
        Assert.Equal(15, frame.SidepodDamage);
        Assert.Equal(16, frame.GearboxDamage);
        Assert.Equal(17, frame.EngineDamage);
    }

    [Fact]
    public void Map_CarPackets_PlayerIndexBeyondSlots_ReturnsEmpty()
    {
        var header = Header(playerIndex: byte.MaxValue);   // 관전 중
        var telemetry = new CarTelemetryDataPacket { Header = header, CarTelemetryData = new CarTelemetryData[CarSlotCount] };
        var status = new CarStatusDataPacket { Header = header, CarStatusData = new CarStatusData[CarSlotCount] };
        var damage = new CarDamageDataPacket { Header = header, CarDamageData = new CarDamageData[CarSlotCount] };

        Assert.Empty(_sut.Map(telemetry));
        Assert.Empty(_sut.Map(status));
        Assert.Empty(_sut.Map(damage));
    }

    [Fact]
    public void Map_CarPacketWithWrongFormat_ReturnsEmpty()
    {
        var packet = new CarTelemetryDataPacket
        {
            Header = new PacketHeader { PacketFormat = 1234 },
            CarTelemetryData = new CarTelemetryData[CarSlotCount],
        };

        Assert.Empty(_sut.Map(packet));
    }

    [Fact]
    public void MapParticipants_CarriesPlayerCarIndex()
    {
        var packet = new ParticipantsDataPacket { Header = Header(playerIndex: 5), Participants = new ParticipantData[CarSlotCount] };

        Assert.Equal(5, _sut.MapParticipants(packet).PlayerCarIndex);
    }
}
