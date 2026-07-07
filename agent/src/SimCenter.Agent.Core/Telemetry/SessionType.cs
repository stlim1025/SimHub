namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 게임중립 세션 유형. 백엔드 도메인의 SessionType과 이름을 일치시켜(직렬화 시 문자열) 그대로 매핑된다.
/// 실시간 랭킹은 TimeTrial만 대상(D-16). 게임별 세부 모드는 Infrastructure 매퍼가 이 5종으로 정규화한다.
/// </summary>
public enum SessionType
{
    Unknown = 0,
    TimeTrial = 1,
    Practice = 2,
    Qualifying = 3,
    Race = 4,
}
