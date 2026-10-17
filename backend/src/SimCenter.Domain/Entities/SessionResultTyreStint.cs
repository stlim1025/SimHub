using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 차 1대의 타이어 스틴트(P7). 최종 순위표는 세션당 한 번만 오므로 P7에서 저장해 둔다(P8 화면의 재료).
/// 재분류로 바뀌면 옛 스틴트는 soft delete하고 새 스틴트를 붙인다.
/// </summary>
public class SessionResultTyreStint : BaseEntity
{
    public Guid SessionResultId { get; set; }

    /// <summary>스틴트 번호(1부터).</summary>
    public int StintNumber { get; set; }

    /// <summary>그 스틴트가 끝난 랩.</summary>
    public int EndLap { get; set; }

    /// <summary>화면용 컴파운드(Soft·Medium·Hard·Intermediate·Wet).</summary>
    public TyreCompound VisualCompound { get; set; }

    /// <summary>게임 중립 문자열 라벨(예: "C3"). 없으면 null.</summary>
    public string? ActualCompound { get; set; }
}
