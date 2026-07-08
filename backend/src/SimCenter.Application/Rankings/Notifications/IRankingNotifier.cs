namespace SimCenter.Application.Rankings.Notifications;

/// <summary>
/// Backend → App 실시간 브로드캐스트 포트(05 §3). Application은 SignalR에 무의존이며, 구현은 Api 계층이
/// <c>IHubContext&lt;RankingHub&gt;</c>로 제공한다(의존 방향 Api → Application 유지).
/// 모든 호출은 인입 커밋 이후 best-effort로 수행되고, 실패해도 랩 저장/Ack에는 영향을 주지 않는다.
/// </summary>
public interface IRankingNotifier
{
    /// <summary>트랙 그룹(track:{trackId})에 갱신된 TOP N 스냅샷을 브로드캐스트한다.</summary>
    Task RankingUpdatedAsync(RankingSnapshotDto snapshot, CancellationToken cancellationToken = default);

    /// <summary>사용자 그룹(user:{userId})에 새 랩 기록 신호를 보낸다(내 랩 목록 갱신 트리거).</summary>
    Task LapRecordedAsync(LapRecordedNotice notice, CancellationToken cancellationToken = default);

    /// <summary>사용자 그룹(user:{userId})에 개인 최고 갱신을 알린다.</summary>
    Task PersonalBestAchievedAsync(PersonalBestNotice notice, CancellationToken cancellationToken = default);
}

/// <summary>LapRecorded payload(05 §3.4, shared/schema/lap_recorded.json).</summary>
public sealed record LapRecordedNotice(
    Guid LapId,
    Guid UserId,
    Guid TrackId,
    string SessionType,
    int LapTimeMs,
    bool IsValid,
    bool IsRankingEligible);

/// <summary>PersonalBestAchieved payload(05 §3.4, shared/schema/personal_best_achieved.json).</summary>
public sealed record PersonalBestNotice(Guid UserId, Guid TrackId, int LapTimeMs, int? PreviousBestMs);
