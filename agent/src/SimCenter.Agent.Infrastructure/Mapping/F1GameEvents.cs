using System.Buffers.Binary;
using System.Text;
using F1Game.UDP.Packets;
using F1Events = F1Game.UDP.Events;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// Event(3) 패킷 → 게임 이벤트(<c>car.details.events[]</c>, D-49 docs/15 §8). 코드는 4글자 ASCII(<c>PENA</c> 등), 상세 키는 <c>f1_25_udp_spec.md</c> §7.
/// 차 번호는 원시 carIndex(플레이어는 <c>details.lapData.carIndex</c>), 시간은 ms 정수로 바꾼다. 세션 시작·종료(SSTA·SEND)는 세션 경계 마커가 맡고,
/// 버튼 상태(BUTN)는 입력 장치 상태라 싣지 않는다. 라이브러리가 모르는 코드는 상세 없이 코드만 싣는다.
/// </summary>
internal static class F1GameEvents
{
    private const int MillisecondsPerSecond = 1000;
    private const int CodeLength = 4;

    /// <summary>싣지 않는 이벤트면 null.</summary>
    public static (string Code, IReadOnlyDictionary<string, object?> Details)? Map(EventDataPacket packet)
    {
        var details = packet.EventDetails;
        return details.EventType switch
        {
            F1Events.EventType.SessionStarted or F1Events.EventType.SessionEnded or F1Events.EventType.ButtonStatus => null,
            _ => (CodeOf(details.EventType), DetailsOf(details)),
        };
    }

    /// <summary>이벤트 종류 값은 4글자 코드의 리틀 엔디언 정수다(예: <c>PENA</c> = 0x414E4550).</summary>
    internal static string CodeOf(F1Events.EventType type)
    {
        Span<byte> bytes = stackalloc byte[CodeLength];
        BinaryPrimitives.WriteUInt32LittleEndian(bytes, unchecked((uint)type));
        return Encoding.ASCII.GetString(bytes);
    }

    private static IReadOnlyDictionary<string, object?> DetailsOf(F1Events.EventDetails details)
    {
        var bag = new DetailBag();
        if (details.TryGetPenaltyEvent(out var penalty))
        {
            bag.Add("penaltyType", (int)penalty.PenaltyType)
                .Add("infringementType", (int)penalty.InfringementType)
                .Add("vehicleIndex", penalty.VehicleIdx)
                .Add("otherVehicleIndex", penalty.OtherVehicleIdx)
                .Add("timeS", penalty.Time)
                .Add("lapNumber", penalty.LapNum)
                .Add("placesGained", penalty.PlacesGained);
        }
        else if (details.TryGetFastestLapEvent(out var fastest))
        {
            bag.Add("vehicleIndex", fastest.VehicleIdx).Add("lapTimeMs", SecondsToMs(fastest.LapTime));
        }
        else if (details.TryGetRetirementEvent(out var retirement))
        {
            bag.Add("vehicleIndex", retirement.VehicleIdx).Add("reason", (int)retirement.Reason);
        }
        else if (details.TryGetDrsDisabledEvent(out var drsDisabled))
        {
            bag.Add("reason", (int)drsDisabled.Reason);
        }
        else if (details.TryGetTeamMateInPitsEvent(out var teamMate))
        {
            bag.Add("vehicleIndex", teamMate.VehicleIdx);
        }
        else if (details.TryGetRaceWinnerEvent(out var winner))
        {
            bag.Add("vehicleIndex", winner.VehicleIdx);
        }
        else if (details.TryGetSpeedTrapEvent(out var speedTrap))
        {
            bag.Add("vehicleIndex", speedTrap.VehicleIdx)
                .Add("speedKph", speedTrap.Speed)
                .Add("overallFastestInSession", speedTrap.IsOverallFastestInSession)
                .Add("driverFastestInSession", speedTrap.IsDriverFastestInSession)
                .Add("fastestVehicleIndexInSession", speedTrap.FastestVehicleIdxInSession)
                .Add("fastestSpeedInSessionKph", speedTrap.FastestSpeedInSession);
        }
        else
        {
            AddOtherDetails(bag, details);
        }

        return bag.Build();
    }

    private static void AddOtherDetails(DetailBag bag, F1Events.EventDetails details)
    {
        if (details.TryGetStartLightsEvent(out var lights))
        {
            bag.Add("numLights", lights.NumLights);
        }
        else if (details.TryGetDriveThroughPenaltyServedEvent(out var driveThrough))
        {
            bag.Add("vehicleIndex", driveThrough.VehicleIdx);
        }
        else if (details.TryGetStopGoPenaltyServedEvent(out var stopGo))
        {
            bag.Add("vehicleIndex", stopGo.VehicleIdx).Add("stopTimeMs", SecondsToMs(stopGo.StopTime));
        }
        else if (details.TryGetFlashbackEvent(out var flashback))
        {
            bag.Add("flashbackFrameIdentifier", flashback.FlashbackFrameIdentifier)
                .Add("flashbackSessionTimeMs", SecondsToMs(flashback.FlashbackSessionTime));
        }
        else if (details.TryGetOvertakeEvent(out var overtake))
        {
            bag.Add("overtakingVehicleIndex", overtake.OvertakingVehicleIdx)
                .Add("beingOvertakenVehicleIndex", overtake.BeingOvertakenVehicleIdx);
        }
        else if (details.TryGetSafetyCarEvent(out var safetyCar))
        {
            bag.Add("safetyCarType", (int)safetyCar.SafetyCarType).Add("eventType", (int)safetyCar.EventType);
        }
        else if (details.TryGetCollisionEvent(out var collision))
        {
            bag.Add("vehicle1Index", collision.Vehicle1Index).Add("vehicle2Index", collision.Vehicle2Index);
        }
    }

    /// <summary>초(float) → ms 정수(사사오입). 유한하지 않거나 int 범위 밖이면 null.</summary>
    private static int? SecondsToMs(float seconds)
    {
        var milliseconds = Math.Round((double)seconds * MillisecondsPerSecond, MidpointRounding.AwayFromZero);
        return double.IsFinite(milliseconds) && milliseconds is >= int.MinValue and <= int.MaxValue ? (int)milliseconds : null;
    }
}
