using System.Text;
using System.Text.Json;
using F1Game.UDP.Data;
using F1Game.UDP.Packets;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Mapping;
using SimCenter.Agent.Infrastructure.Outbox;
using SimCenter.Agent.Infrastructure.Sinks;
using Xunit.Abstractions;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Tests;

/// <summary>
/// "전부 수집"(D-49, docs/15 §8)의 실제 크기: Spa(7,004m) 1랩을 5m 칸마다 게임에서 나올 법한 패킷 값으로 만들어 <b>실제 매퍼·기록기</b>를 거친
/// 트레이스(기본 7채널 + extra 118채널)와 상세(셋업·세션·타이어 세트 20·이벤트 40 …)를 싣고 싱크가 Outbox에 넣은 바이트를 잰다.
/// </summary>
public sealed class OutboxTelemetrySinkCollectAllSizeTests : IAsyncLifetime
{
    private const int SpaLengthM = 7_004;
    private const int SpaLapTimeMs = 106_000;
    private const int EventCount = 40;
    private const int RandomSeed = 49;

    private readonly ITestOutputHelper _output;
    private readonly TelemetryOutbox _outbox = new(Options.Create(new AgentOptions { OutboxPath = ":memory:" }));
    private readonly OutboxTelemetrySink _sut;
    private readonly F1PacketMapper _mapper = new(2025, NullLogger<F1PacketMapper>.Instance);
    private readonly Random _random = new(RandomSeed);

    public OutboxTelemetrySinkCollectAllSizeTests(ITestOutputHelper output)
    {
        _output = output;
        _sut = new OutboxTelemetrySink(_outbox, NullLogger<OutboxTelemetrySink>.Instance);
    }

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync() => await _outbox.DisposeAsync();

    [Fact]
    public async Task SpaLap_AllExtraChannelsAt5m_WithDetails_IsMeasuredAndEnqueued()
    {
        var trace = RecordSpaTrace();
        var lap = Lap(trace, RealisticDetails());
        var fullBytes = Utf8Bytes(JsonSerializer.Serialize<object>(lap, OutboxTelemetrySink.WireJson));

        await _sut.EmitAsync(new TelemetryEnvelope(Guid.NewGuid(), "F1_25", DateTime.UnixEpoch, TelemetryEventType.LapFinished, lap));

        var json = Assert.Single(await _outbox.GetPendingAsync(max: 1)).PayloadJson;
        using var doc = JsonDocument.Parse(json);
        var payload = doc.RootElement.GetProperty("payload");
        var wireTrace = payload.GetProperty("trace");
        var resolution = wireTrace.GetProperty("resolutionM").GetInt32();
        _output.WriteLine(
            $"Spa 7,004m: {trace.TimeMs.Count} samples @5m, extra {trace.Extra!.Count} channels — payload @5m {fullBytes} bytes; " +
            $"enqueued envelope {Utf8Bytes(json)} bytes @{resolution}m (limit {OutboxTelemetrySink.MaxEnvelopeBytes})");
        Assert.Equal(118, trace.Extra.Count);
        Assert.True(Utf8Bytes(json) <= OutboxTelemetrySink.MaxEnvelopeBytes);
        Assert.Equal(trace.Extra.Count, wireTrace.GetProperty("extra").EnumerateObject().Count());   // 해상도는 낮아져도 채널은 다 간다
        Assert.Equal(JsonValueKind.Object, payload.GetProperty("car").GetProperty("details").ValueKind);
    }

    // ---- 실제 매퍼·기록기로 1랩 트레이스 ----

    private LapTrace RecordSpaTrace()
    {
        var recorder = new LapTraceRecorder();
        var samples = (SpaLengthM / LapTraceRecorder.DefaultResolutionM) + 1;
        var header = new PacketHeader { PacketFormat = 2025, SessionUID = 1 };
        for (var i = 0; i < samples; i++)
        {
            var phase = (double)i / samples;
            Feed(recorder, F1ExtraChannels.FromMotion(Motion(phase)));
            Feed(recorder, F1ExtraChannels.FromMotionEx(MotionEx()));
            Feed(recorder, F1ExtraChannels.FromCarStatus(Status(phase)));
            Feed(recorder, F1ExtraChannels.FromLapData(LapDataAt(phase)));
            var telemetry = Telemetry(phase);
            Feed(recorder, F1ExtraChannels.FromCarTelemetry(telemetry, suggestedGear: 0));
            recorder.UpdatePosition(i * LapTraceRecorder.DefaultResolutionM, (int)(phase * SpaLapTimeMs));
            recorder.Record(_mapper.MapCarTelemetry(telemetry, header));
        }

        return Assert.IsType<LapTrace>(recorder.Flush());
    }

    private static void Feed(LapTraceRecorder recorder, IReadOnlyDictionary<string, double> channels) =>
        recorder.OnExtraChannels(new ExtraChannelsFrame("1", channels));

    private double Noise(double scale) => (_random.NextDouble() - 0.5) * 2 * scale;

    private Tyres<T> Wheels<T>(Func<T> value) => new() { RearLeft = value(), RearRight = value(), FrontLeft = value(), FrontRight = value() };

    private CarTelemetryData Telemetry(double phase) => new()
    {
        Speed = (ushort)(80 + _random.Next(260)),
        Throttle = (float)_random.NextDouble(),
        Steer = (float)Noise(1),
        Brake = (float)(_random.NextDouble() < 0.2 ? _random.NextDouble() : 0),
        Gear = (sbyte)(2 + _random.Next(7)),
        EngineRPM = (ushort)(9_000 + _random.Next(3_500)),
        IsDrsOn = phase is > 0.1 and < 0.2,
        RevLightsPercent = (byte)_random.Next(100),
        BrakesTemperature = Wheels(() => (ushort)(300 + _random.Next(700))),
        TyresSurfaceTemperature = Wheels(() => (byte)(85 + _random.Next(30))),
        TyresInnerTemperature = Wheels(() => (byte)(95 + _random.Next(15))),
        EngineTemperature = (ushort)(105 + _random.Next(10)),
        TyresPressure = Wheels(() => (float)(21.5 + Noise(1.5))),
        SurfaceType = Wheels(() => _random.NextDouble() < 0.1 ? F1Enums.Surface.RumbleStrip : F1Enums.Surface.Tarmac),
    };

    private CarStatusData Status(double phase) => new()
    {
        TractionControl = F1Enums.TractionOptions.Off,
        FuelMix = F1Enums.FuelMixOptions.Standard,
        FrontBrakeBias = 56,
        FuelInTank = (float)(24.4 - (phase * 1.7)),
        FuelRemainingLaps = (float)(3.21 - phase),
        EnginePowerICE = (float)(590_000 + Noise(30_000)),
        EnginePowerMGUK = (float)(120_000 + Noise(10_000)),
        ErsStoreEnergy = (float)(2_000_000 + Noise(1_900_000)),
        ErsDeployMode = F1Enums.ErsDeployMode.Medium,
        ErsHarvestedThisLapMGUK = (float)(phase * 1_000_000),
        ErsHarvestedThisLapMGUH = (float)(phase * 800_000),
        ErsDeployedThisLap = (float)(phase * 3_900_000),
    };

    private CarMotionData Motion(double phase) => new()
    {
        WorldPositionX = (float)(Math.Cos(phase * Math.Tau) * 900),
        WorldPositionY = (float)Noise(40),
        WorldPositionZ = (float)(Math.Sin(phase * Math.Tau) * 900),
        WorldVelocityX = (float)Noise(90),
        WorldVelocityY = (float)Noise(2),
        WorldVelocityZ = (float)Noise(90),
        GForceLateral = (float)Noise(5),
        GForceLongitudinal = (float)Noise(5),
        GForceVertical = (float)Noise(2),
        Yaw = (float)Noise(Math.PI),
        Pitch = (float)Noise(0.05),
        Roll = (float)Noise(0.05),
    };

    private MotionExDataPacket MotionEx() => new()
    {
        SuspensionPosition = Wheels(() => (float)(20 + Noise(15))),
        SuspensionVelocity = Wheels(() => (float)Noise(300)),
        SuspensionAcceleration = Wheels(() => (float)Noise(30_000)),
        WheelSpeed = Wheels(() => (float)(60 + Noise(30))),
        WheelSlipRatio = Wheels(() => (float)Noise(0.2)),
        WheelSlipAngle = Wheels(() => (float)Noise(0.15)),
        WheelLateralForce = Wheels(() => (float)Noise(8_000)),
        WheelLongitudinalForce = Wheels(() => (float)Noise(8_000)),
        HeightOfCOGAboveGround = (float)(0.28 + Noise(0.03)),
        LocalVelocityX = (float)Noise(3),
        LocalVelocityY = (float)Noise(1),
        LocalVelocityZ = (float)(60 + Noise(30)),
        AngularVelocityX = (float)Noise(0.5),
        AngularVelocityY = (float)Noise(1.5),
        AngularVelocityZ = (float)Noise(0.5),
        AngularAccelerationX = (float)Noise(20),
        AngularAccelerationY = (float)Noise(20),
        AngularAccelerationZ = (float)Noise(20),
        FrontWheelsAngle = (float)Noise(0.3),
        WheelVerticalForce = Wheels(() => (float)(4_000 + Noise(3_000))),
        FrontAeroHeight = (float)(0.03 + Noise(0.01)),
        RearAeroHeight = (float)(0.07 + Noise(0.02)),
        FrontRollAngle = (float)Noise(0.02),
        RearRollAngle = (float)Noise(0.02),
        ChassisYaw = (float)Noise(0.1),
        ChassisPitch = (float)Noise(0.03),
        WheelsCamper = Wheels(() => (float)(-0.06 + Noise(0.01))),
        WheelsCamperGain = Wheels(() => (float)Noise(0.01)),
    };

    private LapData LapDataAt(double phase) => new()
    {
        CarPosition = (byte)(1 + _random.Next(20)),
        DeltaToCarInFrontInMS = (ushort)_random.Next(9_999),
        DeltaToRaceLeaderInMS = (ushort)_random.Next(59_999),
        SafetyCarDelta = (float)Noise(phase),
    };

    // ---- 상세(실제 매퍼 함수 + Core 다듬기) ----

    private IReadOnlyDictionary<string, object?> RealisticDetails()
    {
        var session = new SessionDataPacket
        {
            NumMarshalZones = 21,
            NumWeatherForecastSamples = 56,
            NumSessionsInWeekend = 12,
            Sector2LapDistanceStart = 2_300.5f,
            Sector3LapDistanceStart = 5_100.25f,
        };
        var tyreSets = new TyreSetsDataPacket { FittedIndex = 3 };
        var events = Enumerable.Range(0, EventCount)
            .Select(i => new LapEventEntry("OVTK", i * 2_500, new Dictionary<string, object?> { ["overtakingVehicleIndex"] = (byte)i, ["beingOvertakenVehicleIndex"] = (byte)(i + 1) }))
            .ToArray();

        return new Dictionary<string, object?>
        {
            [F1DetailSections.Setup] = DetailValues.Sanitize(F1DetailSections.FromSetup(new CarSetupData { FrontCamber = -3.5f, TyresPressure = Wheels(() => 22.4f) }, 30f)),
            [F1DetailSections.Damage] = DetailValues.Sanitize(F1DetailSections.FromDamage(default)),
            [F1DetailSections.Status] = DetailValues.Sanitize(F1DetailSections.FromStatus(new CarStatusData { MaxRPM = 13_000, EnginePowerICE = 592_123.4f })),
            [F1DetailSections.TyreSets] = DetailValues.Sanitize(F1DetailSections.FromTyreSets(tyreSets)),
            [F1DetailSections.TimeTrial] = DetailValues.Sanitize(F1DetailSections.FromTimeTrial(default)),
            [F1DetailSections.Session] = DetailValues.Sanitize(F1SessionDetails.From(session)),
            [F1DetailSections.Participant] = DetailValues.Sanitize(F1DetailSections.FromParticipant(default, 0, "S. LIM")),
            [F1DetailSections.LapData] = DetailValues.Sanitize(F1DetailSections.FromLapData(default, 0, default)),
            [LapDetailsTracker.EventsKey] = events,
            [LapDetailsTracker.SessionHistoryKey] = new LapHistoryEntry(5, 106_123, 31_456, 44_789, 29_878, true, true, true, true),
        };
    }

    private static LapFinished Lap(LapTrace trace, IReadOnlyDictionary<string, object?> details) => new(
        SessionRef: "1844674407370955161",
        LapNumber: 5,
        LapTimeMs: 106_123,
        Sectors: [new LapSectorDto(1, 31_456), new LapSectorDto(2, 44_789), new LapSectorDto(3, 29_878)],
        IsValid: true,
        IsOutOrInLap: false,
        TrackId: 10,
        SessionType: SessionType.Race,
        GameMode: GameMode.DriverCareer,
        Car: new LapCarSnapshot(
            1, 16, 18, 3,
            new WheelSet<float>(27.5f, 14f, 20f, 14f), new WheelSet<float>(31f, 18f, 24f, 18f),
            new WheelSet<int>(0, 0, 0, 0), new WheelSet<int>(0, 0, 0, 0),
            0, 10, 0, 0, 0, 20, 10, 30, 24.4f, 22.7f, 13.1f, 1_494_000, 988_000, 2_100_000, 1_600_000, details),
        Conditions: new LapConditions(Weather.Overcast, 18, 27, 35),
        Trace: trace);

    private static int Utf8Bytes(string json) => Encoding.UTF8.GetByteCount(json);
}
