using System.Buffers.Binary;
using F1Game.UDP;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using F1Enums = F1Game.UDP.Enums;
using CoreSessionType = SimCenter.Agent.Core.Telemetry.SessionType;

namespace SimCenter.Agent.Infrastructure.Tests;

/// <summary>
/// 실제 F1 25 게임(v1.26, m_packetFormat 2025)이 보낸 바이트로 F1Game.UDP 버전이 게임의 UDP 레이아웃과 맞는지 확인한다(D-20, D-41).
/// 26.0.0(2026 시즌팩 레이아웃, 24대)은 이 패킷들을 "바이트 부족"으로 거부해 랩이 하나도 저장되지 않았다.
/// 구조체를 직접 만드는 <see cref="F1PacketMapperTests"/>는 바이트 레이아웃을 거치지 않아 이 문제를 잡지 못한다.
/// </summary>
public class F1WireLayoutTests
{
    private const int Format = 2025;
    private const int PacketIdOffset = 6;
    private const int PlayerCarIndexOffset = 27; // 헤더 29바이트의 끝에서 두 번째(m_playerCarIndex)
    private const string FixtureFolder = "Fixtures/F1_25";

    private static F1PacketMapper Mapper(ILogger<F1PacketMapper>? logger = null) =>
        new(Format, logger ?? NullLogger<F1PacketMapper>.Instance);

    private static byte[] ReadFixture(string name) =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, FixtureFolder, name));

    [Fact]
    public void Map_RealSessionDatagram_ProducesSessionFrame()
    {
        var frames = Mapper().Map(ReadFixture("session.bin"));

        var session = Assert.Single(frames.OfType<SessionFrame>());
        Assert.Equal((int)F1Enums.Track.Texas, session.TrackId);
        Assert.Equal(CoreSessionType.TimeTrial, session.SessionType);
        Assert.Equal(Format, session.PacketFormat);
    }

    [Fact]
    public void Map_RealLapDataDatagram_ProducesPlayerLapFrame()
    {
        var frames = Mapper().Map(ReadFixture("lapdata.bin"));

        var lap = Assert.Single(frames.OfType<LapFrame>());
        Assert.Equal(2, lap.CurrentLapNumber);
        Assert.Equal(99_191, lap.LastLapTimeMs); // 1:39.191 — 캡처 직전에 끝낸 랩
    }

    /// <summary>
    /// F1 25 UDP 스펙의 패킷 크기. Event·Participants·FinalClassification·LobbyInfo를 뺀 12종은 실제 게임 캡처와 같다.
    /// 라이브러리를 올렸을 때 레이아웃이 바뀌면 여기서 먼저 실패한다.
    /// </summary>
    [Theory]
    [InlineData(F1Enums.PacketType.Motion, 1349)]
    [InlineData(F1Enums.PacketType.Session, 753)]
    [InlineData(F1Enums.PacketType.LapData, 1285)]
    [InlineData(F1Enums.PacketType.Event, 45)]
    [InlineData(F1Enums.PacketType.Participants, 1284)]
    [InlineData(F1Enums.PacketType.CarSetups, 1133)]
    [InlineData(F1Enums.PacketType.CarTelemetry, 1352)]
    [InlineData(F1Enums.PacketType.CarStatus, 1239)]
    [InlineData(F1Enums.PacketType.FinalClassification, 1042)]
    [InlineData(F1Enums.PacketType.LobbyInfo, 954)]
    [InlineData(F1Enums.PacketType.CarDamage, 1041)]
    [InlineData(F1Enums.PacketType.SessionHistory, 1460)]
    [InlineData(F1Enums.PacketType.TyreSets, 231)]
    [InlineData(F1Enums.PacketType.MotionEx, 273)]
    [InlineData(F1Enums.PacketType.TimeTrial, 101)]
    [InlineData(F1Enums.PacketType.LapPositions, 1131)]
    public void PacketReader_ParsesF125SpecSize(F1Enums.PacketType packetType, int size)
    {
        var datagram = new byte[size];
        BinaryPrimitives.WriteUInt16LittleEndian(datagram, Format);
        datagram[PacketIdOffset] = (byte)packetType;

        var packet = PacketReader.ToPacket(datagram);

        Assert.Equal(packetType, packet.PacketType);
    }

    [Fact]
    public void Map_UnparsableDatagram_WarnsOncePerPacketType()
    {
        var logger = new CapturingLogger<F1PacketMapper>();
        var sut = Mapper(logger);
        var lap = ReadFixture("lapdata.bin");
        var session = ReadFixture("session.bin");

        Assert.Empty(sut.Map(lap.AsSpan(0, lap.Length - 1)));
        Assert.Empty(sut.Map(lap.AsSpan(0, lap.Length - 1)));
        Assert.Empty(sut.Map(session.AsSpan(0, session.Length - 1)));

        var warnings = Warnings(logger);
        Assert.Equal(2, warnings.Count);
        Assert.Contains(warnings, message => message.Contains("packetId=2"));
        Assert.Contains(warnings, message => message.Contains("packetId=1"));
    }

    [Fact]
    public void Map_OtherPacketFormat_WarnsOncePerFormat()
    {
        var logger = new CapturingLogger<F1PacketMapper>();
        var sut = Mapper(logger);
        var session = ReadFixture("session.bin");
        BinaryPrimitives.WriteUInt16LittleEndian(session, 2024);

        Assert.Empty(sut.Map(session));
        Assert.Empty(sut.Map(session));

        var warning = Assert.Single(Warnings(logger));
        Assert.Contains("2024", warning);
    }

    [Fact]
    public void Map_PlayerIndexBeyondSlots_WarnsOnce()
    {
        var logger = new CapturingLogger<F1PacketMapper>();
        var sut = Mapper(logger);
        var lap = ReadFixture("lapdata.bin");
        lap[PlayerCarIndexOffset] = byte.MaxValue; // 관전 등으로 플레이어 차가 없을 때 게임이 보내는 값

        // 플레이어 칸은 버리고 모든 차 랩 상태(트랙 형상 표본용)만 낸다.
        Assert.IsType<FieldLapStatesFrame>(Assert.Single(sut.Map(lap)));
        Assert.IsType<FieldLapStatesFrame>(Assert.Single(sut.Map(lap)));

        Assert.Single(Warnings(logger));
    }

    // ---- 랩 상세(docs/15 §3.1): 실제 캡처의 새 필드 + Car Telemetry·Status·Damage 바이트 레이아웃 ----

    private const int HeaderSize = 29;
    private const int CarTelemetrySize = 60;   // F1 25 CarTelemetryData 1대
    private const int CarStatusSize = 55;      // F1 25 CarStatusData 1대
    private const int CarDamageSize = 46;      // F1 25 CarDamageData 1대
    private const byte WirePlayerIndex = 2;

    [Fact]
    public void Map_RealSessionDatagram_ProducesConditions()
    {
        var session = Assert.Single(Mapper().Map(ReadFixture("session.bin")).OfType<SessionFrame>());

        Assert.Equal(Weather.Clear, session.Weather);
        Assert.Equal(27, session.AirTemperatureC);
        Assert.Equal(40, session.TrackTemperatureC);
        Assert.Equal(5514, session.TrackLengthM);   // COTA
        Assert.Null(session.RainForecastPercent);   // Time Trial 캡처에는 예보 샘플이 없다
    }

    [Fact]
    public void Map_RealLapDataDatagram_ProducesDistanceAndCurrentLapTime()
    {
        var lap = Assert.Single(Mapper().Map(ReadFixture("lapdata.bin")).OfType<LapFrame>());

        // 랩 번호가 막 바뀐 순간의 캡처 — 시간은 0으로 돌아갔지만 거리는 아직 앞 랩 값이다(트레이스는 칸 덮어쓰기로 견딘다).
        Assert.Equal(5054.4614f, lap.LapDistanceM, precision: 3);
        Assert.Equal(0, lap.CurrentLapTimeMs);
    }

    /// <summary>F1 UDP의 바퀴 배열 순서는 RL·RR·FL·FR이다 — 바이트에 순서대로 다른 값을 넣고 이름으로 옮겨졌는지 본다.</summary>
    [Fact]
    public void Map_CarDamageBytes_MapsWheelOrderRearLeftRearRightFrontLeftFrontRight()
    {
        var datagram = Datagram(F1Enums.PacketType.CarDamage, 1041);
        var car = HeaderSize + (WirePlayerIndex * CarDamageSize);
        WriteFloats(datagram, car, 1.5f, 2.5f, 3.5f, 4.5f);              // m_tyresWear[RL, RR, FL, FR]
        WriteBytes(datagram, car + 16, 11, 12, 13, 14);                  // m_tyresDamage
        WriteBytes(datagram, car + 20, 21, 22, 23, 24);                  // m_brakesDamage
        WriteBytes(datagram, car + 28, 31, 32, 33, 34, 35, 36);          // 앞날개 L·R, 뒷날개, 플로어, 디퓨저, 사이드포드
        WriteBytes(datagram, car + 36, 37, 38);                          // 기어박스, 엔진

        var frame = Assert.Single(Mapper().Map(datagram).OfType<CarDamageFrame>());

        Assert.Equal(new WheelSet<float>(FrontLeft: 3.5f, FrontRight: 4.5f, RearLeft: 1.5f, RearRight: 2.5f), frame.TyreWearPercent);
        Assert.Equal(new WheelSet<int>(FrontLeft: 13, FrontRight: 14, RearLeft: 11, RearRight: 12), frame.TyreDamagePercent);
        Assert.Equal(new WheelSet<int>(FrontLeft: 23, FrontRight: 24, RearLeft: 21, RearRight: 22), frame.BrakeDamagePercent);
        Assert.Equal(
            new[] { 31, 32, 33, 34, 35, 36, 37, 38 },
            new[]
            {
                frame.FrontLeftWingDamage, frame.FrontRightWingDamage, frame.RearWingDamage, frame.FloorDamage,
                frame.DiffuserDamage, frame.SidepodDamage, frame.GearboxDamage, frame.EngineDamage,
            });
    }

    [Fact]
    public void Map_CarTelemetryBytes_MapsPlayerCar()
    {
        var datagram = Datagram(F1Enums.PacketType.CarTelemetry, 1352);
        var car = HeaderSize + (WirePlayerIndex * CarTelemetrySize);
        BinaryPrimitives.WriteUInt16LittleEndian(datagram.AsSpan(car), 287);         // m_speed
        WriteFloats(datagram, car + 2, 0.75f, -0.25f, 0.5f);                          // m_throttle, m_steer, m_brake
        datagram[car + 15] = unchecked((byte)(sbyte)-1);                              // m_gear(R)
        BinaryPrimitives.WriteUInt16LittleEndian(datagram.AsSpan(car + 16), 11_850);  // m_engineRPM

        var frame = Assert.Single(Mapper().Map(datagram).OfType<CarTelemetryFrame>());

        Assert.Equal(new CarTelemetryFrame("0", 287, 0.75f, 0.5f, -0.25f, -1, 11_850), frame);
    }

    [Fact]
    public void Map_CarStatusBytes_MapsPlayerCar()
    {
        var datagram = Datagram(F1Enums.PacketType.CarStatus, 1239);
        var car = HeaderSize + (WirePlayerIndex * CarStatusSize);
        WriteFloats(datagram, car + 5, 24.5f);                         // m_fuelInTank
        WriteFloats(datagram, car + 13, 13.25f);                       // m_fuelRemainingLaps
        WriteBytes(datagram, car + 25, 18, 16, 3);                     // m_actualTyreCompound, m_visualTyreCompound, m_tyresAgeLaps
        WriteFloats(datagram, car + 37, 1_494_000f);                   // m_ersStoreEnergy
        WriteFloats(datagram, car + 42, 1_000_000f, 600_000f, 2_100_000f);   // 이 랩 회수(MGU-K, MGU-H)·배포

        var frame = Assert.Single(Mapper().Map(datagram).OfType<CarStatusFrame>());

        Assert.Equal(new CarStatusFrame("0", 24.5f, 13.25f, 1_494_000f, 2_100_000f, 1_000_000f, 600_000f, 18, 16, 3), frame);
    }

    [Fact]
    public void Map_PlayerIndexBeyondSlots_WarnsOnceAcrossCarPackets()
    {
        var logger = new CapturingLogger<F1PacketMapper>();
        var sut = Mapper(logger);
        var lap = ReadFixture("lapdata.bin");
        lap[PlayerCarIndexOffset] = byte.MaxValue;
        var telemetry = Datagram(F1Enums.PacketType.CarTelemetry, 1352, playerIndex: byte.MaxValue);
        var status = Datagram(F1Enums.PacketType.CarStatus, 1239, playerIndex: byte.MaxValue);
        var damage = Datagram(F1Enums.PacketType.CarDamage, 1041, playerIndex: byte.MaxValue);

        Assert.IsType<FieldSurfacesFrame>(Assert.Single(sut.Map(telemetry)));
        Assert.Empty(sut.Map(status));
        Assert.IsType<FieldDamageFrame>(Assert.Single(sut.Map(damage)));
        Assert.IsType<FieldLapStatesFrame>(Assert.Single(sut.Map(lap)));

        Assert.Single(Warnings(logger));   // 관전 중이면 모든 차 패킷이 같은 이유로 버려진다 — 한 번만 알린다
    }

    private static byte[] Datagram(F1Enums.PacketType packetType, int size, byte playerIndex = WirePlayerIndex)
    {
        var datagram = new byte[size];
        BinaryPrimitives.WriteUInt16LittleEndian(datagram, Format);
        datagram[PacketIdOffset] = (byte)packetType;
        datagram[PlayerCarIndexOffset] = playerIndex;
        return datagram;
    }

    private static void WriteFloats(byte[] datagram, int offset, params float[] values)
    {
        for (var i = 0; i < values.Length; i++)
        {
            BinaryPrimitives.WriteSingleLittleEndian(datagram.AsSpan(offset + (i * sizeof(float))), values[i]);
        }
    }

    private static void WriteBytes(byte[] datagram, int offset, params byte[] values) => values.CopyTo(datagram, offset);

    private static List<string> Warnings(CapturingLogger<F1PacketMapper> logger) =>
        logger.Entries.Where(entry => entry.Level == LogLevel.Warning).Select(entry => entry.Message).ToList();

    private sealed class CapturingLogger<T> : ILogger<T>
    {
        public List<(LogLevel Level, string Message)> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Entries.Add((logLevel, formatter(state, exception)));
    }
}
