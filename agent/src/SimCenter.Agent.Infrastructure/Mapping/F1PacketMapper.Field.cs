using F1Game.UDP.Data;
using F1Game.UDP.Packets;
using SimCenter.Agent.Core.Telemetry.Frames;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// 모든 차 프레임(트랙 형상 표본의 원천, 헌장 Agent Rules 예외): Motion·Lap Data·Car Telemetry의 22칸을 그대로 옮긴다.
/// 플레이어 칸이 없어도(관전 중) 낸다. 서버로 가는 것은 수집기가 추린 표본뿐이다.
/// </summary>
public sealed partial class F1PacketMapper
{
    private const int MillisecondsPerSecondF = 1000;

    /// <summary>바퀴 하나의 노면 값 비트 수·마스크(4비트 × 4 묶음).</summary>
    private const int SurfaceBits = 4;
    private const int SurfaceMask = 0xF;

    /// <summary>상태 바이트: 하위 3비트 = Driver Status, 그 위 2비트 = Pit Status(게임 원시 값).</summary>
    private const int DriverStatusMask = 0x7;
    private const int PitStatusMask = 0x3;
    private const int PitStatusShift = 3;

    private static FieldPositionsFrame MapFieldPositions(MotionDataPacket packet)
    {
        var cars = packet.CarMotionData.AsReadOnlySpan();
        var positions = new FieldPosition[cars.Length];
        for (var i = 0; i < cars.Length; i++)
        {
            positions[i] = new FieldPosition(cars[i].WorldPositionX, cars[i].WorldPositionZ);
        }

        return new FieldPositionsFrame(
            packet.Header.SessionUID.ToString(),
            packet.Header.FrameIdentifier,
            (int)Math.Round(packet.Header.SessionTime * MillisecondsPerSecondF),
            positions);
    }

    private static FieldLapStatesFrame MapFieldLapStates(LapDataPacket packet)
    {
        var laps = packet.LapData.AsReadOnlySpan();
        var states = new FieldLapState[laps.Length];
        for (var i = 0; i < laps.Length; i++)
        {
            var lap = laps[i];
            var isOnTrack = lap.ResultStatus == F1Enums.ResultStatus.Active
                            && lap.DriverStatus != F1Enums.DriverStatus.InGarage
                            && lap.PitStatus == F1Enums.PitStatus.None;
            var status = (byte)(((int)lap.DriverStatus & DriverStatusMask) | (((int)lap.PitStatus & PitStatusMask) << PitStatusShift));
            states[i] = new FieldLapState(lap.LapDistance, isOnTrack, status);
        }

        return new FieldLapStatesFrame(packet.Header.SessionUID.ToString(), packet.Header.FrameIdentifier, states);
    }

    private static FieldSurfacesFrame MapFieldSurfaces(CarTelemetryDataPacket packet)
    {
        var cars = packet.CarTelemetryData.AsReadOnlySpan();
        var surfaces = new ushort[cars.Length];
        for (var i = 0; i < cars.Length; i++)
        {
            surfaces[i] = PackSurfaces(cars[i].SurfaceType);
        }

        return new FieldSurfacesFrame(packet.Header.SessionUID.ToString(), packet.Header.FrameIdentifier, surfaces);
    }

    /// <summary>바퀴 4개 노면을 4비트씩 묶는다(FL·FR·RL·RR 순, 하위 비트부터).</summary>
    internal static ushort PackSurfaces(Tyres<F1Enums.Surface> wheels)
        => (ushort)(((int)wheels.FrontLeft & SurfaceMask)
                    | (((int)wheels.FrontRight & SurfaceMask) << SurfaceBits)
                    | (((int)wheels.RearLeft & SurfaceMask) << (SurfaceBits * 2))
                    | (((int)wheels.RearRight & SurfaceMask) << (SurfaceBits * 3)));
}
