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
/// 관심 패킷만 처리(Session/LapData/Event, P7: Participants/FinalClassification), 나머지는 무시(YAGNI, docs/06 §2.2).
/// 개별 Map* 메서드는 구성 가능한 패킷 구조체를 받아 단위테스트가 가능하다.
/// </summary>
public sealed class F1PacketMapper
{
    private const int MillisecondsPerSecond = 1000;

    /// <summary>F1 25가 한 차에 기록하는 타이어 스틴트 최대 수(<c>Array8</c>의 칸 수, 12 §5.2).</summary>
    private const int MaxTyreStints = 8;

    /// <summary>
    /// 순위표 행으로 보내는 <c>Position</c>의 상한. 백엔드 <c>SessionClassificationValidator.MaxClassificationEntries</c>(32)와 같다 —
    /// 이를 넘는 값이 한 칸이라도 실리면 백엔드가 세션 전체를 Reject하므로 그런 칸은 보내지 않는다.
    /// </summary>
    private const int MaxClassifiedPosition = 32;

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

            case F1Enums.PacketType.Participants when packet.TryGetParticipantsDataPacket(out var participants):
                return new ITelemetryFrame[] { MapParticipants(participants) };

            case F1Enums.PacketType.FinalClassification when packet.TryGetFinalClassificationDataPacket(out var classification):
                return new ITelemetryFrame[] { MapClassification(classification) };

            default:
                return Empty;
        }
    }

    public SessionFrame MapSession(SessionDataPacket packet) => new(
        SessionRef: packet.Header.SessionUID.ToString(),
        TrackId: (int)packet.Track,
        SessionType: MapSessionType(packet.SessionType),
        PacketFormat: packet.Header.PacketFormat,
        SessionKind: F1EnumMaps.ToSessionKind(packet.SessionType),
        GameMode: F1EnumMaps.ToGameMode(packet.GameMode),
        SeasonLinkId: packet.SeasonLinkIdentifier,
        WeekendLinkId: packet.WeekendLinkIdentifier,
        SessionLinkId: packet.SessionLinkIdentifier,
        TotalLaps: packet.TotalLaps,
        AiDifficulty: packet.AIDifficulty,
        IsNetworkGame: packet.IsNetworkGame);

    /// <summary>참가자 배열 전체를 carIndex 순서로 매핑한다(12 §5.2). 사람(네트워크) 드라이버는 <c>GameDriverId = null</c>.</summary>
    public ParticipantsFrame MapParticipants(ParticipantsDataPacket packet)
    {
        var slots = packet.Participants.AsReadOnlySpan();
        var participants = new List<ParticipantInfo>(slots.Length);
        for (var carIndex = 0; carIndex < slots.Length; carIndex++)
        {
            var slot = slots[carIndex];
            participants.Add(new ParticipantInfo(
                CarIndex: carIndex,
                Name: CutAtFirstNul(slot.Name),
                GameDriverId: slot.Driver == F1Enums.Driver.NetworkHuman ? null : (int)slot.Driver,
                TeamId: (int)slot.Team,
                RaceNumber: slot.RaceNumber,
                IsAiControlled: slot.IsAiControlled));
        }

        return new ParticipantsFrame(packet.Header.SessionUID.ToString(), participants);
    }

    /// <summary>최종 순위표를 매핑한다. 빈 그리드 칸(Invalid·Inactive 또는 Position 0)은 뺀다(12 §5.2).</summary>
    public ClassificationFrame MapClassification(FinalClassificationDataPacket packet)
    {
        var slots = packet.ClassificationData.AsReadOnlySpan();
        var rows = new List<ClassificationRow>(slots.Length);
        for (var carIndex = 0; carIndex < slots.Length; carIndex++)
        {
            var slot = slots[carIndex];
            if (IsEmptySlot(slot))
            {
                continue;
            }

            rows.Add(MapClassificationRow(carIndex, slot));
        }

        return new ClassificationFrame(packet.Header.SessionUID.ToString(), packet.Header.PlayerCarIndex, rows);
    }

    /// <summary>Invalid·Inactive 칸, 순위 0, 또는 백엔드가 받는 상한(<see cref="MaxClassifiedPosition"/>)을 넘는 쓰레기 순위는 빈 칸이다.</summary>
    private static bool IsEmptySlot(FinalClassificationData slot) =>
        slot.ResultStatus is F1Enums.ResultStatus.Invalid or F1Enums.ResultStatus.Inactive
        || slot.Position == 0
        || slot.Position > MaxClassifiedPosition;

    private static ClassificationRow MapClassificationRow(int carIndex, FinalClassificationData slot) => new(
        CarIndex: carIndex,
        Position: slot.Position,
        GridPosition: slot.GridPosition,
        NumLaps: slot.NumLaps,
        Points: slot.Points,
        NumPitStops: slot.NumPitStops,
        NumPenalties: slot.NumPenalties,
        ResultStatus: F1EnumMaps.ToResultStatus(slot.ResultStatus),
        BestLapTimeMs: ClampToInt(slot.BestLapTimeInMS),
        TotalRaceTimeMs: SecondsToMilliseconds(slot.TotalRaceTime),
        PenaltiesTimeMs: slot.PenaltiesTime * MillisecondsPerSecond,
        TyreStints: MapTyreStints(slot));

    private static List<TyreStint> MapTyreStints(FinalClassificationData slot)
    {
        var actual = slot.TyreStintsActual.AsReadOnlySpan();
        var visual = slot.TyreStintsVisual.AsReadOnlySpan();
        var endLaps = slot.TyreStintsEndLaps.AsReadOnlySpan();
        var count = Math.Min((int)slot.NumTyreStints, MaxTyreStints);

        var stints = new List<TyreStint>(count);
        for (var i = 0; i < count; i++)
        {
            stints.Add(new TyreStint(
                EndLap: endLaps[i],
                VisualCompound: F1EnumMaps.ToVisualCompound(visual[i]),
                ActualCompound: F1EnumMaps.ToActualCompoundLabel(actual[i])));
        }

        return stints;
    }

    /// <summary>
    /// 초(double) → 밀리초(int), 사사오입(0.5는 0에서 먼 쪽). 깨진 값(NaN·음수·범위 밖)은 백엔드가 영구 거부하는 값을 만들지 않도록
    /// 0 또는 <see cref="int.MaxValue"/>로 다듬는다(12 §0 실패 원칙).
    /// </summary>
    private static int SecondsToMilliseconds(double seconds)
    {
        if (double.IsNaN(seconds) || seconds <= 0)
        {
            return 0;
        }

        var milliseconds = Math.Round(seconds * MillisecondsPerSecond, MidpointRounding.AwayFromZero);
        return milliseconds >= int.MaxValue ? int.MaxValue : (int)milliseconds;
    }

    private static int ClampToInt(uint value) => value > int.MaxValue ? int.MaxValue : (int)value;

    /// <summary>UDP의 이름 필드는 고정 길이 버퍼라 NUL 패딩이 남을 수 있다 — 첫 NUL에서 자른다. null이면 빈 문자열.</summary>
    private static string CutAtFirstNul(string? name)
    {
        if (string.IsNullOrEmpty(name))
        {
            return string.Empty;
        }

        var nul = name.IndexOf('\0');
        return nul < 0 ? name : name[..nul];
    }

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
