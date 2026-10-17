namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 세션의 상세 종류(P7). 5종 <see cref="SessionType"/>보다 세분화한 값(연습 1/2/3, 퀄리 1/2/3, 스프린트 슈트아웃, 레이스 1/2/3 …).
/// 백엔드 Domain의 <c>SessionKind</c>와 이름·순서를 맞춘다. 0번(<see cref="Unknown"/>)은 "모름" 대체값이다.
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
