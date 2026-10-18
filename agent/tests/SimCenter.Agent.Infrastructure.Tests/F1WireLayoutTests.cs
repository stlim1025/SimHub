using System.Buffers.Binary;
using F1Game.UDP;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
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

        var session = Assert.IsType<SessionFrame>(Assert.Single(frames));
        Assert.Equal((int)F1Enums.Track.Texas, session.TrackId);
        Assert.Equal(CoreSessionType.TimeTrial, session.SessionType);
        Assert.Equal(Format, session.PacketFormat);
    }

    [Fact]
    public void Map_RealLapDataDatagram_ProducesPlayerLapFrame()
    {
        var frames = Mapper().Map(ReadFixture("lapdata.bin"));

        var lap = Assert.IsType<LapFrame>(Assert.Single(frames));
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

        Assert.Empty(sut.Map(lap));
        Assert.Empty(sut.Map(lap));

        Assert.Single(Warnings(logger));
    }

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
