using F1Game.UDP.Data;
using SimCenter.Agent.Core.Telemetry.Frames;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// UDP 형식 2026(F1 25 2026 시즌팩) 매핑. 차 칸 패킷은 <see cref="Season2026Wire"/>가 25.1.1 구조체 칸 배열(24칸)로 옮겨 2025와 같은 매핑을 타고,
/// 배치가 2025와 같은 패킷(Session 앞부분·Event·Session History·Tyre Sets·Motion Ex)은 25.1.1로 그대로 해석한다.
/// 2026에만 있는 값: Car Telemetry 2(플레이어 → 트레이스 extra, 모든 차의 액티브 에어로·오버테이크 모드·역주행 → 리플레이 표본), Session 꼬리(→ session 상세),
/// 랩당 ERS 회수 한도(→ status 상세), 충돌 강도·부분 모드 이유(→ 이벤트 상세). Lobby Info(9)는 2025처럼 읽지 않는다.
/// 크기가 모자란 패킷은 종류마다 한 번 경고하고 버린다.
/// </summary>
public sealed partial class F1PacketMapper
{
    private static readonly F1Enums.PacketType CarTelemetry2 = (F1Enums.PacketType)Season2026Wire.CarTelemetry2PacketId;

    /// <summary>Car Telemetry 2의 액티브 에어로 모드 값(0 코너 · 1 직선).</summary>
    private const byte ActiveAeroStraightMode = 1;

    private IReadOnlyList<ITelemetryFrame> MapSeason2026(ReadOnlySpan<byte> datagram)
    {
        if (datagram.Length < Season2026Wire.HeaderSize)
        {
            WarnUnreadable(datagram, $"헤더 {Season2026Wire.HeaderSize}바이트보다 짧습니다");
            return Empty;
        }

        var packetType = (F1Enums.PacketType)datagram[PacketIdOffset];
        if (RequiredSize2026(packetType) is not { } required)
        {
            return Empty;
        }

        if (datagram.Length < required)
        {
            WarnUnreadable(datagram, $"2026 배치는 {required}바이트가 필요합니다");
            return Empty;
        }

        var header = Season2026Wire.Header(datagram);
        return packetType switch
        {
            F1Enums.PacketType.Motion => MapMotionPacket(header, Season2026Wire.Motion(datagram)),
            F1Enums.PacketType.Session => MapSession2026(datagram),
            F1Enums.PacketType.LapData => MapLapData2026(datagram, header),
            F1Enums.PacketType.Event => MapEvent2026(datagram),
            F1Enums.PacketType.Participants => MapParticipantsFrames(header, Season2026Wire.Participants(datagram)),
            F1Enums.PacketType.CarSetups => MapCarSetupPacket(header, Season2026Wire.CarSetups(datagram), Season2026Wire.NextFrontWingValue(datagram)),
            F1Enums.PacketType.CarTelemetry => MapCarTelemetryPacket(header, Season2026Wire.CarTelemetry(datagram), Season2026Wire.SuggestedGear(datagram)),
            F1Enums.PacketType.CarStatus => MapCarStatusPacket(header, Season2026Wire.CarStatus(datagram), PlayerErsHarvestLimit(datagram, header)),
            F1Enums.PacketType.FinalClassification => [MapClassification(header, Season2026Wire.Classification(datagram))],
            F1Enums.PacketType.CarDamage => MapCarDamagePacket(header, Season2026Wire.CarDamage(datagram)),
            F1Enums.PacketType.TimeTrial => [DetailsFrame(header, F1DetailSections.TimeTrial, TimeTrialDetails(datagram))],
            F1Enums.PacketType.LapPositions => [F1SessionHistory.MapSeason2026(datagram, header)],
            _ when packetType == CarTelemetry2 => MapCarTelemetry2(datagram, header),

            // Session History·Tyre Sets·Motion Ex: 배치가 2025와 같다.
            _ => TryParse(datagram, out var packet) ? MapParsed(packet) : Empty,
        };
    }

    /// <summary>읽는 패킷의 2026 크기. Lobby Info·모르는 패킷이면 null(읽지 않는다). 배치가 2025와 같은 셋은 25.1.1이 크기를 검사한다.</summary>
    private static int? RequiredSize2026(F1Enums.PacketType packetType) => packetType switch
    {
        F1Enums.PacketType.Motion => Season2026Wire.MotionSize,
        F1Enums.PacketType.Session => Season2026Wire.SessionSize,
        F1Enums.PacketType.LapData => Season2026Wire.LapDataSize,
        F1Enums.PacketType.Event => Season2026Wire.EventSize,
        F1Enums.PacketType.Participants => Season2026Wire.ParticipantsSize,
        F1Enums.PacketType.CarSetups => Season2026Wire.CarSetupsSize,
        F1Enums.PacketType.CarTelemetry => Season2026Wire.CarTelemetrySize,
        F1Enums.PacketType.CarStatus => Season2026Wire.CarStatusSize,
        F1Enums.PacketType.FinalClassification => Season2026Wire.ClassificationSize,
        F1Enums.PacketType.CarDamage => Season2026Wire.CarDamageSize,
        F1Enums.PacketType.TimeTrial => Season2026Wire.TimeTrialSize,
        F1Enums.PacketType.LapPositions => Season2026Wire.LapPositionsSize,
        F1Enums.PacketType.SessionHistory or F1Enums.PacketType.TyreSets or F1Enums.PacketType.MotionEx => Season2026Wire.HeaderSize,
        _ when packetType == CarTelemetry2 => Season2026Wire.CarTelemetry2Size,
        _ => null,
    };

    /// <summary>Session: 앞 753바이트는 2025와 같아 25.1.1로 읽고, 꼬리(액티브 에어로·반응 시간 등)를 상세에 더한다.</summary>
    private IReadOnlyList<ITelemetryFrame> MapSession2026(ReadOnlySpan<byte> datagram)
    {
        if (!TryParse(datagram, out var packet) || !packet.TryGetSessionDataPacket(out var session))
        {
            return Empty;
        }

        var details = F1SessionDetails.From(session, Season2026Wire.SessionTail(datagram));
        return [MapSession(session), DetailsFrame(session.Header, F1DetailSections.Session, details)];
    }

    private IReadOnlyList<ITelemetryFrame> MapLapData2026(ReadOnlySpan<byte> datagram, PacketHeader header)
    {
        var (personalBest, rival) = Season2026Wire.TimeTrialCarIndexes(datagram);
        return MapLapDataPacket(header, Season2026Wire.LapData(datagram), personalBest, rival);
    }

    /// <summary>Event: 배치는 2025와 같고, 충돌이면 공용체 안의 강도 바이트를, 부분 모드 켜짐(PMEN)이면 이유 바이트를 더한다.</summary>
    private IReadOnlyList<ITelemetryFrame> MapEvent2026(ReadOnlySpan<byte> datagram)
    {
        if (!TryParse(datagram, out var packet) || !packet.TryGetEventDataPacket(out var eventPacket))
        {
            return Empty;
        }

        var details = eventPacket.EventDetails;
        var extras = new Season2026EventExtras(
            CollisionSeverity: details.TryGetCollisionEvent(out _) ? Season2026Wire.CollisionSeverity(datagram) : null,
            PartialModeReason: F1GameEvents.CodeOf(details.EventType) == Season2026Wire.PartialModeEnabledCode
                ? Season2026Wire.PartialModeReason(datagram)
                : null);
        return MapEventFrames(eventPacket, extras);
    }

    private static float? PlayerErsHarvestLimit(ReadOnlySpan<byte> datagram, PacketHeader header) =>
        header.PlayerCarIndex < Season2026Wire.MaxCars ? Season2026Wire.ErsHarvestLimitPerLap(datagram, header.PlayerCarIndex) : null;

    private static IReadOnlyDictionary<string, object?> TimeTrialDetails(ReadOnlySpan<byte> datagram)
    {
        var (sessionBest, personalBest, rival) = Season2026Wire.TimeTrial(datagram);
        return F1DetailSections.FromTimeTrial(sessionBest, personalBest, rival);
    }

    /// <summary>
    /// Car Telemetry 2: 플레이어 칸의 모든 값은 트레이스 extra로(다음 Car Telemetry 프레임의 칸에 찍힌다),
    /// 모든 차의 액티브 에어로·오버테이크 모드·역주행은 리플레이 표본으로(<see cref="FieldActiveAeroFrame"/>).
    /// </summary>
    private IReadOnlyList<ITelemetryFrame> MapCarTelemetry2(ReadOnlySpan<byte> datagram, PacketHeader header)
    {
        var cars = Season2026Wire.CarTelemetry2All(datagram);
        var field = MapFieldActiveAero(header, cars);
        return IsPlayerSlot(CarTelemetry2, header, cars.Length)
            ? [ExtraFrame(header, F1ExtraChannels.FromCarTelemetry2(cars[header.PlayerCarIndex])), field]
            : [field];
    }

    private static FieldActiveAeroFrame MapFieldActiveAero(PacketHeader header, IReadOnlyList<Season2026CarTelemetry2> cars)
    {
        var states = new FieldActiveAero[cars.Count];
        for (var i = 0; i < states.Length; i++)
        {
            var car = cars[i];
            states[i] = new FieldActiveAero(
                StraightMode: car.ActiveAeroMode == ActiveAeroStraightMode,
                car.ActiveAeroAvailable,
                car.OvertakeAvailable,
                car.OvertakeActive,
                car.IsDrivingWrongWay);
        }

        return new FieldActiveAeroFrame(header.SessionUID.ToString(), states);
    }
}
