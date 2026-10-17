using F1Game.UDP.Data;
using F1Game.UDP.Events;
using F1Game.UDP.Packets;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using F1Enums = F1Game.UDP.Enums;
using CoreGameMode = SimCenter.Agent.Core.Telemetry.GameMode;
using CoreResultStatus = SimCenter.Agent.Core.Telemetry.ResultStatus;
using CoreSessionType = SimCenter.Agent.Core.Telemetry.SessionType;
using CoreTyreCompound = SimCenter.Agent.Core.Telemetry.TyreCompound;

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

    // ---- P7: Session 맥락 · Participants · Final Classification ----

    private const int CarSlotCount = 24;
    private const int TyreStintSlotCount = 8;

    // 라이브러리의 Array24/Array8은 T[]에서 암시 변환된다 — 칸 수를 맞춘 배열을 만들어 준다.
    private static T[] Slots<T>(int count, params (int Index, T Value)[] filled)
    {
        var array = new T[count];
        foreach (var (index, value) in filled)
        {
            array[index] = value;
        }

        return array;
    }

    private static T[] Stints<T>(params T[] values) =>
        Slots(TyreStintSlotCount, values.Select((value, index) => (index, value)).ToArray());

    private static FinalClassificationData FinishedCar(byte position = 1) => new()
    {
        Position = position,
        ResultStatus = F1Enums.ResultStatus.Finished,
    };

    [Fact]
    public void MapSession_MapsLinksModeAndContext()
    {
        var packet = new SessionDataPacket
        {
            Header = Header(),
            Track = F1Enums.Track.Monza,
            SessionType = F1Enums.SessionType.Qualifying2,
            GameMode = F1Enums.GameMode.DriverCareer25,
            SeasonLinkIdentifier = 2_847_561_234,   // uint 범위(> int.MaxValue)
            WeekendLinkIdentifier = 99_112_233,
            SessionLinkIdentifier = 44_556_677,
            TotalLaps = 29,
            AIDifficulty = 85,
            IsNetworkGame = true,
        };

        var frame = _sut.MapSession(packet);

        Assert.Equal(SessionKind.Qualifying2, frame.SessionKind);
        Assert.Equal(CoreSessionType.Qualifying, frame.SessionType);   // 기존 정규화 결과는 그대로
        Assert.Equal(CoreGameMode.DriverCareer, frame.GameMode);
        Assert.Equal(2_847_561_234u, frame.SeasonLinkId);
        Assert.Equal(99_112_233u, frame.WeekendLinkId);
        Assert.Equal(44_556_677u, frame.SessionLinkId);
        Assert.Equal(29, frame.TotalLaps);
        Assert.Equal(85, frame.AiDifficulty);
        Assert.True(frame.IsNetworkGame);
    }

    [Fact]
    public void MapParticipants_MapsSlots_AndNetworkHumanToNull()
    {
        var participants = Slots(
            CarSlotCount,
            (0, new ParticipantData
            {
                IsAiControlled = true,
                Driver = (F1Enums.Driver)9,
                Team = (F1Enums.Team)2,
                RaceNumber = 44,
                Name = "HAMILTON",
            }),
            (1, new ParticipantData
            {
                IsAiControlled = false,
                Driver = F1Enums.Driver.NetworkHuman,
                Team = (F1Enums.Team)5,
                RaceNumber = 26,
                Name = "S. LIM",
            }));
        var packet = new ParticipantsDataPacket { Header = Header(uid: 77), NumActiveCars = 2, Participants = participants };

        var frame = _sut.MapParticipants(packet);

        Assert.Equal("77", frame.SessionRef);
        Assert.Equal(CarSlotCount, frame.Participants.Count);   // 배열 전체를 carIndex 순서로
        Assert.Equal(Enumerable.Range(0, CarSlotCount), frame.Participants.Select(p => p.CarIndex));

        var ai = frame.Participants[0];
        Assert.Equal("HAMILTON", ai.Name);
        Assert.Equal(9, ai.GameDriverId);
        Assert.Equal(2, ai.TeamId);
        Assert.Equal(44, ai.RaceNumber);
        Assert.True(ai.IsAiControlled);

        var human = frame.Participants[1];
        Assert.Equal("S. LIM", human.Name);
        Assert.Null(human.GameDriverId);
        Assert.Equal(5, human.TeamId);
        Assert.Equal(26, human.RaceNumber);
        Assert.False(human.IsAiControlled);
    }

    [Theory]
    [InlineData("LIM\0\0\0\0", "LIM")]            // 고정 길이 버퍼의 NUL 패딩
    [InlineData("LIM\0garbage", "LIM")]           // 첫 NUL 뒤는 버린다
    [InlineData("S. LIM", "S. LIM")]
    [InlineData(null, "")]                        // 이름이 비어 있어도 예외 없이 빈 문자열
    public void MapParticipants_CutsNameAtFirstNul(string? rawName, string expected)
    {
        var participants = Slots(CarSlotCount, (0, new ParticipantData { Name = rawName! }));
        var packet = new ParticipantsDataPacket { Header = Header(), Participants = participants };

        var frame = _sut.MapParticipants(packet);

        Assert.Equal(expected, frame.Participants[0].Name);
    }

    [Fact]
    public void MapClassification_SkipsEmptySlots_AndConvertsUnits()
    {
        var cars = Slots(
            CarSlotCount,
            (0, new FinalClassificationData
            {
                Position = 1,
                GridPosition = 2,
                NumLaps = 29,
                Points = 25,
                NumPitStops = 1,
                NumPenalties = 1,
                ResultStatus = F1Enums.ResultStatus.Finished,
                BestLapTimeInMS = 81_234,
                TotalRaceTime = 1598.7654,            // 초 → 1598765 ms
                PenaltiesTime = 5,                    // 초 → 5000 ms
                NumTyreStints = 2,
                TyreStintsActual = Stints(F1Enums.ActualCompound.F1C3, F1Enums.ActualCompound.F1C2),
                TyreStintsVisual = Stints(F1Enums.VisualCompound.F1Medium, F1Enums.VisualCompound.F1Hard),
                TyreStintsEndLaps = Stints<byte>(14, 29),
            }),
            (1, new FinalClassificationData { Position = 2, ResultStatus = F1Enums.ResultStatus.Inactive }),   // 비활성 칸
            (2, new FinalClassificationData { Position = 0, ResultStatus = F1Enums.ResultStatus.Finished }),   // 순위 0
            (3, new FinalClassificationData { Position = 3, ResultStatus = F1Enums.ResultStatus.Invalid }));   // 무효 칸
        var packet = new FinalClassificationDataPacket { Header = Header(uid: 88, playerIndex: 4), NumCars = 4, ClassificationData = cars };

        var frame = _sut.MapClassification(packet);

        Assert.Equal("88", frame.SessionRef);
        Assert.Equal(4, frame.PlayerCarIndex);
        var row = Assert.Single(frame.Rows);
        Assert.Equal(0, row.CarIndex);
        Assert.Equal(1, row.Position);
        Assert.Equal(2, row.GridPosition);
        Assert.Equal(29, row.NumLaps);
        Assert.Equal(25, row.Points);
        Assert.Equal(1, row.NumPitStops);
        Assert.Equal(1, row.NumPenalties);
        Assert.Equal(CoreResultStatus.Finished, row.ResultStatus);
        Assert.Equal(81_234, row.BestLapTimeMs);
        Assert.Equal(1_598_765, row.TotalRaceTimeMs);
        Assert.Equal(5_000, row.PenaltiesTimeMs);
        Assert.Equal(
            new[]
            {
                new TyreStint(14, CoreTyreCompound.Medium, "C3"),
                new TyreStint(29, CoreTyreCompound.Hard, "C2"),
            },
            row.TyreStints);
    }

    [Fact]
    public void MapClassification_PositionAboveBackendMaximum_IsTreatedAsEmptySlot()
    {
        // 백엔드는 position 1~32만 받는다. 쓰레기 값(33 이상) 한 칸 때문에 세션 전체가 Reject되지 않도록 빈 칸으로 본다.
        var cars = Slots(
            CarSlotCount,
            (0, FinishedCar(position: 32)),
            (1, FinishedCar(position: 33)),
            (2, FinishedCar(position: 255)));
        var packet = new FinalClassificationDataPacket { Header = Header(), ClassificationData = cars };

        var frame = _sut.MapClassification(packet);

        var row = Assert.Single(frame.Rows);
        Assert.Equal(0, row.CarIndex);
        Assert.Equal(32, row.Position);
    }

    [Fact]
    public void MapClassification_KeepsCarIndexOrder()
    {
        var cars = Slots(
            CarSlotCount,
            (3, FinishedCar(position: 2)),
            (7, FinishedCar(position: 1)));
        var packet = new FinalClassificationDataPacket { Header = Header(), ClassificationData = cars };

        var frame = _sut.MapClassification(packet);

        Assert.Equal(new[] { 3, 7 }, frame.Rows.Select(r => r.CarIndex));
        Assert.Equal(new[] { 2, 1 }, frame.Rows.Select(r => r.Position));
    }

    [Fact]
    public void MapClassification_NumTyreStintsAboveEight_IsCappedAtEight()
    {
        var car = FinishedCar() with
        {
            NumTyreStints = 12,
            TyreStintsActual = Stints(F1Enums.ActualCompound.F1C1),
            TyreStintsVisual = Stints(F1Enums.VisualCompound.F1Soft),
            TyreStintsEndLaps = Stints<byte>(10),
        };
        var packet = new FinalClassificationDataPacket { Header = Header(), ClassificationData = Slots(CarSlotCount, (0, car)) };

        var row = Assert.Single(_sut.MapClassification(packet).Rows);

        Assert.Equal(TyreStintSlotCount, row.TyreStints.Count);
    }

    [Fact]
    public void MapClassification_NoStints_GivesEmptyList()
    {
        var packet = new FinalClassificationDataPacket
        {
            Header = Header(),
            ClassificationData = Slots(CarSlotCount, (0, FinishedCar())),
        };

        var row = Assert.Single(_sut.MapClassification(packet).Rows);

        Assert.Empty(row.TyreStints);
    }

    [Fact]
    public void MapClassification_UnknownCompounds_AreUnknownAndNullLabel()
    {
        var car = FinishedCar() with
        {
            NumTyreStints = 1,
            TyreStintsActual = Stints(F1Enums.ActualCompound.F2Hard),
            TyreStintsVisual = Stints(F1Enums.VisualCompound.F2Soft),
            TyreStintsEndLaps = Stints<byte>(5),
        };
        var packet = new FinalClassificationDataPacket { Header = Header(), ClassificationData = Slots(CarSlotCount, (0, car)) };

        var stint = Assert.Single(Assert.Single(_sut.MapClassification(packet).Rows).TyreStints);

        Assert.Equal(new TyreStint(5, CoreTyreCompound.Unknown, null), stint);
    }

    [Fact]
    public void MapClassification_GarbageTimes_NeverProduceNegativeMilliseconds()
    {
        // 백엔드는 음수 시간을 영구 거부한다(12 §6.2-2) — 깨진 값이 와도 항상 거부될 페이로드를 만들지 않는다.
        var nan = FinishedCar(position: 1) with { TotalRaceTime = double.NaN };
        var negative = FinishedCar(position: 2) with { TotalRaceTime = -12.5 };
        var huge = FinishedCar(position: 3) with { TotalRaceTime = 1e18, BestLapTimeInMS = uint.MaxValue };
        var packet = new FinalClassificationDataPacket
        {
            Header = Header(),
            ClassificationData = Slots(CarSlotCount, (0, nan), (1, negative), (2, huge)),
        };

        var rows = _sut.MapClassification(packet).Rows;

        Assert.Equal(0, rows[0].TotalRaceTimeMs);
        Assert.Equal(0, rows[1].TotalRaceTimeMs);
        Assert.Equal(int.MaxValue, rows[2].TotalRaceTimeMs);
        Assert.Equal(int.MaxValue, rows[2].BestLapTimeMs);
    }

    [Fact]
    public void Map_RoutesParticipantsAndClassificationPackets()
    {
        var participants = new ParticipantsDataPacket
        {
            Header = Header(uid: 5),
            Participants = Slots(CarSlotCount, (0, new ParticipantData { Name = "A" })),
        };
        var classification = new FinalClassificationDataPacket
        {
            Header = Header(uid: 5),
            ClassificationData = Slots(CarSlotCount, (0, FinishedCar())),
        };

        var fromParticipants = Assert.Single(_sut.Map(participants));
        var fromClassification = Assert.Single(_sut.Map(classification));

        Assert.IsType<ParticipantsFrame>(fromParticipants);
        Assert.IsType<ClassificationFrame>(fromClassification);
    }

    [Fact]
    public void Map_ParticipantsPacketWithWrongFormat_ReturnsEmpty()
    {
        var packet = new ParticipantsDataPacket
        {
            Header = new PacketHeader { PacketFormat = 1234 },
            Participants = Slots(CarSlotCount, (0, new ParticipantData { Name = "A" })),
        };

        Assert.Empty(_sut.Map(packet));
    }
}
