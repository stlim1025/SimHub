namespace SimCenter.Api.Hubs;

/// <summary>RankingHub 그룹 이름 규약(05 §3.1). 트랙 랭킹 구독 그룹과 개인 알림 그룹.</summary>
public static class RankingGroups
{
    public static string Track(Guid trackId) => $"track:{trackId}";

    public static string User(Guid userId) => $"user:{userId}";
}

/// <summary>RankingHub가 앱에 보내는 이벤트(메서드) 이름(05 §3.2).</summary>
public static class RankingHubEvents
{
    public const string RankingUpdated = "RankingUpdated";

    /// <summary>새 랩(LapDto + trackId)을 랩 주인에게만(docs/15 §9, D-50).</summary>
    public const string LapRecorded = "LapRecorded";

    public const string PersonalBestAchieved = "PersonalBestAchieved";
}
