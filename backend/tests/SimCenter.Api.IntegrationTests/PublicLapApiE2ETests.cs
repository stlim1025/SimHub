using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using SimCenter.Application.Rankings;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 공유 링크 랩(<c>GET /public/laps/{id}</c>·<c>/public/laps/{id}/trace</c>): 토큰 없이 읽고, 주인 이름은 랭킹과 같은 공개 규칙(D-39),
/// 이메일·사용자 ID는 없다. 없는 랩·트레이스 없는 랩은 404.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class PublicLapApiE2ETests : IClassFixture<ApiFactory>
{
    private const string OwnerName = "E2E 드라이버";
    private const int LapTimeMs = 98_448;

    private static readonly DateTime T0 = new(2026, 10, 19, 11, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public PublicLapApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task AnonymousViewer_ReadsDetailAndTrace_WithOwnerName()
    {
        var (_, withTrace, withoutTrace, sentTrace) = await SeedAsync();
        var anonymous = _factory.CreateClient();

        var detail = await anonymous.GetFromJsonAsync<JsonElement>($"/api/v1/public/laps/{withTrace}");

        Assert.Equal(withTrace, detail.GetProperty("lap").GetProperty("lapId").GetGuid());
        Assert.Equal(LapTimeMs, detail.GetProperty("lap").GetProperty("lapTimeMs").GetInt32());
        Assert.Equal("SA", detail.GetProperty("countryCode").GetString());
        Assert.Equal(OwnerName, detail.GetProperty("displayName").GetString());
        Assert.Equal(16, detail.GetProperty("car").GetProperty("visualTyreCompound").GetInt32());
        Assert.Equal("LightCloud", detail.GetProperty("conditions").GetProperty("weather").GetString());
        Assert.False(detail.TryGetProperty("userId", out _));
        Assert.False(detail.TryGetProperty("email", out _));
        Assert.False(detail.TryGetProperty("sessionId", out _));
        Assert.False(detail.TryGetProperty("comparison", out _));

        var trace = await anonymous.GetFromJsonAsync<JsonElement>($"/api/v1/public/laps/{withTrace}/trace");
        Assert.Equal(sentTrace.SpeedKph, trace.GetProperty("speedKph").EnumerateArray().Select(v => v.GetInt32()).ToArray());

        Assert.Equal(HttpStatusCode.NotFound, (await anonymous.GetAsync($"/api/v1/public/laps/{withoutTrace}/trace")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await anonymous.GetAsync($"/api/v1/public/laps/{Guid.NewGuid()}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await anonymous.GetAsync($"/api/v1/public/laps/{Guid.NewGuid()}/trace")).StatusCode);
    }

    [Fact]
    public async Task OwnerHidingName_IsShownAsAnonymousDriver()
    {
        var (owner, lapId, _, _) = await SeedAsync();
        using (var put = await owner.PutAsJsonAsync("/api/v1/me/profile", new
        {
            displayName = OwnerName,
            showOnLeaderboard = false,
            avatarTeam = (string?)null,
            preferredGame = "F1_25",
            controller = "Gamepad",
            console = "PlayStation",
            units = "Imperial",
            timeZoneId = "Europe/London",
            theme = "Light",
        }))
        {
            put.EnsureSuccessStatusCode();
        }

        var detail = await _factory.CreateClient().GetFromJsonAsync<JsonElement>($"/api/v1/public/laps/{lapId}");

        Assert.Equal(RankingPrivacy.AnonymousDisplayName, detail.GetProperty("displayName").GetString());
    }

    /// <summary>한 사용자로 Jeddah 랩 2개(스냅샷·날씨·트레이스 있는 랩 / 없는 랩)를 보낸다.</summary>
    private async Task<(HttpClient Owner, Guid WithTrace, Guid WithoutTrace, LapDetailPayloads.TraceChannels Trace)> SeedAsync()
    {
        var owner = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(owner);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(owner, "PUBLIC-LAP-PC");
        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();

        var trace = LapDetailPayloads.Trace();
        await SubmitAsync(connection, LapDetailPayloads.LapFinished(
            3, LapTimeMs + 1_000, isValid: true, T0));
        await SubmitAsync(connection, LapDetailPayloads.LapFinished(
            4, LapTimeMs, isValid: true, T0.AddMinutes(2), car: LapDetailPayloads.Car(),
            conditions: LapDetailPayloads.Conditions(), trace: trace.ToWire()));

        var laps = await owner.GetFromJsonAsync<JsonElement>("/api/v1/me/laps");
        var items = laps.GetProperty("laps").GetProperty("items").EnumerateArray().ToList(); // 최근 순
        return (owner, items[0].GetProperty("lapId").GetGuid(), items[1].GetProperty("lapId").GetGuid(), trace);
    }

    private static async Task SubmitAsync(HubConnection connection, object envelope)
    {
        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
