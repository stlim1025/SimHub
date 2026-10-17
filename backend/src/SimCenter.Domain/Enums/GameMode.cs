namespace SimCenter.Domain.Enums;

/// <summary>
/// 게임 모드(P7, D-29). 시즌에 묶이는 모드는 <c>SeasonPolicy</c>가 판정한다.
/// 0번(<see cref="Other"/>)은 "모름/그 밖" 대체값이다 — 인입은 모르는 문자열을 이 값으로 받아들인다.
/// Agent.Core의 같은 이름 enum과 이름·순서를 맞춘다. DB에는 문자열로 저장한다.
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
