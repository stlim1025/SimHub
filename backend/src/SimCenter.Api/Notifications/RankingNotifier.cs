using Microsoft.AspNetCore.SignalR;
using SimCenter.Api.Hubs;
using SimCenter.Application.Rankings;
using SimCenter.Application.Rankings.Notifications;

namespace SimCenter.Api.Notifications;

/// <summary>
/// IRankingNotifier의 SignalR 구현(05 §3.2). Application이 정의한 포트를 Api가 <see cref="IHubContext{RankingHub}"/>로 실현한다
/// (의존 방향 Api → Application 유지). 페이로드 직렬화는 Program.cs의 SignalR JSON 프로토콜(camelCase + enum 문자열)을 따른다.
/// </summary>
public sealed class RankingNotifier : IRankingNotifier
{
    private readonly IHubContext<RankingHub> _hub;

    public RankingNotifier(IHubContext<RankingHub> hub) => _hub = hub;

    public Task RankingUpdatedAsync(RankingSnapshotDto snapshot, CancellationToken cancellationToken = default)
        => _hub.Clients.Group(RankingGroups.Track(snapshot.TrackId))
            .SendAsync(RankingHubEvents.RankingUpdated, snapshot, cancellationToken);

    /// <summary>랩 주인의 연결에만 보낸다(D-50). 사용자 식별은 <see cref="JwtSubjectUserIdProvider"/>(JWT sub).</summary>
    public Task LapRecordedAsync(Guid userId, LapRecordedNotice notice, CancellationToken cancellationToken = default)
        => _hub.Clients.User(userId.ToString())
            .SendAsync(RankingHubEvents.LapRecorded, notice, cancellationToken);

    public Task PersonalBestAchievedAsync(PersonalBestNotice notice, CancellationToken cancellationToken = default)
        => _hub.Clients.Group(RankingGroups.User(notice.UserId))
            .SendAsync(RankingHubEvents.PersonalBestAchieved, notice, cancellationToken);
}
