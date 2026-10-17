using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Seasons;

/// <summary>
/// 세션 키 생성 규칙(D-29). 같은 게임 세션의 결과가 다시 오면 같은 키가 나와야 재분류로 합쳐진다.
/// 순수 함수 — 상태 없음.
/// </summary>
public static class SessionKeys
{
    private const string LinkPrefix = "link:";
    private const string UidPrefix = "uid:";

    /// <summary>
    /// 시즌 대상(<see cref="SeasonPolicy.BelongsToSeason"/>)이고 세션 링크 식별자가 0이 아니면
    /// <c>link:{시즌}:{주말}:{세션}</c>, 그 밖에는 <see cref="Uid"/>(<c>uid:{sessionRef}</c>)다.
    /// </summary>
    public static string For(GameMode mode, long seasonLinkId, long weekendLinkId, long sessionLinkId, string sessionRef) =>
        SeasonPolicy.BelongsToSeason(mode, seasonLinkId, weekendLinkId) && sessionLinkId != 0
            ? $"{LinkPrefix}{seasonLinkId}:{weekendLinkId}:{sessionLinkId}"
            : Uid(sessionRef);

    /// <summary>게임 세션 UID 기반 키. 트랙·종류가 어긋난 세션의 대체 키로도 쓴다.</summary>
    public static string Uid(string sessionRef) => $"{UidPrefix}{sessionRef}";
}
