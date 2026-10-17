namespace SimCenter.Domain.Enums;

/// <summary>
/// 세션의 상세 종류(P7). 기존 <see cref="SessionType"/>(Practice·Qualifying·Race…)보다 세분화한 값이다
/// (예: 연습 1/2/3, 퀄리 1/2/3, 스프린트 슈트아웃, 스프린트 레이스).
/// 0번(<see cref="Unknown"/>)은 "모름" 대체값이다. Agent.Core의 같은 이름 enum과 이름·순서를 맞춘다. DB에는 문자열로 저장한다.
/// </summary>
public enum SessionKind
{
    Unknown = 0,
    Practice1 = 1,
    Practice2 = 2,
    Practice3 = 3,
    ShortPractice = 4,
    Qualifying1 = 5,
    Qualifying2 = 6,
    Qualifying3 = 7,
    ShortQualifying = 8,
    OneShotQualifying = 9,
    SprintShootout1 = 10,
    SprintShootout2 = 11,
    SprintShootout3 = 12,
    ShortSprintShootout = 13,
    OneShotSprintShootout = 14,
    Race = 15,
    Race2 = 16,
    Race3 = 17,
    TimeTrial = 18,
}
