using F1Game.UDP.Data;
using F1Game.UDP.Packets;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// Session History(11)·Lap Positions(15) → 세션 기록 프레임(D-49, docs/15 §8). 개수 칸(<c>NumLaps</c>·<c>NumberOfLaps</c>)을 넘는 배열 칸은 쓰레기라 보지 않는다.
/// Lap Positions의 <c>StartingLap</c>은 0부터 세는 랩 위치라 랩 번호 = <c>StartingLap + 1 + i</c>다.
/// </summary>
internal static class F1SessionHistory
{
    public static SessionHistoryFrame Map(SessionHistoryDataPacket packet)
    {
        var laps = packet.LapHistoryData.AsReadOnlySpan();
        var count = Math.Min((int)packet.NumLaps, laps.Length);
        var entries = new LapHistoryEntry[count];
        for (var i = 0; i < count; i++)
        {
            entries[i] = ToEntry(lapNumber: i + 1, laps[i]);
        }

        return new SessionHistoryFrame(
            packet.Header.SessionUID.ToString(),
            packet.CarIndex,
            IsPlayer: packet.CarIndex == packet.Header.PlayerCarIndex,
            entries);
    }

    public static LapPositionsFrame Map(LapPositionsDataPacket packet)
    {
        var laps = packet.PositionsPerLapForVehicle.AsReadOnlySpan();
        var count = Math.Min((int)packet.NumberOfLaps, laps.Length);
        var positions = new IReadOnlyList<int>[count];
        for (var i = 0; i < count; i++)
        {
            var lap = laps[i];
            positions[i] = ToInts(lap.AsReadOnlySpan());
        }

        return new LapPositionsFrame(packet.Header.SessionUID.ToString(), FirstLapNumber: packet.StartingLap + 1, positions);
    }

    private static LapHistoryEntry ToEntry(int lapNumber, LapHistoryData lap) => new(
        LapNumber: lapNumber,
        LapTimeMs: lap.LapTimeInMS > int.MaxValue ? int.MaxValue : (int)lap.LapTimeInMS,
        Sector1TimeMs: F1DetailSections.ToMilliseconds(lap.Sector1TimeMinutes, lap.Sector1TimeInMS),
        Sector2TimeMs: F1DetailSections.ToMilliseconds(lap.Sector2TimeMinutes, lap.Sector2TimeInMS),
        Sector3TimeMs: F1DetailSections.ToMilliseconds(lap.Sector3TimeMinutes, lap.Sector3TimeInMS),
        LapValid: lap.LapValidBitFlags.HasFlag(F1Enums.LapValid.LapValid),
        Sector1Valid: lap.LapValidBitFlags.HasFlag(F1Enums.LapValid.Sector1Valid),
        Sector2Valid: lap.LapValidBitFlags.HasFlag(F1Enums.LapValid.Sector2Valid),
        Sector3Valid: lap.LapValidBitFlags.HasFlag(F1Enums.LapValid.Sector3Valid));

    private static int[] ToInts(ReadOnlySpan<byte> values)
    {
        var ints = new int[values.Length];
        for (var i = 0; i < values.Length; i++)
        {
            ints[i] = values[i];
        }

        return ints;
    }
}
