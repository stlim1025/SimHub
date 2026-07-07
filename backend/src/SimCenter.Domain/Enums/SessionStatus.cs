namespace SimCenter.Domain.Enums;

/// <summary>
/// DrivingSession 상태(D-10). Rig당 Active 세션은 1개만 허용(부분 유니크 인덱스로 보장).
/// </summary>
public enum SessionStatus
{
    Active = 0,
    Ended = 1,
}
