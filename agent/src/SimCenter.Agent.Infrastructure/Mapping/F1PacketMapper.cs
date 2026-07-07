using F1Game.UDP;
using F1Game.UDP.Data;
using F1Game.UDP.Packets;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;
using F1Enums = F1Game.UDP.Enums;
using F1Events = F1Game.UDP.Events;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// F1Game.UDP 패킷을 Agent.Core의 게임중립 프레임으로 매핑한다(D-20 경계).
/// MVP 관심 패킷만 처리(Session/LapData/Event), 나머지는 무시(YAGNI, docs/06 §2.2).
/// 개별 Map* 메서드는 구성 가능한 패킷 구조체를 받아 단위테스트가 가능하다.
/// </summary>
public sealed class F1PacketMapper
{
    private static readonly IReadOnlyList<ITelemetryFrame> Empty = Array.Empty<ITelemetryFrame>();

    private readonly int _expectedPacketFormat;

    public F1PacketMapper(int expectedPacketFormat) => _expectedPacketFormat = expectedPacketFormat;

    /// <summary>원시 데이터그램을 파싱해 프레임으로 매핑한다. 파싱 실패/무관 패킷은 빈 목록.</summary>
    public IReadOnlyList<ITelemetryFrame> Map(ReadOnlySpan<byte> datagram)
    {
        UnionPacket packet;
        try
        {
            packet = PacketReader.ToPacket(datagram);
        }
        catch (Exception ex) when (ex is ParsingException or NotEnoughBytesException or InvalidPacketTypeException)
        {
            return Empty;
        }

        return Map(packet);
    }

    /// <summary>파싱된 UnionPacket을 프레임으로 매핑(버전 검증 포함).</summary>
    public IReadOnlyList<ITelemetryFrame> Map(UnionPacket packet)
    {
        // 버전 가드: 기대 포맷이 아니면 스킵(다른 연식 패킷, D-20/OCP).
        if (packet.Header.PacketFormat != _expectedPacketFormat)
        {
            return Empty;
        }

        switch (packet.PacketType)
        {
            case F1Enums.PacketType.Session when packet.TryGetSessionDataPacket(out var session):
                return new ITelemetryFrame[] { MapSession(session) };

            case F1Enums.PacketType.LapData when packet.TryGetLapDataPacket(out var lapPacket):
            {
                var index = packet.Header.PlayerCarIndex;
                var cars = lapPacket.LapData.AsReadOnlySpan();
                if (index >= cars.Length)
                {
                    return Empty;
                }

                return new ITelemetryFrame[] { MapLap(cars[index], packet.Header) };
            }

            case F1Enums.PacketType.Event when packet.TryGetEventDataPacket(out var eventPacket):
            {
                var marker = MapEvent(eventPacket);
                return marker is null ? Empty : new ITelemetryFrame[] { marker };
            }

            default:
                return Empty;
        }
    }

    public SessionFrame MapSession(SessionDataPacket packet) => new(
        SessionRef: packet.Header.SessionUID.ToString(),
        TrackId: (int)packet.Track,
        SessionType: MapSessionType(packet.SessionType),
        PacketFormat: packet.Header.PacketFormat);

    public LapFrame MapLap(LapData lap, PacketHeader header) => new(
        SessionRef: header.SessionUID.ToString(),
        CurrentLapNumber: lap.CurrentLapNum,
        CurrentSector: (int)lap.Sector,
        Sector1TimeMs: (lap.Sector1TimeInMinutes * 60_000) + lap.Sector1TimeInMS,
        Sector2TimeMs: (lap.Sector2TimeInMinutes * 60_000) + lap.Sector2TimeInMS,
        LastLapTimeMs: (int)lap.LastLapTimeInMS,
        IsCurrentLapInvalid: lap.IsCurrentLapInvalid,
        IsOutOrInLap: lap.DriverStatus is F1Enums.DriverStatus.InLap or F1Enums.DriverStatus.OutLap
                      || lap.PitStatus != F1Enums.PitStatus.None);

    public EventMarker? MapEvent(EventDataPacket packet) => packet.EventDetails.EventType switch
    {
        F1Events.EventType.SessionStarted => new EventMarker(packet.Header.SessionUID.ToString(), SessionBoundary.Start),
        F1Events.EventType.SessionEnded => new EventMarker(packet.Header.SessionUID.ToString(), SessionBoundary.End),
        _ => null,
    };

    /// <summary>F1 세부 세션 모드를 게임중립 5종으로 정규화(D-16). 실시간 랭킹은 TimeTrial만.</summary>
    private static SessionType MapSessionType(F1Enums.SessionType type) => type switch
    {
        F1Enums.SessionType.TimeTrial => SessionType.TimeTrial,
        >= F1Enums.SessionType.Practice1 and <= F1Enums.SessionType.ShortPractice => SessionType.Practice,
        >= F1Enums.SessionType.Qualifying1 and <= F1Enums.SessionType.OneShotQualifying => SessionType.Qualifying,
        >= F1Enums.SessionType.SprintShootout1 and <= F1Enums.SessionType.OneShotSprintShootout => SessionType.Qualifying,
        >= F1Enums.SessionType.Race and <= F1Enums.SessionType.Race3 => SessionType.Race,
        _ => SessionType.Unknown,
    };
}
