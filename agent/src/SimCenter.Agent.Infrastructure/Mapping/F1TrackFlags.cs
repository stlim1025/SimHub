using F1Game.UDP.Packets;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// Session 패킷의 마셜 구역 깃발 → 옐로 플래그가 나온 섹터(<see cref="TrackFlagsFrame"/>). 구역 시작(랩 비율)을 트랙 길이로 거리로 바꿔
/// 섹터 2·3 시작 거리와 견준다. 섹터 시작 거리가 비었거나 트랙 밖이면 랩을 셋으로 나눈다.
/// </summary>
internal static class F1TrackFlags
{
    /// <summary>마셜 구역 깃발 원시 값: 옐로.</summary>
    private const int YellowZoneFlag = 3;

    private const int FirstSector = 1;
    private const int SecondSector = 2;
    private const int ThirdSector = 3;

    /// <summary>섹터 시작 거리를 모를 때 쓰는 랩 비율(섹터 2·3 시작).</summary>
    private const float FallbackSector2Start = 1f / 3f;
    private const float FallbackSector3Start = 2f / 3f;

    public static TrackFlagsFrame From(SessionDataPacket packet) =>
        new(packet.Header.SessionUID.ToString(), YellowSectors(packet));

    private static int[] YellowSectors(SessionDataPacket packet)
    {
        var zones = packet.MarshalZones.AsReadOnlySpan();
        var count = Math.Min((int)packet.NumMarshalZones, zones.Length);
        float length = packet.TrackLength;
        var known = length > 0
            && packet.Sector2LapDistanceStart > 0
            && packet.Sector3LapDistanceStart > packet.Sector2LapDistanceStart
            && packet.Sector3LapDistanceStart < length;
        var sector2 = known ? packet.Sector2LapDistanceStart / length : FallbackSector2Start;
        var sector3 = known ? packet.Sector3LapDistanceStart / length : FallbackSector3Start;

        var sectors = new SortedSet<int>();
        for (var i = 0; i < count; i++)
        {
            if ((int)zones[i].ZoneFlag != YellowZoneFlag)
            {
                continue;
            }

            var start = zones[i].ZoneStart;
            sectors.Add(start < sector2 ? FirstSector : start < sector3 ? SecondSector : ThirdSector);
        }

        return [.. sectors];
    }
}
