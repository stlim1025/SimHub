using System.Buffers.Binary;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Tests;

/// <summary>
/// <c>car.details</c> 묶음·게임 이벤트·세션 기록(D-49, docs/15 §8)을 F1 25 규격 크기의 합성 바이트로 확인한다(오프셋은 F1 25 UDP 스펙).
/// 바퀴 배열(RL·RR·FL·FR)은 이름(FL·FR·RL·RR)으로 옮겨졌는지, 다른 차 패킷은 버리는지, 같은 패킷 안 프레임 순서를 본다.
/// </summary>
public class F1DetailSectionsWireTests
{
    private const int Format = 2025;
    private const int PacketIdOffset = 6;
    private const int PlayerCarIndexOffset = 27;
    private const int HeaderSize = 29;
    private const byte PlayerIndex = 2;
    private const string FixtureFolder = "Fixtures/F1_25";

    private static readonly F1PacketMapper Mapper = new(Format, NullLogger<F1PacketMapper>.Instance);

    [Fact]
    public void CarSetups_PlayerCar_MapsAllFieldsWithWheelNames()
    {
        var datagram = Datagram(F1Enums.PacketType.CarSetups, 1133);
        var car = HeaderSize + (PlayerIndex * 50);
        WriteBytes(datagram, car, 30, 25, 70, 55);                          // 앞·뒤 날개, 온·오프 스로틀
        WriteFloats(datagram, car + 4, -3.5f, -2f, 0.05f, 0.2f);            // 앞·뒤 캠버, 앞·뒤 토
        WriteBytes(datagram, car + 20, 41, 3, 10, 5, 20, 52, 95, 56, 1);    // 서스펜션·ARB·높이, 브레이크 압력·바이어스, 엔진 브레이크
        WriteFloats(datagram, car + 29, 21.1f, 21.2f, 22.3f, 22.4f);        // 공기압[RL, RR, FL, FR]
        datagram[car + 45] = 6;                                             // 밸러스트
        WriteFloats(datagram, car + 46, 12.5f);                             // 연료 적재
        WriteFloats(datagram, 1129, 31f);                                   // m_nextFrontWingValue(패킷 끝)

        var setup = Section(Mapper.Map(datagram), F1DetailSections.Setup);

        Assert.Equal((byte)30, setup["frontWing"]);
        Assert.Equal((byte)55, setup["offThrottle"]);
        Assert.Equal(-3.5f, setup["frontCamber"]);
        Assert.Equal(0.2f, setup["rearToe"]);
        Assert.Equal((byte)41, setup["frontSuspension"]);
        Assert.Equal((byte)56, setup["brakeBias"]);
        Assert.Equal((byte)1, setup["engineBraking"]);
        Assert.Equal(new object?[] { 22.3f, 22.4f, 21.1f, 21.2f }, Wheels(setup, "tyrePressure"));
        Assert.Equal((byte)6, setup["ballast"]);
        Assert.Equal(12.5f, setup["fuelLoad"]);
        Assert.Equal(31f, setup["nextFrontWingValue"]);
    }

    [Fact]
    public void CarDamage_DetailsFollowDamageFrame_WithBlistersAndEngineWear()
    {
        var datagram = Datagram(F1Enums.PacketType.CarDamage, 1041);
        var car = HeaderSize + (PlayerIndex * 46);
        WriteBytes(datagram, car + 24, 1, 2, 3, 4);                    // m_tyreBlisters[RL, RR, FL, FR]
        WriteBytes(datagram, car + 34, 1, 0);                          // DRS·ERS 고장
        WriteBytes(datagram, car + 38, 11, 12, 13, 14, 15, 16, 0, 1);  // MGU-H·ES·CE·ICE·MGU-K·TC 마모, 엔진 블로운·시즈

        var frames = Mapper.Map(datagram);

        Assert.IsType<CarDamageFrame>(frames[0]);
        var damage = Section(frames, F1DetailSections.Damage);
        Assert.Equal(new object?[] { (byte)3, (byte)4, (byte)1, (byte)2 }, Wheels(damage, "tyreBlisters"));
        Assert.Equal(true, damage["drsFault"]);
        Assert.Equal(false, damage["ersFault"]);
        Assert.Equal(
            new object?[] { (byte)11, (byte)12, (byte)13, (byte)14, (byte)15, (byte)16 },
            new[] { "engineMguhWear", "engineEsWear", "engineCeWear", "engineIceWear", "engineMgukWear", "engineTcWear" }.Select(key => damage[key]));
        Assert.Equal(false, damage["engineBlown"]);
        Assert.Equal(true, damage["engineSeized"]);
    }

    [Fact]
    public void CarStatus_Details_CarryLimitsAndFlags()
    {
        var datagram = Datagram(F1Enums.PacketType.CarStatus, 1239);
        var car = HeaderSize + (PlayerIndex * 55);
        WriteFloats(datagram, car + 9, 110f);                      // m_fuelCapacity
        WriteUInt16s(datagram, car + 17, 13_000, 4_000);           // m_maxRPM, m_idleRPM
        datagram[car + 21] = 8;                                    // m_maxGears
        WriteUInt16s(datagram, car + 23, 120);                     // m_drsActivationDistance
        datagram[car + 54] = 1;                                    // m_networkPaused

        var status = Section(Mapper.Map(datagram), F1DetailSections.Status);

        Assert.Equal(110f, status["fuelCapacity"]);
        Assert.Equal((ushort)13_000, status["maxRpm"]);
        Assert.Equal((ushort)4_000, status["idleRpm"]);
        Assert.Equal((byte)8, status["maxGears"]);
        Assert.Equal((ushort)120, status["drsActivationDistance"]);
        Assert.Equal(true, status["networkPaused"]);
    }

    [Fact]
    public void TyreSets_PlayerCar_MapsTwentySets()
    {
        var datagram = Datagram(F1Enums.PacketType.TyreSets, 231);
        datagram[29] = PlayerIndex;                                  // m_carIdx
        var set = 30 + (3 * 10);                                     // 세트 3
        WriteBytes(datagram, set, 18, 16, 12, 1, 15, 25, 18);        // 실제·표시 컴파운드, 마모, 사용 가능, 추천 세션, 수명, 남은 수명
        BinaryPrimitives.WriteInt16LittleEndian(datagram.AsSpan(set + 7), -350);   // m_lapDeltaTime
        datagram[set + 9] = 1;                                       // m_fitted
        datagram[230] = 3;                                           // m_fittedIdx

        var tyreSets = Section(Mapper.Map(datagram), F1DetailSections.TyreSets);

        Assert.Equal((byte)3, tyreSets["fittedIndex"]);
        var sets = Assert.IsType<object?[]>(tyreSets["sets"]);
        Assert.Equal(20, sets.Length);
        var fitted = AsDictionary(sets[3]);
        Assert.Equal(18, fitted["actualCompound"]);
        Assert.Equal(16, fitted["visualCompound"]);
        Assert.Equal((byte)12, fitted["wearPercent"]);
        Assert.Equal(true, fitted["available"]);
        Assert.Equal(15, fitted["recommendedSession"]);
        Assert.Equal((short)-350, fitted["lapDeltaTimeMs"]);
        Assert.Equal(true, fitted["fitted"]);
    }

    [Fact]
    public void TyreSets_OtherCar_IsDropped()
    {
        var datagram = Datagram(F1Enums.PacketType.TyreSets, 231);
        datagram[29] = PlayerIndex + 1;

        Assert.Empty(Mapper.Map(datagram));
    }

    [Fact]
    public void TimeTrial_MapsThreeDataSets()
    {
        var datagram = Datagram(F1Enums.PacketType.TimeTrial, 101);
        var personalBest = 29 + 24;                                       // 두 번째 세트
        WriteBytes(datagram, personalBest, 2, 8);                        // carIdx, teamId
        WriteUInt32s(datagram, personalBest + 2, 83_452, 27_010, 30_110, 26_332);
        WriteBytes(datagram, personalBest + 18, 2, 3, 1, 1, 0, 1);       // TC, 기어박스, ABS, 동일 성능, 커스텀 셋업, 유효

        var timeTrial = Section(Mapper.Map(datagram), F1DetailSections.TimeTrial);

        var pb = AsDictionary(timeTrial["personalBest"]);
        Assert.Equal((byte)2, pb["carIndex"]);
        Assert.Equal(8, pb["teamId"]);
        Assert.Equal(83_452u, pb["lapTimeMs"]);
        Assert.Equal(26_332u, pb["sector3TimeMs"]);
        Assert.Equal(3, pb["gearboxAssist"]);
        Assert.Equal(false, pb["customSetup"]);
        Assert.Equal(true, pb["valid"]);
        Assert.True(timeTrial.ContainsKey("playerSessionBest"));
        Assert.True(timeTrial.ContainsKey("rival"));
    }

    [Fact]
    public void LapData_DetailsAreLastFrame_WithPenaltiesAndGhostIndices()
    {
        var datagram = Datagram(F1Enums.PacketType.LapData, 1285);
        var car = HeaderSize + (PlayerIndex * 57);
        WriteBytes(datagram, car + 38, 5, 3, 2);           // 패널티(초), 경고, 코너 컷 경고
        WriteFloats(datagram, car + 52, 331.5f);           // 스피드 트랩 최고 속도
        datagram[car + 56] = 4;                            // 그 랩
        WriteBytes(datagram, 1283, 9, 10);                 // 타임 트라이얼 PB·라이벌 고스트 carIdx

        var frames = Mapper.Map(datagram);

        Assert.IsType<LapFrame>(frames[0]);
        var lapData = Assert.IsType<CarDetailsFrame>(frames[^1]).Values;
        Assert.Equal(F1DetailSections.LapData, ((CarDetailsFrame)frames[^1]).Section);
        Assert.Equal(PlayerIndex, Convert.ToInt32(lapData["carIndex"]));
        Assert.Equal((byte)5, lapData["penaltiesS"]);
        Assert.Equal((byte)3, lapData["totalWarnings"]);
        Assert.Equal((byte)2, lapData["cornerCuttingWarnings"]);
        Assert.Equal(331.5f, lapData["speedTrapFastestSpeedKph"]);
        Assert.Equal((byte)4, lapData["speedTrapFastestLap"]);
        Assert.Equal((byte)9, lapData["timeTrialPbCarIndex"]);
        Assert.Equal((byte)10, lapData["timeTrialRivalCarIndex"]);
    }

    [Fact]
    public void Participants_PlayerSlot_AddsParticipantDetails()
    {
        var datagram = Datagram(F1Enums.PacketType.Participants, 1284);
        var player = 30 + (PlayerIndex * 57);
        WriteBytes(datagram, player, 0, 255, 7, 8, 1, 26, 75);   // AI, 드라이버(네트워크 사람), 네트워크 ID, 팀, 마이팀, 번호, 국적
        Encoding.ASCII.GetBytes("S. LIM").CopyTo(datagram, player + 7);
        WriteUInt16s(datagram, player + 41, 1_200);              // m_techLevel
        datagram[player + 43] = 1;                               // 플랫폼(Steam)

        var frames = Mapper.Map(datagram);

        Assert.IsType<ParticipantsFrame>(frames[0]);
        var participant = Section(frames, F1DetailSections.Participant);
        Assert.Equal(PlayerIndex, Convert.ToInt32(participant["carIndex"]));
        Assert.Equal(255, participant["driverId"]);
        Assert.Equal(8, participant["teamId"]);
        Assert.Equal(true, participant["myTeam"]);
        Assert.Equal("S. LIM", participant["name"]);
        Assert.Equal((ushort)1_200, participant["techLevel"]);
        Assert.Equal(1, participant["platform"]);
    }

    [Fact]
    public void Participants_SpectatingIndex_HasNoParticipantDetails()
    {
        var datagram = Datagram(F1Enums.PacketType.Participants, 1284, playerIndex: byte.MaxValue);

        Assert.IsType<ParticipantsFrame>(Assert.Single(Mapper.Map(datagram)));
    }

    [Fact]
    public void Session_RealCapture_AddsSessionDetailsAfterSessionFrame()
    {
        var frames = Mapper.Map(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, FixtureFolder, "session.bin")));

        Assert.IsType<SessionFrame>(frames[0]);
        var session = Section(frames, F1DetailSections.Session);
        Assert.Equal((int)F1Enums.Track.Texas, session["trackId"]);
        Assert.Equal((int)F1Enums.SessionType.TimeTrial, session["sessionType"]);
        Assert.Equal((ushort)5514, session["trackLength"]);
        Assert.Empty(Assert.IsType<object?[]>(session["weatherForecast"]));   // Time Trial 캡처에는 예보가 없다
        Assert.IsType<object?[]>(session["marshalZones"]);
        Assert.IsType<object?[]>(session["weekendStructure"]);
    }

    // ---- Event(3) ----

    [Fact]
    public void Event_Penalty_MapsAllDetailFields()
    {
        var datagram = EventDatagram("PENA");
        WriteBytes(datagram, 33, 4, 7, 2, 255, 5, 3, 0);   // 패널티 종류, 위반 종류, 차, 다른 차, 시간, 랩, 얻은 순위

        var gameEvent = Assert.IsType<GameEventFrame>(Assert.Single(Mapper.Map(datagram)));

        Assert.Equal("PENA", gameEvent.Code);
        Assert.Equal(4, gameEvent.Details["penaltyType"]);
        Assert.Equal(7, gameEvent.Details["infringementType"]);
        Assert.Equal((byte)2, gameEvent.Details["vehicleIndex"]);
        Assert.Equal((byte)255, gameEvent.Details["otherVehicleIndex"]);
        Assert.Equal((byte)5, gameEvent.Details["timeS"]);
        Assert.Equal((byte)3, gameEvent.Details["lapNumber"]);
    }

    [Fact]
    public void Event_FastestLap_ConvertsSecondsToMilliseconds()
    {
        var datagram = EventDatagram("FTLP");
        datagram[33] = 2;
        WriteFloats(datagram, 34, 83.4526f);

        var gameEvent = Assert.IsType<GameEventFrame>(Assert.Single(Mapper.Map(datagram)));

        Assert.Equal((byte)2, gameEvent.Details["vehicleIndex"]);
        Assert.Equal(83_453, gameEvent.Details["lapTimeMs"]);
    }

    [Fact]
    public void Event_SpeedTrap_MapsSpeedsAndFlags()
    {
        var datagram = EventDatagram("SPTP");
        datagram[33] = 2;
        WriteFloats(datagram, 34, 331.25f);
        WriteBytes(datagram, 38, 1, 1, 2);
        WriteFloats(datagram, 41, 331.25f);

        var details = Assert.IsType<GameEventFrame>(Assert.Single(Mapper.Map(datagram))).Details;

        Assert.Equal(331.25f, details["speedKph"]);
        Assert.Equal(true, details["overallFastestInSession"]);
        Assert.Equal((byte)2, details["fastestVehicleIndexInSession"]);
        Assert.Equal(331.25f, details["fastestSpeedInSessionKph"]);
    }

    [Fact]
    public void Event_FlashbackAndCollision_MapDetails()
    {
        var flashback = EventDatagram("FLBK");
        WriteUInt32s(flashback, 33, 12_345);
        WriteFloats(flashback, 37, 61.5f);
        var collision = EventDatagram("COLL");
        WriteBytes(collision, 33, 2, 7);

        var flashbackDetails = Assert.IsType<GameEventFrame>(Assert.Single(Mapper.Map(flashback))).Details;
        var collisionDetails = Assert.IsType<GameEventFrame>(Assert.Single(Mapper.Map(collision))).Details;

        Assert.Equal(12_345u, flashbackDetails["flashbackFrameIdentifier"]);
        Assert.Equal(61_500, flashbackDetails["flashbackSessionTimeMs"]);
        Assert.Equal((byte)2, collisionDetails["vehicle1Index"]);
        Assert.Equal((byte)7, collisionDetails["vehicle2Index"]);
    }

    [Theory]
    [InlineData("CHQF")]
    [InlineData("DRSE")]
    [InlineData("LGOT")]
    [InlineData("RDFL")]
    public void Event_WithoutDetails_IsCodeOnly(string code)
    {
        var gameEvent = Assert.IsType<GameEventFrame>(Assert.Single(Mapper.Map(EventDatagram(code))));

        Assert.Equal(code, gameEvent.Code);
        Assert.Empty(gameEvent.Details);
    }

    [Fact]
    public void Event_Buttons_AreDropped_AndSessionBoundariesStayMarkers()
    {
        Assert.Empty(Mapper.Map(EventDatagram("BUTN")));
        Assert.IsType<EventMarker>(Assert.Single(Mapper.Map(EventDatagram("SSTA"))));
        Assert.IsType<EventMarker>(Assert.Single(Mapper.Map(EventDatagram("SEND"))));
    }

    // ---- Session History(11) · Lap Positions(15) ----

    [Fact]
    public void SessionHistory_MapsLapsUpToNumLaps_WithSectorMinutesAndValidFlags()
    {
        var datagram = Datagram(F1Enums.PacketType.SessionHistory, 1460);
        WriteBytes(datagram, 29, PlayerIndex, 2);                  // m_carIdx, m_numLaps
        var lap2 = 36 + 14;
        WriteUInt32s(datagram, lap2, 95_432);                     // m_lapTimeInMS
        WriteUInt16s(datagram, lap2 + 4, 5_100);                  // S1 ms
        datagram[lap2 + 6] = 0;
        WriteUInt16s(datagram, lap2 + 7, 1_200);                  // S2 ms + 1분
        datagram[lap2 + 9] = 1;
        WriteUInt16s(datagram, lap2 + 10, 29_132);                // S3 ms
        datagram[lap2 + 13] = 0b1011;                             // 랩·S1·S3 유효, S2 무효
        WriteUInt32s(datagram, 36 + (2 * 14), 77_777);            // 개수 밖 칸(쓰레기)

        var history = Assert.IsType<SessionHistoryFrame>(Assert.Single(Mapper.Map(datagram)));

        Assert.True(history.IsPlayer);
        Assert.Equal(PlayerIndex, history.CarIndex);
        Assert.Equal(2, history.Laps.Count);
        Assert.Equal(new LapHistoryEntry(2, 95_432, 5_100, 61_200, 29_132, true, true, false, true), history.Laps[1]);
    }

    [Fact]
    public void SessionHistory_OtherCar_IsNotPlayer()
    {
        var datagram = Datagram(F1Enums.PacketType.SessionHistory, 1460);
        datagram[29] = 7;

        Assert.False(Assert.IsType<SessionHistoryFrame>(Assert.Single(Mapper.Map(datagram))).IsPlayer);
    }

    [Fact]
    public void LapPositions_MapsLapsFromStartingLap()
    {
        var datagram = Datagram(F1Enums.PacketType.LapPositions, 1131);
        WriteBytes(datagram, 29, 2, 10);                    // m_numLaps, m_lapStart(0부터)
        WriteBytes(datagram, 31, 3, 1, 2);                  // 첫 랩: car 0 = 3위, car 1 = 1위, car 2 = 2위
        WriteBytes(datagram, 31 + 22, 2, 1, 3);             // 둘째 랩

        var positions = Assert.IsType<LapPositionsFrame>(Assert.Single(Mapper.Map(datagram)));

        Assert.Equal(11, positions.FirstLapNumber);
        Assert.Equal(2, positions.PositionsByLap.Count);
        Assert.Equal(22, positions.PositionsByLap[0].Count);
        Assert.Equal(new[] { 3, 1, 2, 0 }, positions.PositionsByLap[0].Take(4));
        Assert.Equal(new[] { 2, 1, 3, 0 }, positions.PositionsByLap[1].Take(4));
    }

    // ---- 헬퍼 ----

    private static IReadOnlyDictionary<string, object?> Section(IReadOnlyList<ITelemetryFrame> frames, string section) =>
        Assert.Single(frames.OfType<CarDetailsFrame>(), frame => frame.Section == section).Values;

    private static IReadOnlyDictionary<string, object?> AsDictionary(object? value) =>
        Assert.IsAssignableFrom<IReadOnlyDictionary<string, object?>>(value);

    private static object?[] Wheels(IReadOnlyDictionary<string, object?> values, string key) =>
        [values[key + "FL"], values[key + "FR"], values[key + "RL"], values[key + "RR"]];

    private static byte[] EventDatagram(string code)
    {
        var datagram = Datagram(F1Enums.PacketType.Event, 45);
        Encoding.ASCII.GetBytes(code).CopyTo(datagram, HeaderSize);
        return datagram;
    }

    private static byte[] Datagram(F1Enums.PacketType packetType, int size, byte playerIndex = PlayerIndex)
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

    private static void WriteUInt16s(byte[] datagram, int offset, params ushort[] values)
    {
        for (var i = 0; i < values.Length; i++)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(datagram.AsSpan(offset + (i * sizeof(ushort))), values[i]);
        }
    }

    private static void WriteUInt32s(byte[] datagram, int offset, params uint[] values)
    {
        for (var i = 0; i < values.Length; i++)
        {
            BinaryPrimitives.WriteUInt32LittleEndian(datagram.AsSpan(offset + (i * sizeof(uint))), values[i]);
        }
    }

    private static void WriteBytes(byte[] datagram, int offset, params byte[] values) => values.CopyTo(datagram, offset);
}
