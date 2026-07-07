using F1Game.UDP.Data;
using F1Game.UDP.Events;
using F1Game.UDP.Packets;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using F1Enums = F1Game.UDP.Enums;
using CoreSessionType = SimCenter.Agent.Core.Telemetry.SessionType;

namespace SimCenter.Agent.Infrastructure.Tests;

public class F1PacketMapperTests
{
    private const int Format = 2025;
    private readonly F1PacketMapper _sut = new(expectedPacketFormat: Format);

    private static PacketHeader Header(ulong uid = 1001, byte playerIndex = 0) =>
        new() { PacketFormat = Format, SessionUID = uid, PlayerCarIndex = playerIndex };

    [Fact]
    public void MapSession_MapsTrackAndSessionType()
    {
        var packet = new SessionDataPacket
        {
            Header = Header(),
            Track = F1Enums.Track.Silverstone,
            SessionType = F1Enums.SessionType.TimeTrial,
        };

        var frame = _sut.MapSession(packet);

        Assert.Equal("1001", frame.SessionRef);
        Assert.Equal(7, frame.TrackId); // Silverstone = 7 (Codemasters 표준)
        Assert.Equal(CoreSessionType.TimeTrial, frame.SessionType);
        Assert.Equal(Format, frame.PacketFormat);
    }

    [Theory]
    [InlineData(F1Enums.SessionType.TimeTrial, CoreSessionType.TimeTrial)]
    [InlineData(F1Enums.SessionType.Practice1, CoreSessionType.Practice)]
    [InlineData(F1Enums.SessionType.ShortPractice, CoreSessionType.Practice)]
    [InlineData(F1Enums.SessionType.Qualifying3, CoreSessionType.Qualifying)]
    [InlineData(F1Enums.SessionType.OneShotQualifying, CoreSessionType.Qualifying)]
    [InlineData(F1Enums.SessionType.SprintShootout1, CoreSessionType.Qualifying)]
    [InlineData(F1Enums.SessionType.Race, CoreSessionType.Race)]
    [InlineData(F1Enums.SessionType.Race3, CoreSessionType.Race)]
    [InlineData(F1Enums.SessionType.Unknown, CoreSessionType.Unknown)]
    public void MapSession_NormalizesSessionType(F1Enums.SessionType input, CoreSessionType expected)
    {
        var packet = new SessionDataPacket { Header = Header(), Track = F1Enums.Track.Monza, SessionType = input };

        Assert.Equal(expected, _sut.MapSession(packet).SessionType);
    }

    [Fact]
    public void MapLap_CombinesMinutesAndMs_AndFlags()
    {
        var lap = new LapData
        {
            CurrentLapNum = 3,
            Sector = F1Enums.Sector.Second,
            Sector1TimeInMinutes = 1,
            Sector1TimeInMS = 2000,   // → 62000
            Sector2TimeInMinutes = 0,
            Sector2TimeInMS = 30110,
            LastLapTimeInMS = 83452,
            IsCurrentLapInvalid = true,
            DriverStatus = F1Enums.DriverStatus.OutLap,
            PitStatus = F1Enums.PitStatus.None,
        };

        var frame = _sut.MapLap(lap, Header(uid: 1001, playerIndex: 0));

        Assert.Equal("1001", frame.SessionRef);
        Assert.Equal(3, frame.CurrentLapNumber);
        Assert.Equal(1, frame.CurrentSector); // Second
        Assert.Equal(62000, frame.Sector1TimeMs);
        Assert.Equal(30110, frame.Sector2TimeMs);
        Assert.Equal(83452, frame.LastLapTimeMs);
        Assert.True(frame.IsCurrentLapInvalid);
        Assert.True(frame.IsOutOrInLap); // OutLap
    }

    [Fact]
    public void MapLap_PitStatus_MarksOutOrInLap()
    {
        var lap = new LapData { DriverStatus = F1Enums.DriverStatus.OnTrack, PitStatus = F1Enums.PitStatus.Pitting };

        Assert.True(_sut.MapLap(lap, Header()).IsOutOrInLap);
    }

    [Fact]
    public void MapLap_NormalFlyingLap_NotOutOrInLap()
    {
        var lap = new LapData { DriverStatus = F1Enums.DriverStatus.FlyingLap, PitStatus = F1Enums.PitStatus.None };

        Assert.False(_sut.MapLap(lap, Header()).IsOutOrInLap);
    }

    [Fact]
    public void MapEvent_SessionStartAndEnd_MapToMarkers()
    {
        var start = new EventDataPacket { Header = Header(), EventDetails = new EventDetails { EventType = EventType.SessionStarted } };
        var end = new EventDataPacket { Header = Header(), EventDetails = new EventDetails { EventType = EventType.SessionEnded } };

        Assert.Equal(SessionBoundary.Start, _sut.MapEvent(start)!.Kind);
        Assert.Equal(SessionBoundary.End, _sut.MapEvent(end)!.Kind);
    }

    [Fact]
    public void MapEvent_UnrelatedEvent_ReturnsNull()
    {
        var fastest = new EventDataPacket { Header = Header(), EventDetails = new EventDetails { EventType = EventType.FastestLap } };

        Assert.Null(_sut.MapEvent(fastest));
    }

    [Fact]
    public void Map_WrongPacketFormat_ReturnsEmpty()
    {
        var packet = new UnionPacket { Header = new PacketHeader { PacketFormat = 1234 } };

        Assert.Empty(_sut.Map(packet));
    }
}
