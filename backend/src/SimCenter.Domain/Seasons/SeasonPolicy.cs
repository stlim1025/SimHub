using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Seasons;

/// <summary>시즌 소속 판정(D-29). 순수 함수 — 상태 없음.</summary>
public static class SeasonPolicy
{
    /// <summary>
    /// 이 세션이 시즌·주말에 묶이는 대상인가? 시즌형 모드(커리어·그랑프리)이고
    /// 게임의 시즌·주말 링크 식별자가 모두 0이 아닐 때만 참이다.
    /// </summary>
    public static bool BelongsToSeason(GameMode mode, long seasonLinkId, long weekendLinkId) =>
        IsSeasonMode(mode) && seasonLinkId != 0 && weekendLinkId != 0;

    private static bool IsSeasonMode(GameMode mode) => mode is
        GameMode.DriverCareer or
        GameMode.MyTeamCareer or
        GameMode.OnlineCareer or
        GameMode.ChallengeCareer or
        GameMode.GrandPrix;
}
