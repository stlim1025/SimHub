using F1Game.UDP.Data;
using F1Game.UDP.Packets;
using SimCenter.Agent.Core.Telemetry.Frames;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// "전부 수집"(D-49, docs/15 §8) 매핑: 패킷마다 기존 프레임에 더해 트레이스 extra 채널(<see cref="ExtraChannelsFrame"/>)·
/// 상세 묶음(<see cref="CarDetailsFrame"/>)·게임 이벤트·세션 기록 프레임을 낸다. 같은 패킷 안 프레임 순서가 뜻을 가진다(각 메서드 주석).
/// Lobby Info(9)는 읽지 않는다. 다른 차는 트랙 형상 표본용 위치·랩 상태·노면만 읽는다(헌장 Agent Rules 예외, <c>F1PacketMapper.Field.cs</c>).
/// </summary>
public sealed partial class F1PacketMapper
{
    /// <summary>기존 프레임이 없는 패킷(Motion·Car Setups·Session History·Tyre Sets·Motion Ex·Time Trial·Lap Positions).</summary>
    private IReadOnlyList<ITelemetryFrame> MapCollectAllPacket(UnionPacket packet)
    {
        switch (packet.PacketType)
        {
            case F1Enums.PacketType.Motion when packet.TryGetMotionDataPacket(out var motion):
                return [.. MapPlayerCar(packet.PacketType, packet.Header, motion.CarMotionData.AsReadOnlySpan(), MapMotionFrames), MapFieldPositions(motion)];

            case F1Enums.PacketType.MotionEx when packet.TryGetMotionExDataPacket(out var motionEx):
                return [ExtraFrame(motionEx.Header, F1ExtraChannels.FromMotionEx(motionEx))];

            case F1Enums.PacketType.CarSetups when packet.TryGetCarSetupDataPacket(out var setups):
                return MapCarSetupPacket(setups);

            case F1Enums.PacketType.SessionHistory when packet.TryGetSessionHistoryDataPacket(out var history):
                return [F1SessionHistory.Map(history)];

            case F1Enums.PacketType.LapPositions when packet.TryGetLapPositionsDataPacket(out var positions):
                return [F1SessionHistory.Map(positions)];

            case F1Enums.PacketType.TyreSets when packet.TryGetTyreSetsDataPacket(out var tyreSets):
                // 차마다 돌아가며 온다 — 플레이어 차의 세트만 싣는다.
                return tyreSets.CarIndex == tyreSets.Header.PlayerCarIndex
                    ? [DetailsFrame(tyreSets.Header, F1DetailSections.TyreSets, F1DetailSections.FromTyreSets(tyreSets))]
                    : Empty;

            case F1Enums.PacketType.TimeTrial when packet.TryGetTimeTrialDataPacket(out var timeTrial):
                return [DetailsFrame(timeTrial.Header, F1DetailSections.TimeTrial, F1DetailSections.FromTimeTrial(timeTrial))];

            default:
                return Empty;
        }
    }

    /// <summary>
    /// Car Telemetry: extra 채널을 <b>먼저</b> 싣는다 — 트레이스 기록기가 뒤따르는 Car Telemetry 프레임에서 그 칸에 최신 묶음을 찍으므로
    /// 같은 패킷의 값이 같은 칸에 들어간다. 추천 기어는 패킷 단위 값이다.
    /// </summary>
    private IReadOnlyList<ITelemetryFrame> MapCarTelemetryPacket(CarTelemetryDataPacket packet)
    {
        var cars = packet.CarTelemetryData.AsReadOnlySpan();
        if (!IsPlayerSlot(F1Enums.PacketType.CarTelemetry, packet.Header, cars.Length))
        {
            return [MapFieldSurfaces(packet)];
        }

        var car = cars[packet.Header.PlayerCarIndex];
        return
        [
            ExtraFrame(packet.Header, F1ExtraChannels.FromCarTelemetry(car, packet.SuggestedGear)),
            MapCarTelemetry(car, packet.Header),
            MapFieldSurfaces(packet),
        ];
    }

    /// <summary>
    /// Lap Data: 랩 프레임을 <b>먼저</b> 싣는다 — 랩이 바뀌는 프레임이면 분석기가 앞 랩을 확정한(그 랩의 마지막 <c>lapData</c> 묶음으로) 뒤에 새 랩의 값이 들어온다.
    /// </summary>
    private IReadOnlyList<ITelemetryFrame> MapLapDataPacket(LapDataPacket packet)
    {
        var laps = packet.LapData.AsReadOnlySpan();
        if (!IsPlayerSlot(F1Enums.PacketType.LapData, packet.Header, laps.Length))
        {
            return [MapFieldLapStates(packet)];
        }

        var index = packet.Header.PlayerCarIndex;
        var lap = laps[index];
        return
        [
            MapLap(lap, packet.Header),
            ExtraFrame(packet.Header, F1ExtraChannels.FromLapData(lap)),
            DetailsFrame(packet.Header, F1DetailSections.LapData, F1DetailSections.FromLapData(lap, index, packet)),
            MapFieldLapStates(packet),
        ];
    }

    private IReadOnlyList<ITelemetryFrame> MapCarStatusFrames(CarStatusData car, PacketHeader header) =>
    [
        MapCarStatus(car, header),
        ExtraFrame(header, F1ExtraChannels.FromCarStatus(car)),
        DetailsFrame(header, F1DetailSections.Status, F1DetailSections.FromStatus(car)),
    ];

    private IReadOnlyList<ITelemetryFrame> MapCarDamageFrames(CarDamageData car, PacketHeader header) =>
        [MapCarDamage(car, header), DetailsFrame(header, F1DetailSections.Damage, F1DetailSections.FromDamage(car))];

    private static IReadOnlyList<ITelemetryFrame> MapMotionFrames(CarMotionData car, PacketHeader header) =>
        [ExtraFrame(header, F1ExtraChannels.FromMotion(car))];

    private IReadOnlyList<ITelemetryFrame> MapCarSetupPacket(CarSetupDataPacket packet)
    {
        var cars = packet.CarSetups.AsReadOnlySpan();
        if (!IsPlayerSlot(F1Enums.PacketType.CarSetups, packet.Header, cars.Length))
        {
            return Empty;
        }

        var setup = F1DetailSections.FromSetup(cars[packet.Header.PlayerCarIndex], packet.NextFrontWingValue);
        return [DetailsFrame(packet.Header, F1DetailSections.Setup, setup)];
    }

    /// <summary>Participants: 기존 참가자 프레임 + 플레이어 칸이 있으면(관전 중이 아니면) 그 칸의 상세 묶음.</summary>
    private IReadOnlyList<ITelemetryFrame> MapParticipantsFrames(ParticipantsDataPacket packet)
    {
        var frame = MapParticipants(packet);
        var slots = packet.Participants.AsReadOnlySpan();
        var index = packet.Header.PlayerCarIndex;
        if (index >= slots.Length)
        {
            return [frame];
        }

        var player = slots[index];
        var details = F1DetailSections.FromParticipant(player, index, CutAtFirstNul(player.Name));
        return [frame, DetailsFrame(packet.Header, F1DetailSections.Participant, details)];
    }

    /// <summary>Event: 세션 경계는 마커로, 그 밖의 코드는 게임 이벤트로(버튼 상태는 버린다).</summary>
    private IReadOnlyList<ITelemetryFrame> MapEventFrames(EventDataPacket packet)
    {
        if (MapEvent(packet) is { } marker)
        {
            return [marker];
        }

        if (F1GameEvents.Map(packet) is not { } gameEvent)
        {
            return Empty;
        }

        var sessionRef = packet.Header.SessionUID.ToString();
        var frame = new GameEventFrame(sessionRef, gameEvent.Code, gameEvent.Details);
        // 차 대 차 충돌·추월은 표본에도 표시한다(벽 충돌은 게임이 이벤트로 보내지 않아 G-force·손상으로 가려낸다).
        var details = packet.EventDetails;
        if (details.TryGetCollisionEvent(out var collision))
        {
            return [frame, new FieldCollisionFrame(sessionRef, collision.Vehicle1Index, collision.Vehicle2Index)];
        }

        return details.TryGetOvertakeEvent(out var overtake)
            ? [frame, new FieldOvertakeFrame(sessionRef, overtake.OvertakingVehicleIdx, overtake.BeingOvertakenVehicleIdx)]
            : [frame];
    }

    private static ExtraChannelsFrame ExtraFrame(PacketHeader header, IReadOnlyDictionary<string, double> channels) =>
        new(header.SessionUID.ToString(), channels);

    private static CarDetailsFrame DetailsFrame(PacketHeader header, string section, IReadOnlyDictionary<string, object?> values) =>
        new(header.SessionUID.ToString(), section, values);
}
