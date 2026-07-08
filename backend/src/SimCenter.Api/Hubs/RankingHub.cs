using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace SimCenter.Api.Hubs;

/// <summary>
/// Backend → App 읽기 전용 브로드캐스트 Hub(05 §3). 사용자 JWT로만 접속 가능(TelemetryHub와 신뢰수준 분리).
/// 연결 시 개인 알림 그룹(user:{userId})에 자동 가입하고, 관심 트랙은 <see cref="SubscribeTrack"/>로 구독한다.
/// </summary>
[Authorize]
public sealed class RankingHub : Hub
{
    public override async Task OnConnectedAsync()
    {
        var userId = GetUserId();
        if (userId is not null)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, RankingGroups.User(userId.Value));
        }

        await base.OnConnectedAsync();
    }

    /// <summary>해당 트랙 랭킹 갱신(RankingUpdated) 수신 그룹에 가입한다.</summary>
    public Task SubscribeTrack(Guid trackId)
        => Groups.AddToGroupAsync(Context.ConnectionId, RankingGroups.Track(trackId));

    /// <summary>트랙 랭킹 그룹에서 탈퇴한다.</summary>
    public Task UnsubscribeTrack(Guid trackId)
        => Groups.RemoveFromGroupAsync(Context.ConnectionId, RankingGroups.Track(trackId));

    private Guid? GetUserId()
    {
        var value = Context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? Context.User?.FindFirst("sub")?.Value;

        return Guid.TryParse(value, out var userId) ? userId : null;
    }
}
