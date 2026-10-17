namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 게임 모드(P7, D-29). 백엔드 Domain의 <c>GameMode</c>와 이름·순서를 맞춘다(직렬화 시 문자열 — <see cref="SessionType"/>과 같은 방식).
/// 게임별 원시 모드 값은 Infrastructure 매퍼가 이 값으로 정규화한다. 0번(<see cref="Other"/>)은 "모름/그 밖" 대체값이다.
/// </summary>
public enum GameMode
{
    Other = 0,
    DriverCareer = 1,
    MyTeamCareer = 2,
    OnlineCareer = 3,
    ChallengeCareer = 4,
    GrandPrix = 5,
    TimeTrial = 6,
    Online = 7,
    Story = 8,
}
