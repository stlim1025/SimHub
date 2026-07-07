namespace SimCenter.Domain.Enums;

/// <summary>
/// 게임 세션 모드(D-16). 실시간 랭킹은 <see cref="TimeTrial"/>만 대상으로 하며,
/// 그 외 세션의 랩도 저장하되 랭킹에서는 제외한다(개별 조회는 가능).
/// 도메인은 게임 중립이므로 게임별 모드는 이 열거형으로 정규화해 매핑한다.
/// </summary>
public enum SessionType
{
    Unknown = 0,
    TimeTrial = 1,
    Practice = 2,
    Qualifying = 3,
    Race = 4,
}
