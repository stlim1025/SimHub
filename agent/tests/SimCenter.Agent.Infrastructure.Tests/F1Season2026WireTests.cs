using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using CoreSessionType = SimCenter.Agent.Core.Telemetry.SessionType;

namespace SimCenter.Agent.Infrastructure.Tests;

/// <summary>
/// UDP 형식 2026(F1 25 2026 시즌팩) 바이트를 읽는지 확인한다. 픽스처(<c>Fixtures/F1_25_2026</c>)는 F1Game.UDP 26.0.0 구조체를 메모리 그대로 쓴 바이트로,
/// 같은 라이브러리로 다시 읽어 같은지 확인해 만들었다(라이브러리가 바이트를 구조체에 그대로 복사해 해석하므로 메모리 배치 = 와이어 배치).
/// 값: 24대, 플레이어 = 마지막 칸(23) — 2025의 22칸 밖이라 24칸을 다 읽어야만 플레이어 값이 나온다. 차 i의 값은 i에서 나온다(각 테스트 주석).
/// </summary>
public class F1Season2026WireTests
{
    private const int PlayerIndex = 23;
    private const int Cars = 24;
    private const string FixtureFolder = "Fixtures/F1_25_2026";
    private const string SessionRef = "1234605616436508552"; // 0x1122334455667788

    private static readonly F1PacketMapper Mapper = new(NullLogger<F1PacketMapper>.Instance);

    private static IReadOnlyList<ITelemetryFrame> MapFixture(string name) =>
        Mapper.Map(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, FixtureFolder, name)));

    private static IReadOnlyDictionary<string, object?> Section(IReadOnlyList<ITelemetryFrame> frames, string section) =>
        Assert.Single(frames.OfType<CarDetailsFrame>(), f => f.Section == section).Values;

    private static double Num(IReadOnlyDictionary<string, object?> values, string key) => Convert.ToDouble(values[key]);

    [Fact]
    public void Motion_ConvertsMilliGForceAndReadsAll24Cars()
    {
        var frames = MapFixture("motion.bin");

        // 차 i: X = 100 + i, Z = −50 − i, G 횡 = (1500 + 10i)/1000, 종 = (−2000 + i)/1000
        var extra = Assert.Single(frames.OfType<ExtraChannelsFrame>()).Channels;
        Assert.Equal(123, extra["worldPosX"]);
        Assert.Equal(1.73, extra["gForceLateral"]);
        Assert.Equal(-1.98, extra["gForceLongitudinal"]);
        Assert.Equal(1.0, extra["gForceVertical"]);

        var field = Assert.Single(frames.OfType<FieldPositionsFrame>());
        Assert.Equal(Cars, field.Cars.Count);
        Assert.Equal((4242u, 123_500), (field.FrameId, field.SessionTimeMs));
        Assert.Equal(new FieldPosition(100, -50, 1.5f, -2f, 2.5f), field.Cars[0]);
        Assert.Equal(123, field.Cars[PlayerIndex].X);
        Assert.Equal(1.73f, field.Cars[PlayerIndex].GLateral, 3);
    }

    [Fact]
    public void LapData_PlayerInLastSlot_MapsLapAndAllCarStates()
    {
        var frames = MapFixture("lapdata.bin");

        var lap = Assert.IsType<LapFrame>(frames[0]);
        Assert.Equal(SessionRef, lap.SessionRef);
        Assert.Equal((3, 1, 90_023, 1_023f), (lap.CurrentLapNumber, lap.CurrentSector, lap.LastLapTimeMs, lap.LapDistanceM));

        var details = Section(frames, F1DetailSections.LapData);
        Assert.Equal((23d, 24d, 255d, 254d), (Num(details, "carIndex"), Num(details, "carPosition"), Num(details, "timeTrialPbCarIndex"), Num(details, "timeTrialRivalCarIndex")));

        var states = Assert.IsType<FieldLapStatesFrame>(frames[^1]);
        Assert.Equal(Cars, states.Cars.Count);
        Assert.Equal(1_023f, states.Cars[PlayerIndex].LapDistanceM);
        Assert.True(states.Cars[PlayerIndex].IsOnTrack);
    }

    [Fact]
    public void CarTelemetry_WidensOneByteEngineTemperature()
    {
        var frames = MapFixture("cartelemetry.bin");

        var telemetry = Assert.Single(frames.OfType<CarTelemetryFrame>());
        Assert.Equal((223, 11_023, 6), (telemetry.SpeedKph, telemetry.EngineRpm, telemetry.Gear));
        Assert.Equal(-0.25f, telemetry.Steer);

        var extra = Assert.Single(frames.OfType<ExtraChannelsFrame>()).Channels;
        Assert.Equal(103, extra["engineTemp"]);          // 100 + 23 % 20
        Assert.Equal(7, extra["suggestedGear"]);
        Assert.Equal(21.6, extra["tyrePressureRR"]);
        Assert.Equal(7, extra["surfaceTypeRR"]);         // 잔디

        var field = Assert.Single(frames.OfType<FieldSurfacesFrame>());
        Assert.Equal(Cars, field.Surfaces.Count);
        Assert.Equal((ushort)223, field.SpeedsKph![PlayerIndex]);
        Assert.Equal((ushort)0x7010, field.Surfaces[PlayerIndex]);   // FL 아스팔트 · FR 연석(1) · RL 아스팔트 · RR 잔디(7)
    }

    [Fact]
    public void CarStatus_SkipsHarvestLimitInLayoutAndPutsItInDetails()
    {
        var frames = MapFixture("carstatus.bin");

        var status = Assert.Single(frames.OfType<CarStatusFrame>());
        Assert.Equal((27f, 3_023_000f, 1_000_023f, 23), (status.FuelInTankKg, status.ErsStoreEnergyJ, status.ErsDeployedThisLapJ, status.TyreAgeLaps));
        Assert.Equal((18, 16), (status.ActualTyreCompound, status.VisualTyreCompound));

        var details = Section(frames, F1DetailSections.Status);
        Assert.Equal(8_500_000d, Num(details, "ersHarvestLimitPerLap"));
        Assert.Equal(3d, Num(details, "ersDeployMode"));   // 2026: 3 = Boost
        Assert.Equal(13_000d, Num(details, "maxRpm"));

        var field = Assert.Single(frames.OfType<FieldStatusFrame>());
        Assert.Equal(Cars, field.TyreAgeLaps.Count);
        Assert.Equal((ushort)3_023, field.ErsStoreKj![PlayerIndex]);
    }

    [Fact]
    public void CarDamage_ReadsAll24Cars()
    {
        var frames = MapFixture("cardamage.bin");

        var damage = Assert.Single(frames.OfType<CarDamageFrame>());
        Assert.Equal(33f, damage.TyreWearPercent.FrontLeft);   // 10 + 23
        Assert.Equal(13f, damage.TyreWearPercent.RearRight);
        Assert.Equal((3, 3), (damage.FrontLeftWingDamage, damage.RearWingDamage));
        Assert.Equal(12d, Num(Section(frames, F1DetailSections.Damage), "engineMgukWear"));

        var field = Assert.Single(frames.OfType<FieldDamageFrame>());
        Assert.Equal(Cars, field.Damage.Count);
        Assert.Equal((byte)3, field.Damage[PlayerIndex]);
    }

    [Fact]
    public void CarSetups_PlayerCarAndNextFrontWing()
    {
        var setup = Section(MapFixture("carsetups.bin"), F1DetailSections.Setup);

        Assert.Equal((43d, 25d, 56d), (Num(setup, "frontWing"), Num(setup, "rearWing"), Num(setup, "brakeBias")));
        Assert.Equal((15.5d, 31.5d), (Num(setup, "fuelLoad"), Num(setup, "nextFrontWingValue")));
        Assert.Equal(27d, Num(setup, "tyrePressureRL"));
    }

    [Fact]
    public void FinalClassification_AllRowsWithPlayerOnPole()
    {
        var classification = Assert.IsType<ClassificationFrame>(Assert.Single(MapFixture("classification.bin")));

        Assert.Equal((PlayerIndex, Cars), (classification.PlayerCarIndex, classification.Rows.Count));
        var player = Assert.Single(classification.Rows, r => r.CarIndex == PlayerIndex);
        Assert.Equal((1, 24, 73_023, 923_500), (player.Position, player.GridPosition, player.BestLapTimeMs, player.TotalRaceTimeMs));
        Assert.Equal([5, 12], player.TyreStints.Select(s => s.EndLap));
    }

    [Fact]
    public void Participants_ReadsTwoByteDriverNetworkAndTeamIds()
    {
        var frames = MapFixture("participants.bin");

        var participants = Assert.IsType<ParticipantsFrame>(frames[0]);
        Assert.Equal(Cars, participants.Participants.Count);
        Assert.Equal(new ParticipantInfo(PlayerIndex, "GOMDOL", GameDriverId: 188, TeamId: 485, RaceNumber: 25, IsAiControlled: false), participants.Participants[PlayerIndex]);
        Assert.Null(participants.Participants[5].GameDriverId);            // 사람(네트워크) = 65535
        Assert.Equal(("DRIVER0", 476), (participants.Participants[0].Name, participants.Participants[0].TeamId));

        var details = Section(frames, F1DetailSections.Participant);
        Assert.Equal((188d, 485d, 0d, 1_234d, 75d), (Num(details, "driverId"), Num(details, "teamId"), Num(details, "networkId"), Num(details, "techLevel"), Num(details, "nationality")));
    }

    [Fact]
    public void LapPositions_Reads24CarsPerLap()
    {
        var positions = Assert.IsType<LapPositionsFrame>(Assert.Single(MapFixture("lappositions.bin")));

        Assert.Equal(1, positions.FirstLapNumber);
        Assert.Equal(2, positions.PositionsByLap.Count);
        Assert.All(positions.PositionsByLap, lap => Assert.Equal(Cars, lap.Count));
        Assert.Equal(24, positions.PositionsByLap[1][PlayerIndex]);
    }

    [Fact]
    public void TimeTrial_ReadsTwoByteTeamIds()
    {
        var timeTrial = Section(MapFixture("timetrial.bin"), F1DetailSections.TimeTrial);

        var best = Assert.IsAssignableFrom<IReadOnlyDictionary<string, object?>>(timeTrial["playerSessionBest"]);
        Assert.Equal((23d, 485d, 75_000d, 24_000d), (Num(best, "carIndex"), Num(best, "teamId"), Num(best, "lapTimeMs"), Num(best, "sector3TimeMs")));
        Assert.True((bool)best["valid"]!);
        Assert.Equal(486d, Num(Assert.IsAssignableFrom<IReadOnlyDictionary<string, object?>>(timeTrial["personalBest"]), "teamId"));
        var rival = Assert.IsAssignableFrom<IReadOnlyDictionary<string, object?>>(timeTrial["rival"]);
        Assert.Equal((1d, 484d, 74_000d), (Num(rival, "carIndex"), Num(rival, "teamId"), Num(rival, "lapTimeMs")));
    }

    [Fact]
    public void Session_MapsFrameAndAddsActiveAeroZonesAndReactionTime()
    {
        var frames = MapFixture("session.bin");

        var session = Assert.Single(frames.OfType<SessionFrame>());
        Assert.Equal((26, CoreSessionType.Qualifying, 2026), (session.TrackId, session.SessionType, session.PacketFormat));
        Assert.Equal((4_259, 2_160_042_397u), (session.TrackLengthM, session.SessionLinkId));

        var details = Section(frames, F1DetailSections.Session);
        Assert.Equal((13d, 1d), (Num(details, "formula"), Num(details, "activeAeroTrackStatus")));
        var full = Assert.IsType<object?[]>(details["activeAeroZonesFull"]);
        Assert.Equal(2, full.Length);
        var second = Assert.IsAssignableFrom<IReadOnlyDictionary<string, object?>>(full[1]);
        Assert.Equal((0.5d, 0.6d), (Num(second, "zoneStart"), Math.Round(Num(second, "zoneEnd"), 3)));
        Assert.Single(Assert.IsType<object?[]>(details["activeAeroZonesPartial"]));
        Assert.Empty(Assert.IsType<object?[]>(details["drsZones"]));
        Assert.Equal(0.234, Math.Round(Num(details, "startReactionTimeS"), 3));
        Assert.Equal((0d, 1d), (Num(details, "antiLockBrakesAssist"), Num(details, "tractionControlAssist")));
        Assert.Equal(
            (1d, 2d, 1d),
            (Num(details, "dynamicRacingLineHiVis"), Num(details, "dynamicRacingLineColourBlind"), Num(details, "recurringRewindPrompt")));
    }

    [Fact]
    public void CarTelemetry2_PlayerValuesBecomeExtraChannels()
    {
        var extra = Assert.Single(MapFixture("cartelemetry2.bin").OfType<ExtraChannelsFrame>()).Channels;

        // 차 i: 에어로 모드 i % 2, 에어로 거리 100 + i, 오버테이크 거리 50 + i, 오버테이크 사용 중 = 플레이어만, 이전 규정 = 차 7, 역주행 = 차 5
        Assert.Equal(1, extra["activeAeroMode"]);
        Assert.Equal(1, extra["activeAeroAvailable"]);
        Assert.Equal(123, extra["activeAeroActivationDistance"]);
        Assert.Equal(1, extra["overtakeAvailable"]);
        Assert.Equal(1, extra["overtakeActive"]);
        Assert.Equal(73, extra["overtakeActivationDistance"]);
        Assert.Equal(1, extra["regulations2026"]);
        Assert.Equal(0, extra["drivingWrongWay"]);
    }

    [Fact]
    public void CarTelemetry2_AllCarsActiveAeroAndOvertakeModeBecomeFieldFrame()
    {
        var field = Assert.Single(MapFixture("cartelemetry2.bin").OfType<FieldActiveAeroFrame>());

        // 에어로 사용 가능 = i % 3 != 0, 오버테이크 사용 가능 = i % 4 != 0
        Assert.Equal(SessionRef, field.SessionRef);
        Assert.Equal(24, field.Cars.Count);
        Assert.Equal(new FieldActiveAero(false, false, false, false, false), field.Cars[0]);
        Assert.Equal(new FieldActiveAero(true, true, true, false, true), field.Cars[5]);
        Assert.Equal(new FieldActiveAero(true, true, true, true, false), field.Cars[PlayerIndex]);
    }

    [Fact]
    public void PartialModeEnabledEvent_AddsReason()
    {
        var gameEvent = Assert.IsType<GameEventFrame>(Assert.Single(MapFixture("pmen.bin")));

        Assert.Equal("PMEN", gameEvent.Code);
        Assert.Equal(1d, Num(gameEvent.Details, "reason"));
    }

    [Fact]
    public void CollisionEvent_AddsSeverity()
    {
        var frames = MapFixture("collision.bin");

        var gameEvent = Assert.IsType<GameEventFrame>(frames[0]);
        Assert.Equal("COLL", gameEvent.Code);
        Assert.Equal((23d, 4d, 2d), (Num(gameEvent.Details, "vehicle1Index"), Num(gameEvent.Details, "vehicle2Index"), Num(gameEvent.Details, "severity")));
        Assert.Equal(new FieldCollisionFrame(SessionRef, PlayerIndex, 4), frames[1]);
    }

    [Fact]
    public void TruncatedPacket_IsDroppedWithOneWarning()
    {
        var logger = new ListLogger();
        var mapper = new F1PacketMapper(logger);
        var motion = File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, FixtureFolder, "motion.bin"))[..1_300];

        Assert.Empty(mapper.Map(motion));
        Assert.Empty(mapper.Map(motion));

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning).Message;
        Assert.Contains("2026", warning);
        Assert.Contains("1325", warning);
    }

    private sealed class ListLogger : ILogger<F1PacketMapper>
    {
        public List<(LogLevel Level, string Message)> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Entries.Add((logLevel, formatter(state, exception)));
    }
}
