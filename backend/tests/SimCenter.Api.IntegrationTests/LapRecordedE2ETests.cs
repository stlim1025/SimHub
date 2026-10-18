using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using SimCenter.Api.Hubs;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 새 랩 실시간 표시(docs/15 §9, D-50): Agent → TelemetryHub → DB → RankingHub <c>LapRecorded</c>.
/// 랩 주인의 연결만 받고, 페이로드는 <c>GET /me/laps</c>의 항목과 같은 필드 + <c>trackId</c>다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class LapRecordedE2ETests : IClassFixture<ApiFactory>
{
    private static readonly TimeSpan HubWaitTimeout = TimeSpan.FromSeconds(10);

    /// <summary>주인이 받은 뒤 다른 사용자에게 잘못 갈 메시지를 기다려 보는 시간.</summary>
    private static readonly TimeSpan StrayMessageWait = TimeSpan.FromMilliseconds(500);

    private static readonly DateTime OccurredAt = new(2026, 10, 18, 11, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public LapRecordedE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task LapFinished_SendsLapRecorded_OnlyToOwner_WithMyLapsItemPlusTrackId()
    {
        // 1. 주인: 로그인 + 장치 연결 + RankingHub(쿼리 토큰, 앱과 같은 방식).
        var owner = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(owner);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(owner, "LIVE-LAP-PC");
        var ownerReceived = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var ownerHub = TestApi.BuildRankingConnectionWithQueryToken(_factory, BearerToken(owner));
        ownerHub.On<JsonElement>(RankingHubEvents.LapRecorded, lap => ownerReceived.TrySetResult(lap));
        await ownerHub.StartAsync();

        // 2. 다른 사용자도 RankingHub에 붙어 같은 이벤트를 듣는다.
        var other = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(other);
        var otherReceived = 0;
        await using var otherHub = TestApi.BuildRankingConnectionWithQueryToken(_factory, BearerToken(other));
        otherHub.On<JsonElement>(RankingHubEvents.LapRecorded, _ => Interlocked.Increment(ref otherReceived));
        await otherHub.StartAsync();

        // 3. 주인의 장치가 차량·날씨·트레이스를 실은 랩을 보낸다.
        await using var telemetry = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await telemetry.StartAsync();
        var envelope = LapDetailPayloads.LapFinished(
            lapNumber: 6, lapTimeMs: 98_448, isValid: true, OccurredAt,
            car: LapDetailPayloads.Car(), conditions: LapDetailPayloads.Conditions(), trace: LapDetailPayloads.Trace().ToWire());
        var ack = await telemetry.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);

        // 4. 주인은 새로고침 없이 그 랩을 받는다.
        var pushed = await ownerReceived.Task.WaitAsync(HubWaitTimeout);
        await Task.Delay(StrayMessageWait);
        Assert.Equal(0, Volatile.Read(ref otherReceived));

        // 5. 페이로드 = GET /me/laps 항목(모든 필드가 같다) + trackId.
        var list = await owner.GetFromJsonAsync<JsonElement>("/api/v1/me/laps");
        var item = Assert.Single(list.GetProperty("laps").GetProperty("items").EnumerateArray());
        foreach (var property in item.EnumerateObject())
        {
            Assert.True(pushed.TryGetProperty(property.Name, out var value), $"LapRecorded에 {property.Name}가 없다");
            Assert.True(JsonElement.DeepEquals(property.Value, value), $"{property.Name}: REST={property.Value} hub={value}");
        }

        var trackId = await FindTrackIdAsync(owner, "Jeddah");
        Assert.Equal(trackId, pushed.GetProperty("trackId").GetGuid());
        Assert.Equal(98_448, pushed.GetProperty("lapTimeMs").GetInt32());
        Assert.True(pushed.GetProperty("hasTrace").GetBoolean());
        Assert.Equal("LightCloud", pushed.GetProperty("weather").GetString());
        Assert.Equal(JsonValueKind.Object, pushed.GetProperty("team").ValueKind);
        Assert.False(pushed.TryGetProperty("userId", out _)); // 받는 사람이 주인뿐이라 싣지 않는다.
    }

    [Fact]
    public async Task RankingHub_WithoutToken_IsRejected()
    {
        // 익명 연결은 허브에 붙지 못하므로 개인 메시지를 받을 길이 없다.
        await using var anonymous = TestApi.BuildRankingConnectionWithQueryToken(_factory, accessToken: string.Empty);
        await Assert.ThrowsAnyAsync<Exception>(() => anonymous.StartAsync());
    }

    private static string BearerToken(HttpClient client) => client.DefaultRequestHeaders.Authorization!.Parameter!;

    private static async Task<Guid> FindTrackIdAsync(HttpClient client, string name)
    {
        var tracks = await client.GetFromJsonAsync<JsonElement>("/api/v1/tracks");
        return tracks.GetProperty("items").EnumerateArray()
            .Single(t => t.GetProperty("name").GetString() == name)
            .GetProperty("trackId").GetGuid();
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
