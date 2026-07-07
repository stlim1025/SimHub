using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 앱 체크인 세션. 랩-사용자 귀속의 단위이며 Agent는 무상태다(D-2).
/// Rig당 Active 세션은 1개만 존재한다(부분 유니크 인덱스로 보장).
/// </summary>
public class DrivingSession : BaseEntity
{
    public Guid UserId { get; set; }
    public User? User { get; set; }

    public Guid SimRigId { get; set; }
    public SimRig? SimRig { get; set; }

    /// <summary>조회 편의를 위한 비정규화.</summary>
    public Guid StoreId { get; set; }

    /// <summary>게임 코드(예: "F1_25", D-14).</summary>
    public required string GameCode { get; set; }

    public SessionType SessionType { get; set; }

    public SessionStatus Status { get; set; }

    public DateTime StartedAt { get; set; }
    public DateTime? EndedAt { get; set; }

    public ICollection<Lap> Laps { get; set; } = new List<Lap>();
}
