using F1Game.UDP.Data;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// 참가자 칸(형식 무관). 2026 형식은 드라이버·네트워크·팀 ID가 2바이트라(2026 시즌팩 팀 476~) 25.1.1 구조체의 1바이트 칸에 담기지 않는다 —
/// 그 셋과 이름은 칸 밖에 싣고, 나머지는 <see cref="Data"/>에서 읽는다.
/// </summary>
internal readonly record struct ParticipantSlot(ParticipantData Data, string Name, int DriverId, bool IsNetworkHuman, int NetworkId, int TeamId)
{
    /// <summary>2025 형식 참가자 칸.</summary>
    public static ParticipantSlot[] From(ReadOnlySpan<ParticipantData> slots)
    {
        var mapped = new ParticipantSlot[slots.Length];
        for (var i = 0; i < slots.Length; i++)
        {
            var slot = slots[i];
            mapped[i] = new ParticipantSlot(
                slot,
                slot.Name ?? string.Empty,
                (int)slot.Driver,
                slot.Driver == F1Enums.Driver.NetworkHuman,
                slot.NetworkId,
                (int)slot.Team);
        }

        return mapped;
    }
}

/// <summary>Time Trial 데이터 세트(형식 무관). 2026 형식은 팀 ID가 2바이트라 칸 밖에 싣는다.</summary>
internal readonly record struct TimeTrialSet(TimeTrialDataSet Data, int TeamId)
{
    /// <summary>2025 형식 세트.</summary>
    public static TimeTrialSet From(TimeTrialDataSet set) => new(set, (int)set.Team);
}
