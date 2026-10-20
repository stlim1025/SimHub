using F1Game.UDP;
using F1Game.UDP.Data;
using F1Game.UDP.Packets;
using Microsoft.Extensions.Logging;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;
using F1Enums = F1Game.UDP.Enums;
using F1Events = F1Game.UDP.Events;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// F1Game.UDP 패킷을 Agent.Core의 게임중립 프레임으로 매핑한다(D-20 경계).
/// 처음엔 관심 패킷만 처리했으나(docs/06 §2.2) D-49(docs/15 §8)부터 Lobby Info(9)를 뺀 모든 패킷의 플레이어 차·세션 값을 읽는다
/// (추가분은 <c>F1PacketMapper.CollectAll.cs</c>). 다른 차의 Motion은 읽지 않는다.
/// 개별 Map* 메서드는 구성 가능한 패킷 구조체를 받아 단위테스트가 가능하다.
/// </summary>
public sealed partial class F1PacketMapper
{
    private const int MillisecondsPerSecond = 1000;

    /// <summary>F1 25가 한 차에 기록하는 타이어 스틴트 최대 수(<c>Array8</c>의 칸 수, 12 §5.2).</summary>
    private const int MaxTyreStints = 8;

    /// <summary>
    /// 순위표 행으로 보내는 <c>Position</c>의 상한. 백엔드 <c>SessionClassificationValidator.MaxClassificationEntries</c>(32)와 같다 —
    /// 이를 넘는 값이 한 칸이라도 실리면 백엔드가 세션 전체를 Reject하므로 그런 칸은 보내지 않는다.
    /// </summary>
    private const int MaxClassifiedPosition = 32;

    /// <summary>헤더에서 <c>m_packetId</c>의 위치(format 2 + gameYear 1 + major 1 + minor 1 + packetVersion 1).</summary>
    private const int PacketIdOffset = 6;

    /// <summary>헤더조차 못 읽을 만큼 짧은 데이터그램의 패킷 ID 표기.</summary>
    private const string UnknownPacketId = "?";

    private static readonly IReadOnlyList<ITelemetryFrame> Empty = Array.Empty<ITelemetryFrame>();

    private readonly int _expectedPacketFormat;
    private readonly ILogger<F1PacketMapper> _logger;

    /// <summary>이미 경고한 버림 사유(예: <c>parse:2</c>, <c>format:2024</c>). 파이프라인이 단일 스레드로 호출하므로 잠금 없이 쓴다.</summary>
    private readonly HashSet<string> _warnedDropReasons = [];

    public F1PacketMapper(int expectedPacketFormat, ILogger<F1PacketMapper> logger)
    {
        _expectedPacketFormat = expectedPacketFormat;
        _logger = logger;
    }

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
            var packetId = datagram.Length > PacketIdOffset ? datagram[PacketIdOffset].ToString() : UnknownPacketId;
            if (IsFirstDrop($"parse:{packetId}"))
            {
                _logger.LogWarning(
                    "F1 패킷 해석 실패(packetId={PacketId}, {Length}바이트) — F1Game.UDP 버전이 게임의 UDP 형식과 맞는지 확인하세요. 같은 종류는 다시 기록하지 않습니다: {Reason}",
                    packetId,
                    datagram.Length,
                    ex.Message);
            }

            return Empty;
        }

        return Map(packet);
    }

    /// <summary>
    /// 이 사유로 처음 버리는 것이면 true. 패킷을 버리는 경로는 사유마다 한 번 경고한다(초당 수십 개가 와도 로그가 넘치지 않게).
    /// 조용히 버리면 "패킷은 받는데 랩이 저장되지 않는" 상태를 알아챌 수 없다 — F1Game.UDP 버전이 게임 레이아웃과 어긋났던 사례(D-41).
    /// </summary>
    private bool IsFirstDrop(string reason) => _warnedDropReasons.Add(reason);

    /// <summary>파싱된 UnionPacket을 프레임으로 매핑(버전 검증 포함).</summary>
    public IReadOnlyList<ITelemetryFrame> Map(UnionPacket packet)
    {
        // 버전 가드: 기대 포맷이 아니면 스킵(다른 연식 패킷, D-20/OCP).
        if (packet.Header.PacketFormat != _expectedPacketFormat)
        {
            if (IsFirstDrop($"format:{packet.Header.PacketFormat}"))
            {
                _logger.LogWarning(
                    "UDP 형식 {Actual} 패킷을 버립니다 — Agent는 {ExpectedFormat} 형식만 읽습니다. 게임의 텔레메트리 설정에서 UDP 형식을 확인하세요. 같은 형식은 다시 기록하지 않습니다",
                    packet.Header.PacketFormat,
                    _expectedPacketFormat);
            }

            return Empty;
        }

        switch (packet.PacketType)
        {
            case F1Enums.PacketType.Session when packet.TryGetSessionDataPacket(out var session):
                return [MapSession(session), DetailsFrame(session.Header, F1DetailSections.Session, F1SessionDetails.From(session))];

            case F1Enums.PacketType.LapData when packet.TryGetLapDataPacket(out var lapPacket):
                return MapLapDataPacket(lapPacket);

            case F1Enums.PacketType.CarTelemetry when packet.TryGetCarTelemetryDataPacket(out var telemetry):
                return MapCarTelemetryPacket(telemetry);

            case F1Enums.PacketType.CarStatus when packet.TryGetCarStatusDataPacket(out var status):
                return MapPlayerCar(packet.PacketType, packet.Header, status.CarStatusData.AsReadOnlySpan(), MapCarStatusFrames);

            case F1Enums.PacketType.CarDamage when packet.TryGetCarDamageDataPacket(out var damage):
                return MapPlayerCar(packet.PacketType, packet.Header, damage.CarDamageData.AsReadOnlySpan(), MapCarDamageFrames);

            case F1Enums.PacketType.Event when packet.TryGetEventDataPacket(out var eventPacket):
                return MapEventFrames(eventPacket);

            case F1Enums.PacketType.Participants when packet.TryGetParticipantsDataPacket(out var participants):
                return MapParticipantsFrames(participants);

            case F1Enums.PacketType.FinalClassification when packet.TryGetFinalClassificationDataPacket(out var classification):
                return [MapClassification(classification)];

            default:
                return MapCollectAllPacket(packet);
        }
    }

    /// <summary>
    /// 차마다 칸이 있는 패킷에서 플레이어 칸만 매핑한다. 플레이어 번호가 칸 수를 넘으면(관전 중 등) 버리고,
    /// 패킷 종류와 무관하게 한 번만 경고한다(관전 중이면 모든 차 패킷이 같은 이유로 버려진다).
    /// </summary>
    private IReadOnlyList<ITelemetryFrame> MapPlayerCar<TCar>(
        F1Enums.PacketType packetType,
        PacketHeader header,
        ReadOnlySpan<TCar> cars,
        Func<TCar, PacketHeader, IReadOnlyList<ITelemetryFrame>> map)
    {
        return IsPlayerSlot(packetType, header, cars.Length) ? map(cars[header.PlayerCarIndex], header) : Empty;
    }

    /// <summary>헤더의 플레이어 번호가 칸 안이면 true. 아니면(관전 중 등) 패킷 종류와 무관하게 한 번만 경고한다.</summary>
    private bool IsPlayerSlot(F1Enums.PacketType packetType, PacketHeader header, int slots)
    {
        var index = header.PlayerCarIndex;
        if (index < slots)
        {
            return true;
        }

        if (IsFirstDrop("player-index"))
        {
            _logger.LogWarning(
                "플레이어 차 번호 {Index}가 {PacketType} 칸 수 {Slots}를 넘어 플레이어 차를 읽지 못했습니다(관전 중이면 정상) — 아니면 게임의 UDP 레이아웃과 F1Game.UDP 버전이 맞는지 확인하세요",
                index,
                packetType,
                slots);
        }

        return false;
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
        IsNetworkGame: packet.IsNetworkGame,
        Weather: F1EnumMaps.ToWeather(packet.Weather),
        AirTemperatureC: packet.AirTemperature,
        TrackTemperatureC: packet.TrackTemperature,
        TrackLengthM: packet.TrackLength,
        RainForecastPercent: RainForecast.Select(packet));

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

        return new ParticipantsFrame(packet.Header.SessionUID.ToString(), participants, packet.Header.PlayerCarIndex);
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
                      || lap.PitStatus != F1Enums.PitStatus.None,
        LapDistanceM: lap.LapDistance,
        CurrentLapTimeMs: ClampToInt(lap.CurrentLapTimeInMS),
        IsFinished: lap.ResultStatus == F1Enums.ResultStatus.Finished);

    /// <summary>플레이어 차 Car Telemetry(트레이스 원천, D-45). 페달·스티어는 게임 값(0~1, −1~1) 그대로.</summary>
    public CarTelemetryFrame MapCarTelemetry(CarTelemetryData car, PacketHeader header) => new(
        SessionRef: header.SessionUID.ToString(),
        SpeedKph: car.Speed,
        Throttle: car.Throttle,
        Brake: car.Brake,
        Steer: car.Steer,
        Gear: car.Gear,
        EngineRpm: car.EngineRPM);

    /// <summary>플레이어 차 Car Status(스냅샷의 연료·ERS·타이어, D-44). 컴파운드는 게임 원시 값.</summary>
    public CarStatusFrame MapCarStatus(CarStatusData car, PacketHeader header) => new(
        SessionRef: header.SessionUID.ToString(),
        FuelInTankKg: car.FuelInTank,
        FuelRemainingLaps: car.FuelRemainingLaps,
        ErsStoreEnergyJ: car.ErsStoreEnergy,
        ErsDeployedThisLapJ: car.ErsDeployedThisLap,
        ErsHarvestedThisLapMgukJ: car.ErsHarvestedThisLapMGUK,
        ErsHarvestedThisLapMguhJ: car.ErsHarvestedThisLapMGUH,
        ActualTyreCompound: (int)car.ActualTyreCompound,
        VisualTyreCompound: (int)car.VisualTyreCompound,
        TyreAgeLaps: car.TyresAgeLaps);

    /// <summary>
    /// 플레이어 차 Car Damage(스냅샷의 마모·손상, D-44). 라이브러리의 <c>Tyres&lt;T&gt;</c>는 UDP 배열 순서(RL·RR·FL·FR)를 이름으로 풀어 둔다 —
    /// 여기서도 순서가 아니라 이름으로 옮긴다(F1WireLayoutTests가 바이트 순서를 고정).
    /// </summary>
    public CarDamageFrame MapCarDamage(CarDamageData car, PacketHeader header) => new(
        SessionRef: header.SessionUID.ToString(),
        TyreWearPercent: ToWheelSet(car.TyresWear),
        TyreDamagePercent: ToWheelSet(car.TyresDamage),
        BrakeDamagePercent: ToWheelSet(car.BrakesDamage),
        FrontLeftWingDamage: car.FrontLeftWingDamage,
        FrontRightWingDamage: car.FrontRightWingDamage,
        RearWingDamage: car.RearWingDamage,
        FloorDamage: car.FloorDamage,
        DiffuserDamage: car.DiffuserDamage,
        SidepodDamage: car.SidepodDamage,
        GearboxDamage: car.GearBoxDamage,
        EngineDamage: car.EngineDamage);

    private static WheelSet<float> ToWheelSet(Tyres<float> tyres) =>
        new(FrontLeft: tyres.FrontLeft, FrontRight: tyres.FrontRight, RearLeft: tyres.RearLeft, RearRight: tyres.RearRight);

    private static WheelSet<int> ToWheelSet(Tyres<byte> tyres) =>
        new(FrontLeft: tyres.FrontLeft, FrontRight: tyres.FrontRight, RearLeft: tyres.RearLeft, RearRight: tyres.RearRight);

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
