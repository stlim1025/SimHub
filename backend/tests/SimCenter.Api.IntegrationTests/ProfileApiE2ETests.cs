using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Api.RateLimiting;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 프로필·설정 API(14 §5)와 랭킹 이름 비공개(D-39, 14 §6) E2E. 실 PostgreSQL(테스트 DB `simcenter_test`)이 필요하다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class ProfileApiE2ETests : IClassFixture<ApiFactory>
{
    private const string Password = "P@ssw0rd!";
    private const string AnonymousName = "익명 드라이버";
    private const int MonacoGameTrackId = 5;
    private const int HiddenLapTimeMs = 50_123;
    private static readonly TimeSpan HubWaitTimeout = TimeSpan.FromSeconds(10);

    private readonly ApiFactory _factory;

    public ProfileApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task GetMe_NewUser_ReturnsDefaultSettings()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var me = await client.GetFromJsonAsync<JsonElement>("/api/v1/me");

        Assert.True(me.GetProperty("showOnLeaderboard").GetBoolean());
        Assert.Equal(JsonValueKind.Null, me.GetProperty("avatarTeam").ValueKind);
        Assert.Equal("F1_25", me.GetProperty("preferredGame").GetString());
        Assert.Equal("Wheel", me.GetProperty("controller").GetString());
        Assert.Equal("Pc", me.GetProperty("console").GetString());
        Assert.Equal("Metric", me.GetProperty("units").GetString());
        Assert.Equal("Asia/Seoul", me.GetProperty("timeZoneId").GetString());
        Assert.Equal("Dark", me.GetProperty("theme").GetString());
    }

    [Fact]
    public async Task UpdateProfile_Saves_AndGetMeReflectsIt()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        using var response = await client.PutAsJsonAsync("/api/v1/me/profile", ProfileBody(
            displayName: "  lemonary  ", showOnLeaderboard: false, avatarTeam: "mcl", theme: "System"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var saved = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("lemonary", saved.GetProperty("displayName").GetString());
        Assert.Equal("MCL", saved.GetProperty("avatarTeam").GetString());

        var me = await client.GetFromJsonAsync<JsonElement>("/api/v1/me");
        Assert.Equal("lemonary", me.GetProperty("displayName").GetString());
        Assert.False(me.GetProperty("showOnLeaderboard").GetBoolean());
        Assert.Equal("MCL", me.GetProperty("avatarTeam").GetString());
        Assert.Equal("Gamepad", me.GetProperty("controller").GetString());
        Assert.Equal("PlayStation", me.GetProperty("console").GetString());
        Assert.Equal("Imperial", me.GetProperty("units").GetString());
        Assert.Equal("Europe/London", me.GetProperty("timeZoneId").GetString());
        Assert.Equal("System", me.GetProperty("theme").GetString());
    }

    [Fact]
    public async Task UpdateProfile_InvalidValues_Return400WithFieldErrors()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        using var response = await client.PutAsJsonAsync("/api/v1/me/profile", ProfileBody(
            displayName: " ", avatarTeam: "XYZ", controller: "Joystick", timeZoneId: "Mars/Olympus"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("https://simcenter/errors/validation", problem.GetProperty("type").GetString());
        var errors = problem.GetProperty("errors");
        foreach (var field in new[] { "displayName", "avatarTeam", "controller", "timeZoneId" })
        {
            Assert.True(errors.TryGetProperty(field, out _), field);
        }

        // 저장되지 않았다.
        var me = await client.GetFromJsonAsync<JsonElement>("/api/v1/me");
        Assert.Equal("Wheel", me.GetProperty("controller").GetString());
    }

    [Fact]
    public async Task ProfileEndpoints_WithoutToken_Return401()
    {
        var client = _factory.CreateClient();

        using var put = await client.PutAsJsonAsync("/api/v1/me/profile", ProfileBody());
        using var post = await client.PostAsJsonAsync("/api/v1/me/email", new { newEmail = "a@b.com", currentPassword = Password });

        Assert.Equal(HttpStatusCode.Unauthorized, put.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, post.StatusCode);
    }

    [Fact]
    public async Task ChangeEmail_WrongPassword_Returns400OnCurrentPassword()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        using var response = await client.PostAsJsonAsync("/api/v1/me/email",
            new { newEmail = UniqueEmail(), currentPassword = "WrongP@ss1" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(problem.GetProperty("errors").TryGetProperty("currentPassword", out _));
    }

    [Fact]
    public async Task ChangeEmail_ExceedingPerUserLimit_Returns429_AndOtherUserIsUnaffected()
    {
        var heavyUser = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(heavyUser);
        var otherUser = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(otherUser);
        var wrongPassword = new { newEmail = UniqueEmail(), currentPassword = "WrongP@ss1" };

        for (var i = 0; i < RateLimitPolicies.PermitLimit; i++)
        {
            using var allowed = await heavyUser.PostAsJsonAsync("/api/v1/me/email", wrongPassword);
            Assert.Equal(HttpStatusCode.BadRequest, allowed.StatusCode); // 한도 안: 비밀번호 검사(400)까지 도달.
        }

        using var limited = await heavyUser.PostAsJsonAsync("/api/v1/me/email", wrongPassword);
        using var unaffected = await otherUser.PostAsJsonAsync("/api/v1/me/email", wrongPassword);

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, unaffected.StatusCode);
    }

    [Fact]
    public async Task UpdateProfile_StoresCanonicalTimeZoneId()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        using var response = await client.PutAsJsonAsync("/api/v1/me/profile", ProfileBody(timeZoneId: "america/new_york"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("America/New_York", (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("timeZoneId").GetString());
    }

    [Fact]
    public async Task ChangeEmail_TakenEmail_Returns409()
    {
        var other = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(other);
        var takenEmail = (await other.GetFromJsonAsync<JsonElement>("/api/v1/me")).GetProperty("email").GetString();

        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        using var response = await client.PostAsJsonAsync("/api/v1/me/email",
            new { newEmail = takenEmail!.ToUpperInvariant(), currentPassword = Password });

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task ChangeEmail_Success_UpdatesMe_AndNewEmailCanLogIn()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var newEmail = UniqueEmail();

        using var response = await client.PostAsJsonAsync("/api/v1/me/email",
            new { newEmail = $"  {newEmail.ToUpperInvariant()} ", currentPassword = Password });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(newEmail, (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("email").GetString());
        Assert.Equal(newEmail, (await client.GetFromJsonAsync<JsonElement>("/api/v1/me")).GetProperty("email").GetString());

        using var login = await TestApi.LoginAsync(_factory.CreateClient(), newEmail, Password);
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
    }

    [Fact]
    public async Task HiddenUser_RankingRestAndHubSnapshot_ShowAnonymousName()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        using (var put = await client.PutAsJsonAsync("/api/v1/me/profile", ProfileBody(displayName: "숨은 드라이버", showOnLeaderboard: false)))
        {
            put.EnsureSuccessStatusCode();
        }

        var trackId = await FindTrackIdAsync(client, "Monaco");
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-PRIVACY-PC");

        // 1. 앱처럼 RankingHub에 JWT로 접속해 트랙 그룹을 구독한다.
        var snapshotReceived = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var rankingHub = BuildRankingConnection(client.DefaultRequestHeaders.Authorization!.Parameter!);
        rankingHub.On<JsonElement>("RankingUpdated", snapshot => snapshotReceived.TrySetResult(snapshot));
        await rankingHub.StartAsync();
        await rankingHub.InvokeAsync("SubscribeTrack", trackId);

        // 2. 이번 달(서버 랭킹 타임존 기준)에 매우 빠른 Time Trial 랩을 보낸다 → 월별 TOP10 1위.
        await using var telemetry = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await telemetry.StartAsync();
        var ack = await telemetry.InvokeAsync<SubmitAck>("SubmitEvent", LapEnvelope(DateTime.UtcNow.AddMinutes(-1)));
        Assert.True(ack.Acknowledged, ack.RejectReason);

        // 3. RankingUpdated 스냅샷: 내 랩 항목의 이름이 익명이다.
        var pushed = await snapshotReceived.Task.WaitAsync(HubWaitTimeout);
        AssertHiddenEntry(pushed);

        // 4. REST /rankings(같은 기본 기간 monthly)도 익명이다.
        var rest = await client.GetFromJsonAsync<JsonElement>($"/api/v1/rankings?trackId={trackId}&period=monthly");
        AssertHiddenEntry(rest);

        // 5. 다시 공개로 바꾸면 이름이 보인다.
        using (var put = await client.PutAsJsonAsync("/api/v1/me/profile", ProfileBody(displayName: "숨은 드라이버", showOnLeaderboard: true)))
        {
            put.EnsureSuccessStatusCode();
        }

        var shown = await client.GetFromJsonAsync<JsonElement>($"/api/v1/rankings?trackId={trackId}&period=monthly");
        Assert.Equal("숨은 드라이버", FindEntry(shown).GetProperty("displayName").GetString());
    }

    private static void AssertHiddenEntry(JsonElement snapshot)
    {
        var entry = FindEntry(snapshot);
        Assert.Equal(AnonymousName, entry.GetProperty("displayName").GetString());
        Assert.Equal(1, entry.GetProperty("rank").GetInt32());
        Assert.DoesNotContain(snapshot.GetProperty("entries").EnumerateArray(),
            e => e.GetProperty("displayName").GetString() == "숨은 드라이버");
    }

    private static JsonElement FindEntry(JsonElement snapshot)
        => Assert.Single(snapshot.GetProperty("entries").EnumerateArray(),
            e => e.GetProperty("bestLapTimeMs").GetInt32() == HiddenLapTimeMs);

    private static async Task<Guid> FindTrackIdAsync(HttpClient client, string name)
    {
        var tracks = await client.GetFromJsonAsync<JsonElement>("/api/v1/tracks?gameCode=F1_25");
        return tracks.GetProperty("items").EnumerateArray()
            .Single(t => t.GetProperty("name").GetString() == name)
            .GetProperty("trackId").GetGuid();
    }

    private static object ProfileBody(
        string displayName = "E2E 드라이버",
        bool showOnLeaderboard = true,
        string? avatarTeam = null,
        string controller = "Gamepad",
        string timeZoneId = "Europe/London",
        string theme = "Light") => new
    {
        displayName,
        showOnLeaderboard,
        avatarTeam,
        preferredGame = "F1_25",
        controller,
        console = "PlayStation",
        units = "Imperial",
        timeZoneId,
        theme,
    };

    private static string UniqueEmail() => $"e2e-{Guid.NewGuid():N}@simcenter.test";

    private static object LapEnvelope(DateTime occurredAt) => new
    {
        eventId = Guid.NewGuid(),
        gameCode = "F1_25",
        occurredAt,
        type = "LapFinished",
        payload = new
        {
            sessionRef = "0xPRIVACY",
            lapNumber = 2,
            lapTimeMs = HiddenLapTimeMs,
            sectors = new[]
            {
                new { sectorNumber = 1, sectorTimeMs = 16_041 },
                new { sectorNumber = 2, sectorTimeMs = 17_041 },
                new { sectorNumber = 3, sectorTimeMs = 17_041 },
            },
            isValid = true,
            isOutOrInLap = false,
            trackId = MonacoGameTrackId,
            sessionType = "TimeTrial",
        },
    };

    /// <summary>앱과 같은 방식(JWT)으로 RankingHub에 WebSocket 접속한다(시작은 호출자가 한다).</summary>
    private HubConnection BuildRankingConnection(string accessToken)
        => new HubConnectionBuilder()
            .WithUrl(new Uri(_factory.Server.BaseAddress, "hubs/ranking"), options =>
            {
                options.Transports = HttpTransportType.WebSockets;
                options.SkipNegotiation = true;
                options.WebSocketFactory = async (context, cancellationToken) =>
                {
                    var webSocketClient = _factory.Server.CreateWebSocketClient();
                    webSocketClient.ConfigureRequest = request => request.Headers["Authorization"] = $"Bearer {accessToken}";
                    return await webSocketClient.ConnectAsync(context.Uri, cancellationToken);
                };
            })
            .AddJsonProtocol(json => json.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase)
            .Build();

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
