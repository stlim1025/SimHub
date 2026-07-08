namespace SimCenter.Api.Hubs;

/// <summary>RankingHub 그룹 이름 규약(05 §3.1). 트랙 랭킹 구독 그룹과 개인 알림 그룹.</summary>
public static class RankingGroups
{
    public static string Track(Guid trackId) => $"track:{trackId}";

    public static string User(Guid userId) => $"user:{userId}";
}
