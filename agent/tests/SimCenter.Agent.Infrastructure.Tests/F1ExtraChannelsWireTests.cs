using System.Buffers.Binary;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Tests;

/// <summary>
/// 트레이스 extra 채널(D-49, docs/15 §8)을 F1 25 규격 크기의 합성 바이트로 확인한다 — 오프셋은 F1 25 UDP 스펙,
/// 바퀴 배열은 RL·RR·FL·FR 순서로 다른 값을 넣어 이름(FL·FR·RL·RR)으로 옮겨졌는지 본다. 단위 변환(rad → 도, m → mm, 비 → %)도 고정한다.
/// </summary>
public class F1ExtraChannelsWireTests
{
    private const int Format = 2025;
    private const int PacketIdOffset = 6;
    private const int PlayerCarIndexOffset = 27;
    private const int HeaderSize = 29;
    private const byte PlayerIndex = 2;

    private const int MotionPacketSize = 1349;
    private const int MotionCarSize = 60;
    private const int LapDataPacketSize = 1285;
    private const int LapDataCarSize = 57;
    private const int CarTelemetryPacketSize = 1352;
    private const int CarTelemetryCarSize = 60;
    private const int CarStatusPacketSize = 1239;
    private const int CarStatusCarSize = 55;
    private const int MotionExPacketSize = 273;

    private static readonly F1PacketMapper Mapper = new(Format, NullLogger<F1PacketMapper>.Instance);

    [Fact]
    public void CarTelemetry_ExtraChannels_ComeBeforeTelemetryFrame_WithWheelNames()
    {
        var datagram = Datagram(F1Enums.PacketType.CarTelemetry, CarTelemetryPacketSize);
        var car = HeaderSize + (PlayerIndex * CarTelemetryCarSize);
        datagram[car + 14] = 35;                                                    // m_clutch
        datagram[car + 18] = 1;                                                     // m_drs
        datagram[car + 19] = 87;                                                    // m_revLightsPercent
        WriteUInt16s(datagram, car + 22, 501, 502, 503, 504);                       // m_brakesTemperature[RL, RR, FL, FR]
        WriteBytes(datagram, car + 30, 91, 92, 93, 94);                             // m_tyresSurfaceTemperature
        WriteBytes(datagram, car + 34, 101, 102, 103, 104);                         // m_tyresInnerTemperature
        WriteUInt16s(datagram, car + 38, 112);                                      // m_engineTemperature
        WriteFloats(datagram, car + 40, 22.111f, 22.222f, 23.333f, 23.444f);        // m_tyresPressure
        WriteBytes(datagram, car + 56, 0, 1, 4, 7);                                 // m_surfaceType
        datagram[CarTelemetryPacketSize - 1] = 6;                                   // m_suggestedGear(패킷 끝)

        var frames = Mapper.Map(datagram);

        Assert.Equal(3, frames.Count);
        var extra = Assert.IsType<ExtraChannelsFrame>(frames[0]).Channels;   // 같은 패킷의 값이 같은 칸에 찍히도록 먼저
        Assert.IsType<CarTelemetryFrame>(frames[1]);
        var surfaces = Assert.IsType<FieldSurfacesFrame>(frames[2]);         // 모든 차 노면: FL·FR·RL·RR 4비트씩
        Assert.Equal(4 | (7 << 4) | (0 << 8) | (1 << 12), surfaces.Surfaces[PlayerIndex]);
        Assert.Equal(35, extra["clutch"]);
        Assert.Equal(1, extra["drs"]);
        Assert.Equal(87, extra["revLightsPercent"]);
        AssertWheels(extra, "brakeTemp", fl: 503, fr: 504, rl: 501, rr: 502);
        AssertWheels(extra, "tyreSurfaceTemp", fl: 93, fr: 94, rl: 91, rr: 92);
        AssertWheels(extra, "tyreInnerTemp", fl: 103, fr: 104, rl: 101, rr: 102);
        Assert.Equal(112, extra["engineTemp"]);
        AssertWheels(extra, "tyrePressure", fl: 23.33, fr: 23.44, rl: 22.11, rr: 22.22);
        AssertWheels(extra, "surfaceType", fl: 4, fr: 7, rl: 0, rr: 1);
        Assert.Equal(6, extra["suggestedGear"]);
    }

    [Fact]
    public void CarStatus_ExtraChannels_FollowStatusFrame()
    {
        var datagram = Datagram(F1Enums.PacketType.CarStatus, CarStatusPacketSize);
        var car = HeaderSize + (PlayerIndex * CarStatusCarSize);
        WriteBytes(datagram, car, 2, 1, 3, 56, 1);                       // TC, ABS, 연료 믹스, 앞 브레이크 바이어스, 피트 리미터
        WriteFloats(datagram, car + 5, 24.567f);                         // m_fuelInTank
        WriteFloats(datagram, car + 13, -0.25f);                         // m_fuelRemainingLaps
        datagram[car + 22] = 1;                                          // m_drsAllowed
        datagram[car + 28] = 3;                                          // m_vehicleFiaFlags(노랑)
        WriteFloats(datagram, car + 29, 590_123.4f, 120_000.6f);         // m_enginePowerICE, m_enginePowerMGUK
        WriteFloats(datagram, car + 37, 3_456_789f);                     // m_ersStoreEnergy
        datagram[car + 41] = 3;                                          // m_ersDeployMode(Overtake)
        WriteFloats(datagram, car + 42, 100_000f, 50_000f, 300_000f);    // 이 랩 회수 MGU-K·MGU-H, 배포

        var frames = Mapper.Map(datagram);

        Assert.IsType<CarStatusFrame>(frames[0]);
        var extra = Assert.Single(frames.OfType<ExtraChannelsFrame>()).Channels;
        Assert.Equal(new[] { 2d, 1d, 3d, 56d, 1d }, new[] { extra["tractionControl"], extra["antiLockBrakes"], extra["fuelMix"], extra["frontBrakeBias"], extra["pitLimiter"] });
        Assert.Equal(24.57, extra["fuelInTank"]);
        Assert.Equal(-0.25, extra["fuelRemainingLaps"]);
        Assert.Equal(1, extra["drsAllowed"]);
        Assert.Equal(3, extra["vehicleFiaFlag"]);
        Assert.Equal(590_123, extra["enginePowerIce"]);
        Assert.Equal(120_001, extra["enginePowerMguk"]);
        Assert.Equal(3_456_789, extra["ersStoreEnergy"]);
        Assert.Equal(3, extra["ersDeployMode"]);
        Assert.Equal(100_000, extra["ersHarvestedThisLapMguk"]);
        Assert.Equal(50_000, extra["ersHarvestedThisLapMguh"]);
        Assert.Equal(300_000, extra["ersDeployedThisLap"]);
    }

    [Fact]
    public void Motion_PlayerCar_MapsPositionGForceAndAttitudeInDegrees()
    {
        var datagram = Datagram(F1Enums.PacketType.Motion, MotionPacketSize);
        var car = HeaderSize + (PlayerIndex * MotionCarSize);
        WriteFloats(datagram, car, -523.456f, 12.04f, 800.96f, 70.123f, -0.5f, 3.333f);   // 월드 위치 X·Y·Z, 속도 X·Y·Z
        WriteFloats(datagram, car + 36, 3.456f, -4.2f, 1.01f);                           // G-force 횡·종·수직
        WriteFloats(datagram, car + 48, (float)Math.PI / 2, -0.1f, 0.05f);               // 요·피치·롤(rad)

        var frames = Mapper.Map(datagram);

        Assert.Equal(2, frames.Count);
        var extra = Assert.IsType<ExtraChannelsFrame>(frames[0]).Channels;
        var field = Assert.IsType<FieldPositionsFrame>(frames[1]);   // 모든 차 위치(트랙 형상 표본용)는 뒤에
        Assert.Equal(-523.456f, field.Cars[PlayerIndex].X);
        Assert.Equal(800.96f, field.Cars[PlayerIndex].Z);
        Assert.Equal(-523.5, extra["worldPosX"]);   // 위치는 소수 첫째 자리(10cm)
        Assert.Equal(12, extra["worldPosY"]);
        Assert.Equal(801, extra["worldPosZ"]);
        Assert.Equal(70.12, extra["worldVelX"]);
        Assert.Equal(-0.5, extra["worldVelY"]);
        Assert.Equal(3.33, extra["worldVelZ"]);
        Assert.Equal(3.46, extra["gForceLateral"]);
        Assert.Equal(-4.2, extra["gForceLongitudinal"]);
        Assert.Equal(1.01, extra["gForceVertical"]);
        Assert.Equal(90, extra["yawDeg"]);
        Assert.Equal(-5.73, extra["pitchDeg"]);
        Assert.Equal(2.86, extra["rollDeg"]);
    }

    [Fact]
    public void Motion_PlayerIndexBeyondSlots_KeepsOnlyFieldPositions()
    {
        var datagram = Datagram(F1Enums.PacketType.Motion, MotionPacketSize, playerIndex: byte.MaxValue);

        Assert.IsType<FieldPositionsFrame>(Assert.Single(Mapper.Map(datagram)));
    }

    [Fact]
    public void MotionEx_MapsWheelArraysByNameAndConvertsUnits()
    {
        var datagram = Datagram(F1Enums.PacketType.MotionEx, MotionExPacketSize);
        WriteFloats(datagram, 29, 11f, 12f, 13f, 14f);                                // m_suspensionPosition[RL, RR, FL, FR]
        WriteFloats(datagram, 61, 1001f, 1002f, 1003f, 1004f);                        // m_suspensionAcceleration
        WriteFloats(datagram, 77, 71.1f, 71.2f, 71.3f, 71.4f);                        // m_wheelSpeed
        WriteFloats(datagram, 93, 0.011f, 0.022f, 0.033f, 0.044f);                    // m_wheelSlipRatio
        WriteFloats(datagram, 109, 0.01f, 0.02f, 0.03f, 0.04f);                       // m_wheelSlipAngle(rad)
        WriteFloats(datagram, 125, -3001.4f, 3002.6f, -3003f, 3004f);                 // m_wheelLatForce
        WriteFloats(datagram, 157, 0.2512f);                                          // m_heightOfCOGAboveGround(m)
        WriteFloats(datagram, 161, 1.5f, -0.25f, 80.123f);                            // m_localVelocity X·Y·Z
        WriteFloats(datagram, 197, -0.2f);                                            // m_frontWheelsAngle(rad)
        WriteFloats(datagram, 201, 5001f, 5002f, 5003f, 5004f);                       // m_wheelVertForce
        WriteFloats(datagram, 217, 0.0312f, 0.0745f);                                 // m_frontAeroHeight, m_rearAeroHeight(m)
        WriteFloats(datagram, 233, 0.01f, -0.02f);                                    // m_chassisYaw, m_chassisPitch(rad)
        WriteFloats(datagram, 241, -0.061f, -0.062f, -0.063f, -0.064f);               // m_wheelCamber(rad)

        var extra = Assert.IsType<ExtraChannelsFrame>(Assert.Single(Mapper.Map(datagram))).Channels;

        AssertWheels(extra, "suspensionPosition", fl: 13, fr: 14, rl: 11, rr: 12);
        AssertWheels(extra, "suspensionAcceleration", fl: 1003, fr: 1004, rl: 1001, rr: 1002);
        AssertWheels(extra, "wheelSpeed", fl: 71.3, fr: 71.4, rl: 71.1, rr: 71.2);
        AssertWheels(extra, "wheelSlipRatioPct", fl: 3.3, fr: 4.4, rl: 1.1, rr: 2.2);
        AssertWheels(extra, "wheelSlipAngleDeg", fl: 1.72, fr: 2.29, rl: 0.57, rr: 1.15);
        AssertWheels(extra, "wheelLatForce", fl: -3003, fr: 3004, rl: -3001, rr: 3003);
        AssertWheels(extra, "wheelVertForce", fl: 5003, fr: 5004, rl: 5001, rr: 5002);
        AssertWheels(extra, "wheelCamberDeg", fl: -3.61, fr: -3.67, rl: -3.5, rr: -3.55);
        Assert.Equal(251.2, extra["heightOfCogMm"]);
        Assert.Equal(new[] { 1.5, -0.25, 80.12 }, new[] { extra["localVelX"], extra["localVelY"], extra["localVelZ"] });
        Assert.Equal(-11.46, extra["frontWheelsAngleDeg"]);
        Assert.Equal(31.2, extra["frontAeroHeightMm"]);
        Assert.Equal(74.5, extra["rearAeroHeightMm"]);
        Assert.Equal(0.57, extra["chassisYawDeg"]);
        Assert.Equal(-1.15, extra["chassisPitchDeg"]);
    }

    [Fact]
    public void LapData_ExtraChannels_FollowLapFrame()
    {
        var datagram = Datagram(F1Enums.PacketType.LapData, LapDataPacketSize);
        var car = HeaderSize + (PlayerIndex * LapDataCarSize);
        WriteUInt16s(datagram, car + 14, 1_234);    // m_deltaToCarInFrontMSPart
        datagram[car + 16] = 1;                     // m_deltaToCarInFrontMinutesPart
        WriteUInt16s(datagram, car + 17, 500);      // m_deltaToRaceLeaderMSPart
        datagram[car + 19] = 2;                     // m_deltaToRaceLeaderMinutesPart
        WriteFloats(datagram, car + 28, -1.456f);   // m_safetyCarDelta
        datagram[car + 32] = 4;                     // m_carPosition
        datagram[car + 33] = 3;                     // m_currentLapNum

        var frames = Mapper.Map(datagram);

        Assert.Equal(3, Assert.IsType<LapFrame>(frames[0]).CurrentLapNumber);   // 랩 프레임이 먼저(앞 랩을 확정한 뒤 새 값)
        var extra = Assert.Single(frames.OfType<ExtraChannelsFrame>()).Channels;
        Assert.Equal(4, extra["carPosition"]);
        Assert.Equal(61_234, extra["deltaToCarInFrontMs"]);
        Assert.Equal(120_500, extra["deltaToRaceLeaderMs"]);
        Assert.Equal(-1.46, extra["safetyCarDelta"]);
    }

    [Fact]
    public void AllExtraChannels_HaveValidNames_AndFitTheLimit()
    {
        var names = new[]
            {
                Mapper.Map(Datagram(F1Enums.PacketType.CarTelemetry, CarTelemetryPacketSize)),
                Mapper.Map(Datagram(F1Enums.PacketType.CarStatus, CarStatusPacketSize)),
                Mapper.Map(Datagram(F1Enums.PacketType.Motion, MotionPacketSize)),
                Mapper.Map(Datagram(F1Enums.PacketType.MotionEx, MotionExPacketSize)),
                Mapper.Map(Datagram(F1Enums.PacketType.LapData, LapDataPacketSize)),
            }
            .SelectMany(frames => frames.OfType<ExtraChannelsFrame>())
            .SelectMany(frame => frame.Channels.Keys)
            .ToList();

        Assert.Equal(names.Count, names.Distinct().Count());   // 패킷끼리 이름이 겹치지 않는다
        Assert.Equal(118, names.Count);                        // 카탈로그(f1_25_udp_spec.md §6)와 같은 수
        Assert.True(names.Count <= SimCenter.Agent.Core.Analysis.TraceExtraChannels.MaxChannels);
        Assert.All(names, name => Assert.Matches("^[A-Za-z0-9]{1,40}$", name));
    }

    private static void AssertWheels(IReadOnlyDictionary<string, double> extra, string name, double fl, double fr, double rl, double rr) =>
        Assert.Equal(new[] { fl, fr, rl, rr }, new[] { extra[name + "FL"], extra[name + "FR"], extra[name + "RL"], extra[name + "RR"] });

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

    private static void WriteBytes(byte[] datagram, int offset, params byte[] values) => values.CopyTo(datagram, offset);
}
