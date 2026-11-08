using F1Game.UDP.Data;
using F1Game.UDP.Packets;
using SimCenter.Agent.Core.Telemetry.Frames;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// "전부 수집"(D-49, docs/15 §8) 매핑: 패킷마다 기존 프레임에 더해 트레이스 extra 채널(<see cref="ExtraChannelsFrame"/>)·
/// 상세 묶음(<see cref="CarDetailsFrame"/>)·게임 이벤트·세션 기록 프레임을 낸다. 같은 패킷 안 프레임 순서가 뜻을 가진다(각 메서드 주석).
/// Lobby Info(9)는 읽지 않는다. 다른 차는 트랙 형상 표본용 위치·랩 상태·노면만 읽는다(헌장 Agent Rules 예외, <c>F1PacketMapper.Field.cs</c>).
/// 차마다 칸이 있는 패킷은 칸 배열(2025 = 22칸, 2026 = 24칸)을 받아 형식과 무관하게 같은 매핑을 탄다.
/// </summary>
public sealed partial class F1PacketMapper
{
    /// <summary>기존 프레임이 없는 패킷(Motion·Car Setups·Session History·Tyre Sets·Motion Ex·Time Trial·Lap Positions).</summary>
    private IReadOnlyList<ITelemetryFrame> MapCollectAllPacket(UnionPacket packet)
    {
        switch (packet.PacketType)
        {
            case F1Enums.PacketType.Motion when packet.TryGetMotionDataPacket(out var motion):
                return MapMotionPacket(motion.Header, motion.CarMotionData.AsReadOnlySpan());

            case F1Enums.PacketType.MotionEx when packet.TryGetMotionExDataPacket(out var motionEx):
                return [ExtraFrame(motionEx.Header, F1ExtraChannels.FromMotionEx(motionEx))];

            case F1Enums.PacketType.CarSetups when packet.TryGetCarSetupDataPacket(out var setups):
                return MapCarSetupPacket(setups.Header, setups.CarSetups.AsReadOnlySpan(), setups.NextFrontWingValue);

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
                var sets = F1DetailSections.FromTimeTrial(
                    TimeTrialSet.From(timeTrial.PlayerSessionBestDataSet),
                    TimeTrialSet.From(timeTrial.PersonalBestDataSet),
                    TimeTrialSet.From(timeTrial.RivalDataSet));
                return [DetailsFrame(timeTrial.Header, F1DetailSections.TimeTrial, sets)];

            default:
                return Empty;
        }
    }

    /// <summary>
    /// Car Telemetry: extra 채널을 <b>먼저</b> 싣는다 — 트레이스 기록기가 뒤따르는 Car Telemetry 프레임에서 그 칸에 최신 묶음을 찍으므로
    /// 같은 패킷의 값이 같은 칸에 들어간다. 추천 기어는 패킷 단위 값이다.
    /// </summary>
    private IReadOnlyList<ITelemetryFrame> MapCarTelemetryPacket(PacketHeader header, ReadOnlySpan<CarTelemetryData> cars, byte suggestedGear)
    {
        if (!IsPlayerSlot(F1Enums.PacketType.CarTelemetry, header, cars.Length))
        {
            return [MapFieldSurfaces(header, cars)];
        }

        var car = cars[header.PlayerCarIndex];
        return
        [
            ExtraFrame(header, F1ExtraChannels.FromCarTelemetry(car, suggestedGear)),
            MapCarTelemetry(car, header),
            MapFieldSurfaces(header, cars),
        ];
    }

    /// <summary>
    /// Lap Data: 랩 프레임을 <b>먼저</b> 싣는다 — 랩이 바뀌는 프레임이면 분석기가 앞 랩을 확정한(그 랩의 마지막 <c>lapData</c> 묶음으로) 뒤에 새 랩의 값이 들어온다.
    /// </summary>
    private IReadOnlyList<ITelemetryFrame> MapLapDataPacket(PacketHeader header, ReadOnlySpan<LapData> laps, byte timeTrialPbCarIndex, byte timeTrialRivalCarIndex)
    {
        if (!IsPlayerSlot(F1Enums.PacketType.LapData, header, laps.Length))
        {
            return [MapFieldLapStates(header, laps)];
        }

        var index = header.PlayerCarIndex;
        var lap = laps[index];
        return
        [
            MapLap(lap, header),
            ExtraFrame(header, F1ExtraChannels.FromLapData(lap)),
            DetailsFrame(header, F1DetailSections.LapData, F1DetailSections.FromLapData(lap, index, timeTrialPbCarIndex, timeTrialRivalCarIndex)),
            MapFieldLapStates(header, laps),
        ];
    }

    /// <summary>Car Status: 플레이어 칸 프레임 + 모든 차 타이어·ERS. 랩당 ERS 회수 한도는 2026 형식에만 있다(2025는 null).</summary>
    private IReadOnlyList<ITelemetryFrame> MapCarStatusPacket(PacketHeader header, ReadOnlySpan<CarStatusData> cars, float? ersHarvestLimitPerLap) =>
    [
        .. MapPlayerCar(F1Enums.PacketType.CarStatus, header, cars, (car, carHeader) => MapCarStatusFrames(car, carHeader, ersHarvestLimitPerLap)),
        MapFieldStatus(header, cars),
    ];

    private IReadOnlyList<ITelemetryFrame> MapCarDamagePacket(PacketHeader header, ReadOnlySpan<CarDamageData> cars) =>
        [.. MapPlayerCar(F1Enums.PacketType.CarDamage, header, cars, MapCarDamageFrames), MapFieldDamage(header, cars)];

    private IReadOnlyList<ITelemetryFrame> MapMotionPacket(PacketHeader header, ReadOnlySpan<CarMotionData> cars) =>
        [.. MapPlayerCar(F1Enums.PacketType.Motion, header, cars, MapMotionFrames), MapFieldPositions(header, cars)];

    private IReadOnlyList<ITelemetryFrame> MapCarStatusFrames(CarStatusData car, PacketHeader header, float? ersHarvestLimitPerLap) =>
    [
        MapCarStatus(car, header),
        ExtraFrame(header, F1ExtraChannels.FromCarStatus(car)),
        DetailsFrame(header, F1DetailSections.Status, F1DetailSections.FromStatus(car, ersHarvestLimitPerLap)),
    ];

    private IReadOnlyList<ITelemetryFrame> MapCarDamageFrames(CarDamageData car, PacketHeader header) =>
        [MapCarDamage(car, header), DetailsFrame(header, F1DetailSections.Damage, F1DetailSections.FromDamage(car))];

    private static IReadOnlyList<ITelemetryFrame> MapMotionFrames(CarMotionData car, PacketHeader header) =>
        [ExtraFrame(header, F1ExtraChannels.FromMotion(car))];

    private IReadOnlyList<ITelemetryFrame> MapCarSetupPacket(PacketHeader header, ReadOnlySpan<CarSetupData> cars, float nextFrontWingValue)
    {
        if (!IsPlayerSlot(F1Enums.PacketType.CarSetups, header, cars.Length))
        {
            return Empty;
        }

        var setup = F1DetailSections.FromSetup(cars[header.PlayerCarIndex], nextFrontWingValue);
        return [DetailsFrame(header, F1DetailSections.Setup, setup)];
    }

    /// <summary>Participants: 기존 참가자 프레임 + 플레이어 칸이 있으면(관전 중이 아니면) 그 칸의 상세 묶음.</summary>
    private static IReadOnlyList<ITelemetryFrame> MapParticipantsFrames(PacketHeader header, IReadOnlyList<ParticipantSlot> slots)
    {
        var frame = MapParticipants(header, slots);
        var index = header.PlayerCarIndex;
        if (index >= slots.Count)
        {
            return [frame];
        }

        var player = slots[index];
        var details = F1DetailSections.FromParticipant(player, index, CutAtFirstNul(player.Name));
        return [frame, DetailsFrame(header, F1DetailSections.Participant, details)];
    }

    /// <summary>Event: 세션 경계는 마커로, 그 밖의 코드는 게임 이벤트로(버튼 상태는 버린다). 충돌 강도·부분 모드 이유는 2026 형식에만 있다(2025는 기본값).</summary>
    private IReadOnlyList<ITelemetryFrame> MapEventFrames(EventDataPacket packet, Season2026EventExtras extras)
    {
        if (MapEvent(packet) is { } marker)
        {
            return [marker];
        }

        if (F1GameEvents.Map(packet, extras) is not { } gameEvent)
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
