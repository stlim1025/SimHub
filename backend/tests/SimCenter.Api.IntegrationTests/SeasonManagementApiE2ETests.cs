using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 시즌 관리 API E2E: 이름 바꾸기(<c>PUT …/name</c>) · 완료 표시(<c>PUT …/completion</c>) · 삭제(<c>DELETE</c>).
/// 가입 → 장치 연결 → 허브로 레이스 1건을 보내 시즌을 만든 뒤 REST로 바꾸고 다시 읽는다. 실 PostgreSQL이 필요하다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class SeasonManagementApiE2ETests : IClassFixture<ApiFactory>
{
    private const string SeasonsUrl = "/api/v1/me/seasons";
    private const string SessionsUrl = "/api/v1/me/sessions";
    private const string ValidationErrorType = "https://simcenter/errors/validation";
    private const string NotFoundErrorType = "https://simcenter/errors/not-found";
    private const int NameMaxLength = 60;

    private const long SeasonLink = 51;
    private const long WeekendLink = 52;
    private const long FirstRaceLink = 53;
    private const long SecondWeekendLink = 54;
    private const long SecondRaceLink = 55;
    private const int GridSize = 4;
    private const int StintsPerCar = 1;

    private static readonly TimeSpan SeedAge = TimeSpan.FromMinutes(30);

    private readonly ApiFactory _factory;

    public SeasonManagementApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Rename_ThenListAndDetailShowName_AndBlankResets()
    {
        var seeded = await SeedSeasonAsync();

        // 처음에는 기본 이름(null), 완료 안 됨.
        var before = await GetSingleSummaryAsync(seeded.Client);
        Assert.Equal(JsonValueKind.Null, before.GetProperty("name").ValueKind);
        Assert.Equal(JsonValueKind.Null, before.GetProperty("completedAt").ValueKind);

        using (var renamed = await PutAsync(seeded.Client, $"{SeasonsUrl}/{seeded.SeasonId}/name", new { name = "  Ferrari Career  " }))
        {
            Assert.Equal(HttpStatusCode.NoContent, renamed.StatusCode);
        }

        Assert.Equal("Ferrari Career", (await GetSingleSummaryAsync(seeded.Client)).GetProperty("name").GetString());
        var detail = await GetOkAsync(seeded.Client, $"{SeasonsUrl}/{seeded.SeasonId}");
        Assert.Equal("Ferrari Career", detail.GetProperty("season").GetProperty("name").GetString());

        using (var reset = await PutAsync(seeded.Client, $"{SeasonsUrl}/{seeded.SeasonId}/name", new { name = "   " }))
        {
            Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);
        }

        Assert.Equal(JsonValueKind.Null, (await GetSingleSummaryAsync(seeded.Client)).GetProperty("name").ValueKind);
    }

    [Fact]
    public async Task Rename_TooLong_Returns400WithNameField()
    {
        var seeded = await SeedSeasonAsync();

        using var response = await PutAsync(
            seeded.Client, $"{SeasonsUrl}/{seeded.SeasonId}/name", new { name = new string('x', NameMaxLength + 1) });
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(ValidationErrorType, body.GetProperty("type").GetString());
        Assert.True(body.GetProperty("errors").TryGetProperty("name", out _), body.ToString());
    }

    [Fact]
    public async Task Completion_TrueThenFalse_ReflectedAsCompletedAt()
    {
        var seeded = await SeedSeasonAsync();
        var url = $"{SeasonsUrl}/{seeded.SeasonId}/completion";

        using (var complete = await PutAsync(seeded.Client, url, new { completed = true }))
        {
            Assert.Equal(HttpStatusCode.NoContent, complete.StatusCode);
        }

        var completedAt = (await GetSingleSummaryAsync(seeded.Client)).GetProperty("completedAt").GetDateTime();
        Assert.Equal(DateTimeKind.Utc, completedAt.Kind);
        Assert.True(completedAt > DateTime.UtcNow.AddMinutes(-5));

        // 다시 완료해도 처음 시각을 유지한다.
        using (var again = await PutAsync(seeded.Client, url, new { completed = true }))
        {
            Assert.Equal(HttpStatusCode.NoContent, again.StatusCode);
        }

        var detail = await GetOkAsync(seeded.Client, $"{SeasonsUrl}/{seeded.SeasonId}");
        Assert.Equal(completedAt, detail.GetProperty("season").GetProperty("completedAt").GetDateTime());

        using (var reopen = await PutAsync(seeded.Client, url, new { completed = false }))
        {
            Assert.Equal(HttpStatusCode.NoContent, reopen.StatusCode);
        }

        Assert.Equal(JsonValueKind.Null, (await GetSingleSummaryAsync(seeded.Client)).GetProperty("completedAt").ValueKind);
    }

    [Fact]
    public async Task Delete_ThenListExcludesAndDetail404_SessionLosesSeasonLink()
    {
        var seeded = await SeedSeasonAsync();

        using (var deleted = await seeded.Client.DeleteAsync($"{SeasonsUrl}/{seeded.SeasonId}"))
        {
            Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        }

        Assert.Equal(0, (await GetOkAsync(seeded.Client, SeasonsUrl)).GetProperty("total").GetInt32());
        using (var detail = await seeded.Client.GetAsync($"{SeasonsUrl}/{seeded.SeasonId}"))
        {
            Assert.Equal(HttpStatusCode.NotFound, detail.StatusCode);
        }

        // 세션은 남지만 지운 시즌을 가리키지 않는다.
        var session = Assert.Single((await GetOkAsync(seeded.Client, SessionsUrl)).GetProperty("items").EnumerateArray());
        Assert.Equal(JsonValueKind.Null, session.GetProperty("seasonId").ValueKind);
        var sessionDetail = await GetOkAsync(seeded.Client, $"{SessionsUrl}/{session.GetProperty("sessionId").GetGuid()}");
        Assert.Equal(JsonValueKind.Null, sessionDetail.GetProperty("session").GetProperty("seasonId").ValueKind);

        // 지운 시즌은 다시 바꾸거나 지울 수 없다.
        using (var rename = await PutAsync(seeded.Client, $"{SeasonsUrl}/{seeded.SeasonId}/name", new { name = "x" }))
        {
            Assert.Equal(HttpStatusCode.NotFound, rename.StatusCode);
        }

        using (var again = await seeded.Client.DeleteAsync($"{SeasonsUrl}/{seeded.SeasonId}"))
        {
            Assert.Equal(HttpStatusCode.NotFound, again.StatusCode);
        }
    }

    [Fact]
    public async Task Delete_ThenSameLinkArrives_RestoresSeason()
    {
        var seeded = await SeedSeasonAsync();
        using (var deleted = await seeded.Client.DeleteAsync($"{SeasonsUrl}/{seeded.SeasonId}"))
        {
            Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        }

        await using (var connection = await StartHubAsync(seeded.DeviceKey))
        {
            var payload = SessionClassifiedPayloads.Build(GridSize, StintsPerCar, SeasonLink, SecondWeekendLink, SecondRaceLink);
            await SendAsync(connection, payload, DateTime.UtcNow.AddMinutes(-1));
        }

        var summary = await GetSingleSummaryAsync(seeded.Client);
        Assert.Equal(seeded.SeasonId, summary.GetProperty("seasonId").GetGuid());
        Assert.Equal(2, summary.GetProperty("roundCount").GetInt32());
    }

    [Fact]
    public async Task OtherUsersSeason_Returns404_AndIsUnchanged()
    {
        var owner = await SeedSeasonAsync();
        var stranger = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(stranger);

        using var rename = await PutAsync(stranger, $"{SeasonsUrl}/{owner.SeasonId}/name", new { name = "Mine" });
        using var complete = await PutAsync(stranger, $"{SeasonsUrl}/{owner.SeasonId}/completion", new { completed = true });
        using var delete = await stranger.DeleteAsync($"{SeasonsUrl}/{owner.SeasonId}");

        foreach (var response in new[] { rename, complete, delete })
        {
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            var body = await response.Content.ReadFromJsonAsync<JsonElement>();
            Assert.Equal(NotFoundErrorType, body.GetProperty("type").GetString());
        }

        var summary = await GetSingleSummaryAsync(owner.Client);
        Assert.Equal(JsonValueKind.Null, summary.GetProperty("name").ValueKind);
        Assert.Equal(JsonValueKind.Null, summary.GetProperty("completedAt").ValueKind);
    }

    [Fact]
    public async Task UnknownSeason_Returns404()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var unknown = Guid.NewGuid();

        using var rename = await PutAsync(client, $"{SeasonsUrl}/{unknown}/name", new { name = "x" });
        using var complete = await PutAsync(client, $"{SeasonsUrl}/{unknown}/completion", new { completed = true });
        using var delete = await client.DeleteAsync($"{SeasonsUrl}/{unknown}");

        Assert.Equal(HttpStatusCode.NotFound, rename.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, complete.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, delete.StatusCode);
    }

    // ── 헬퍼 ──

    private sealed record SeededSeason(HttpClient Client, string DeviceKey, Guid SeasonId);

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);

    /// <summary>새 사용자·장치로 레이스 1건을 보내 시즌 1개를 만든다.</summary>
    private async Task<SeededSeason> SeedSeasonAsync()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-SEASON-MGMT-PC");

        await using (var connection = await StartHubAsync(deviceKey))
        {
            var payload = SessionClassifiedPayloads.Build(GridSize, StintsPerCar, SeasonLink, WeekendLink, FirstRaceLink);
            await SendAsync(connection, payload, DateTime.UtcNow - SeedAge);
        }

        var seasonId = (await GetSingleSummaryAsync(client)).GetProperty("seasonId").GetGuid();
        return new SeededSeason(client, deviceKey, seasonId);
    }

    private static async Task<JsonElement> GetSingleSummaryAsync(HttpClient client)
        => Assert.Single((await GetOkAsync(client, SeasonsUrl)).GetProperty("items").EnumerateArray());

    private static async Task<JsonElement> GetOkAsync(HttpClient client, string url)
    {
        using var response = await client.GetAsync(url);
        var text = await response.Content.ReadAsStringAsync();

        Assert.True(HttpStatusCode.OK == response.StatusCode, $"GET {url} → {response.StatusCode} {text}");
        return JsonSerializer.Deserialize<JsonElement>(text);
    }

    private static Task<HttpResponseMessage> PutAsync(HttpClient client, string url, object body)
        => client.PutAsJsonAsync(url, body);

    private async Task<HubConnection> StartHubAsync(string deviceKey)
    {
        var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        return connection;
    }

    private static async Task SendAsync(HubConnection connection, object payload, DateTime occurredAt)
    {
        var envelope = new
        {
            eventId = Guid.NewGuid(),
            gameCode = "F1_25",
            occurredAt,
            type = "SessionClassified",
            payload,
        };

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);

        Assert.True(ack.Acknowledged, ack.RejectReason);
    }
}
