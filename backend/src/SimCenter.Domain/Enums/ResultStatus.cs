namespace SimCenter.Domain.Enums;

/// <summary>
/// 세션 최종 순위표에서 차 1대의 결과 상태(P7).
/// 0번(<see cref="Unknown"/>)은 "모름" 대체값이다. Agent.Core의 같은 이름 enum과 이름·순서를 맞춘다. DB에는 문자열로 저장한다.
/// </summary>
public enum ResultStatus
{
    Unknown = 0,
    Active = 1,
    Finished = 2,
    DidNotFinish = 3,
    Disqualified = 4,
    NotClassified = 5,
    Retired = 6,
}
