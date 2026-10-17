using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 시즌·세션 조회 API E2E(P7, 12 §7): 가입 → 장치 연결 → 허브로 <c>SessionClassified</c> 전송 → REST 조회.
/// 실 PostgreSQL(테스트 DB <c>simcenter_test</c>)이 필요하다. 테스트마다 새 사용자를 만들고 그 사용자의 데이터만 보므로
/// 같은 링크 식별자를 써도 서로 섞이지 않는다.
/// <para>
/// 시드(2라운드 × 예선1 + 레이스, 22대, 플레이어 = carIndex 2): 레이스 점수 = <c>max(0, 25 - 3 × carIndex)</c>, 예선 점수 = 0.
/// 그래서 1위(carIndex 0)는 50점, 플레이어는 라운드마다 3위·19점이라 합계 38점으로 시즌 3위다.
/// </para>
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class SeasonsApiE2ETests : IClassFixture<ApiFactory>
{
    private const string SeasonsUrl = "/api/v1/me/seasons";
    private const string SessionsUrl = "/api/v1/me/sessions";
    private const string ValidationErrorType = "https://simcenter/errors/validation";

    private const long SeasonLink = 11;
    private const long Round1WeekendLink = 22;
    private const long Round2WeekendLink = 23;
    private const long Round1QualifyingLink = 31;
    private const long Round1RaceLink = 33;
    private const long Round2QualifyingLink = 41;
    private const long Round2RaceLink = 43;

    private const int GridSize = 22;
    private const int StintsPerCar = 2;
    private const int PlayerCarIndex = 2;
    private const int PlayerPosition = 3;
    private const int PlayerRacePoints = 19;
    private const int PlayerSeasonPoints = 38;
    private const int PlayerBestLapMs = 81074;
    private const int LeaderSeasonPoints = 50;
    private const int RoundCount = 2;
    private const int SessionCount = 4;
    private const int SessionsPerRound = 2;
    private const int DefaultPageSize = 20;
    private const int MaxSeasonPageSize = 20;
    private const int MaxSessionPageSize = 100;
    private const int OversizedPageSize = 999;

    private static readonly TimeSpan SeedSpan = TimeSpan.FromMinutes(60);
    private static readonly TimeSpan SeedStep = TimeSpan.FromMinutes(10);

    private readonly ApiFactory _factory;

    public SeasonsApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task GetSeasons_NoData_ReturnsEmptyPage()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var (status, body) = await GetJsonAsync(client, SeasonsUrl);

        Assert.Equal(HttpStatusCode.OK, status);
        Assert.Equal(1, body.GetProperty("page").GetInt32());
        Assert.Equal(DefaultPageSize, body.GetProperty("pageSize").GetInt32());
        Assert.Equal(0, body.GetProperty("total").GetInt32());
        Assert.Equal(0, body.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task GetSessions_NoData_ReturnsEmptyPage()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var (status, body) = await GetJsonAsync(client, SessionsUrl);

        Assert.Equal(HttpStatusCode.OK, status);
        Assert.Equal(1, body.GetProperty("page").GetInt32());
        Assert.Equal(DefaultPageSize, body.GetProperty("pageSize").GetInt32());
        Assert.Equal(0, body.GetProperty("total").GetInt32());
        Assert.Equal(0, body.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task Lists_OutOfRangePaging_IsCorrected()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var seasons = await GetOkAsync(client, $"{SeasonsUrl}?page=0&pageSize={OversizedPageSize}");
        var sessions = await GetOkAsync(client, $"{SessionsUrl}?page=-5&pageSize={OversizedPageSize}");
        var defaultSize = await GetOkAsync(client, $"{SessionsUrl}?pageSize=0");

        Assert.Equal(1, seasons.GetProperty("page").GetInt32());
        Assert.Equal(MaxSeasonPageSize, seasons.GetProperty("pageSize").GetInt32());
        Assert.Equal(1, sessions.GetProperty("page").GetInt32());
        Assert.Equal(MaxSessionPageSize, sessions.GetProperty("pageSize").GetInt32());
        Assert.Equal(DefaultPageSize, defaultSize.GetProperty("pageSize").GetInt32());
    }

    [Fact]
    public async Task Seasons_AfterTwoRounds_ListAndDetail()
    {
        var seeded = await SeedTwoRoundSeasonAsync();

        // 목록: 시즌 1개, 라운드 2개, 내 순위·점수와 선두.
        var list = await GetOkAsync(seeded.Client, SeasonsUrl);
        Assert.Equal(1, list.GetProperty("total").GetInt32());
        var summary = Assert.Single(list.GetProperty("items").EnumerateArray());
        Assert.Equal("F1_25", summary.GetProperty("gameCode").GetString());
        Assert.Equal("DriverCareer", summary.GetProperty("gameMode").GetString());
        Assert.Equal(RoundCount, summary.GetProperty("roundCount").GetInt32());
        Assert.Equal(PlayerPosition, summary.GetProperty("myPosition").GetInt32());
        Assert.Equal(PlayerSeasonPoints, summary.GetProperty("myPoints").GetInt32());
        Assert.Equal("DRIVER 0", summary.GetProperty("leaderName").GetString());
        Assert.Equal(LeaderSeasonPoints, summary.GetProperty("leaderPoints").GetInt32());
        Assert.True(summary.GetProperty("firstSessionAt").GetDateTime() < summary.GetProperty("lastSessionAt").GetDateTime());
        var seasonId = summary.GetProperty("seasonId").GetGuid();

        // 상세: 헤더는 목록과 같고, 라운드 2개(각 세션 2개, ClassifiedAt 순), Standings 22명(각 칸 2개).
        var (status, detail) = await GetJsonAsync(seeded.Client, $"{SeasonsUrl}/{seasonId}");
        Assert.Equal(HttpStatusCode.OK, status);
        Assert.Equal(seasonId, detail.GetProperty("season").GetProperty("seasonId").GetGuid());
        Assert.Equal(PlayerSeasonPoints, detail.GetProperty("season").GetProperty("myPoints").GetInt32());

        var rounds = detail.GetProperty("rounds").EnumerateArray().ToList();
        Assert.Equal(RoundCount, rounds.Count);
        Assert.Equal(new[] { 1, 2 }, rounds.Select(r => r.GetProperty("round").GetInt32()).ToArray());
        Assert.All(rounds, round =>
        {
            Assert.Equal("Silverstone", round.GetProperty("trackName").GetString());
            Assert.Equal("DRIVER 0", round.GetProperty("winnerName").GetString());
            Assert.Equal(PlayerRacePoints, round.GetProperty("myPoints").GetInt32());

            var chips = round.GetProperty("sessions").EnumerateArray().ToList();
            Assert.Equal(SessionsPerRound, chips.Count);
            Assert.Equal("Qualifying", chips[0].GetProperty("sessionType").GetString());
            Assert.Equal("Qualifying1", chips[0].GetProperty("sessionKind").GetString());
            Assert.Equal("Race", chips[1].GetProperty("sessionType").GetString());
            Assert.Equal("Race", chips[1].GetProperty("sessionKind").GetString());
            Assert.All(chips, chip =>
            {
                Assert.Equal(PlayerPosition, chip.GetProperty("myPosition").GetInt32());
                Assert.Equal("Finished", chip.GetProperty("myResultStatus").GetString());
            });
        });
        Assert.True(rounds[0].GetProperty("firstSessionAt").GetDateTime() < rounds[1].GetProperty("firstSessionAt").GetDateTime());

        var drivers = detail.GetProperty("standings").GetProperty("drivers").EnumerateArray().ToList();
        Assert.Equal(GridSize, drivers.Count);
        Assert.All(drivers, driver => Assert.Equal(RoundCount, driver.GetProperty("cells").GetArrayLength()));
        Assert.Equal(Enumerable.Range(1, GridSize), drivers.Select(d => d.GetProperty("position").GetInt32()));

        var leader = drivers[0];
        Assert.Equal("driver:0", leader.GetProperty("driverKey").GetString());
        Assert.Equal(LeaderSeasonPoints, leader.GetProperty("points").GetInt32());
        Assert.Equal(RoundCount, leader.GetProperty("wins").GetInt32());
        Assert.Equal(RoundCount, leader.GetProperty("podiums").GetInt32());
        Assert.Equal("Mercedes", leader.GetProperty("teamName").GetString());
        Assert.Matches("^#[0-9A-Fa-f]{6}$", leader.GetProperty("teamColor").GetString()!);
        var leaderCell = leader.GetProperty("cells")[0];
        Assert.Equal(1, leaderCell.GetProperty("round").GetInt32());
        Assert.Equal(1, leaderCell.GetProperty("position").GetInt32());
        Assert.Equal("Finished", leaderCell.GetProperty("resultStatus").GetString());
        Assert.Equal(25, leaderCell.GetProperty("points").GetInt32());

        var player = drivers[PlayerPosition - 1];
        Assert.Equal("player", player.GetProperty("driverKey").GetString());
        Assert.True(player.GetProperty("isPlayer").GetBoolean());
        Assert.Equal(PlayerSeasonPoints, player.GetProperty("points").GetInt32());
        Assert.Equal(0, player.GetProperty("wins").GetInt32());
        Assert.Equal(RoundCount, player.GetProperty("podiums").GetInt32());

        var constructors = detail.GetProperty("standings").GetProperty("constructors").EnumerateArray().ToList();
        Assert.Equal(10, constructors.Count);
        Assert.Equal(1, constructors[0].GetProperty("position").GetInt32());
        Assert.Equal(0, constructors[0].GetProperty("teamId").GetInt32());
        Assert.Equal("Mercedes", constructors[0].GetProperty("teamName").GetString());
        Assert.Equal(LeaderSeasonPoints, constructors[0].GetProperty("points").GetInt32());
        Assert.Equal(RoundCount, constructors[0].GetProperty("wins").GetInt32());
    }

    [Fact]
    public async Task Sessions_ListFilterAndDetail()
    {
        var seeded = await SeedTwoRoundSeasonAsync();
        var seasonId = (await GetOkAsync(seeded.Client, SeasonsUrl))
            .GetProperty("items")[0].GetProperty("seasonId").GetGuid();

        // 목록: 4건, ClassifiedAt 내림차순(마지막 레이스 → 마지막 예선 → 첫 레이스 → 첫 예선).
        var list = await GetOkAsync(seeded.Client, $"{SessionsUrl}?pageSize=15");
        Assert.Equal(SessionCount, list.GetProperty("total").GetInt32());
        Assert.Equal(15, list.GetProperty("pageSize").GetInt32());
        var items = list.GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(SessionCount, items.Count);
        Assert.Equal(new[] { "Race", "Qualifying1", "Race", "Qualifying1" }, items.Select(i => i.GetProperty("sessionKind").GetString()).ToArray());
        var classifiedAt = items.Select(i => i.GetProperty("classifiedAt").GetDateTime()).ToList();
        Assert.Equal(classifiedAt.OrderByDescending(t => t), classifiedAt);

        var latestRace = items[0];
        Assert.Equal("Silverstone", latestRace.GetProperty("trackName").GetString());
        Assert.Equal("Race", latestRace.GetProperty("sessionType").GetString());
        Assert.Equal("DriverCareer", latestRace.GetProperty("gameMode").GetString());
        Assert.Equal(seasonId, latestRace.GetProperty("seasonId").GetGuid());
        Assert.Equal(GridSize, latestRace.GetProperty("carCount").GetInt32());
        Assert.Equal(PlayerPosition, latestRace.GetProperty("myPosition").GetInt32());
        Assert.Equal(PlayerPosition, latestRace.GetProperty("myGridPosition").GetInt32());
        Assert.Equal("Finished", latestRace.GetProperty("myResultStatus").GetString());
        Assert.Equal(PlayerBestLapMs, latestRace.GetProperty("myBestLapTimeMs").GetInt32());
        Assert.Equal(PlayerRacePoints, latestRace.GetProperty("myPoints").GetInt32());
        Assert.Equal(0, items[1].GetProperty("myPoints").GetInt32());

        // 필터: sessionType=race → 레이스 2건만.
        var races = await GetOkAsync(seeded.Client, $"{SessionsUrl}?sessionType=race");
        Assert.Equal(RoundCount, races.GetProperty("total").GetInt32());
        Assert.All(races.GetProperty("items").EnumerateArray(), item => Assert.Equal("Race", item.GetProperty("sessionType").GetString()));

        // 상세: 결과 22건, 순위 오름차순, 시즌 라운드 2(마지막 레이스).
        var sessionId = latestRace.GetProperty("sessionId").GetGuid();
        var (status, detail) = await GetJsonAsync(seeded.Client, $"{SessionsUrl}/{sessionId}");
        Assert.Equal(HttpStatusCode.OK, status);

        var header = detail.GetProperty("session");
        Assert.Equal(sessionId, header.GetProperty("sessionId").GetGuid());
        Assert.Equal(seasonId, header.GetProperty("seasonId").GetGuid());
        Assert.Equal(RoundCount, header.GetProperty("round").GetInt32());
        Assert.Equal(15, header.GetProperty("totalLaps").GetInt32());
        Assert.Equal(85, header.GetProperty("aiDifficulty").GetInt32());
        Assert.False(header.GetProperty("isNetworkGame").GetBoolean());
        Assert.Equal(GridSize, header.GetProperty("carCount").GetInt32());

        var results = detail.GetProperty("results").EnumerateArray().ToList();
        Assert.Equal(GridSize, results.Count);
        Assert.Equal(Enumerable.Range(1, GridSize), results.Select(r => r.GetProperty("position").GetInt32()));

        var first = results[0];
        Assert.Equal("DRIVER 0", first.GetProperty("name").GetString());
        Assert.True(first.GetProperty("isFastestLap").GetBoolean());
        Assert.False(results[1].GetProperty("isFastestLap").GetBoolean());
        Assert.Equal(StintsPerCar, first.GetProperty("tyreStints").GetArrayLength());
        Assert.Equal(5, first.GetProperty("tyreStints")[0].GetProperty("endLap").GetInt32());
        Assert.Equal("Mercedes", first.GetProperty("teamName").GetString());
        Assert.True(results[PlayerCarIndex].GetProperty("isPlayer").GetBoolean());
    }

    [Fact]
    public async Task Sessions_SessionTypeFilter_IsCaseInsensitive()
    {
        var seeded = await SeedTwoRoundSeasonAsync();

        foreach (var (value, expectedTotal) in new[]
                 {
                     ("Race", RoundCount), ("race", RoundCount), ("RACE", RoundCount),
                     ("Qualifying", RoundCount), ("qualifying", RoundCount), (" Qualifying ", RoundCount),
                     ("Practice", 0), ("practice", 0),
                 })
        {
            var (status, body) = await GetJsonAsync(seeded.Client, $"{SessionsUrl}?sessionType={Uri.EscapeDataString(value)}");

            Assert.True(HttpStatusCode.OK == status, $"sessionType='{value}' → {status}");
            Assert.True(expectedTotal == body.GetProperty("total").GetInt32(), $"sessionType='{value}' total");
        }

        // 빈 값은 필터 없음(RankingsController의 period와 같은 방식).
        var unfiltered = await GetOkAsync(seeded.Client, $"{SessionsUrl}?sessionType=");
        Assert.Equal(SessionCount, unfiltered.GetProperty("total").GetInt32());
    }

    [Fact]
    public async Task Sessions_NonSeasonSessionWithoutPlayer_HasNullSeasonRoundAndMyValues()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-QUERY-PC");
        await using var connection = await StartHubAsync(deviceKey);

        // 시즌 링크 0(시즌 대상 아님) + 플레이어 차 없음.
        var payload = SessionClassifiedPayloads.Build(
            GridSize, StintsPerCar, seasonLink: 0, weekendLink: 0, sessionLink: 0,
            sessionKind: "Practice1", sessionType: "Practice", playerCarIndex: -1, awardsPoints: false);
        await SendAsync(connection, payload, DateTime.UtcNow.AddMinutes(-5));

        Assert.Equal(0, (await GetOkAsync(client, SeasonsUrl)).GetProperty("total").GetInt32());

        var item = Assert.Single((await GetOkAsync(client, SessionsUrl)).GetProperty("items").EnumerateArray());
        Assert.Equal(JsonValueKind.Null, item.GetProperty("seasonId").ValueKind);
        Assert.Equal(GridSize, item.GetProperty("carCount").GetInt32());
        foreach (var name in new[] { "myPosition", "myGridPosition", "myResultStatus", "myBestLapTimeMs", "myPoints" })
        {
            Assert.True(JsonValueKind.Null == item.GetProperty(name).ValueKind, $"{name}이 null이어야 한다");
        }

        var detail = await GetOkAsync(client, $"{SessionsUrl}/{item.GetProperty("sessionId").GetGuid()}");
        Assert.Equal(JsonValueKind.Null, detail.GetProperty("session").GetProperty("round").ValueKind);
        Assert.Equal(JsonValueKind.Null, detail.GetProperty("session").GetProperty("seasonId").ValueKind);
        Assert.Equal(GridSize, detail.GetProperty("results").GetArrayLength());
    }

    [Fact]
    public async Task OtherUsersSeasonAndSession_Return404()
    {
        var owner = await SeedTwoRoundSeasonAsync();
        var seasonId = (await GetOkAsync(owner.Client, SeasonsUrl)).GetProperty("items")[0].GetProperty("seasonId").GetGuid();
        var sessionId = (await GetOkAsync(owner.Client, SessionsUrl)).GetProperty("items")[0].GetProperty("sessionId").GetGuid();

        var stranger = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(stranger);

        var seasonResponse = await GetJsonAsync(stranger, $"{SeasonsUrl}/{seasonId}");
        var sessionResponse = await GetJsonAsync(stranger, $"{SessionsUrl}/{sessionId}");

        Assert.Equal(HttpStatusCode.NotFound, seasonResponse.Status);
        Assert.Equal("https://simcenter/errors/not-found", seasonResponse.Body.GetProperty("type").GetString());
        Assert.Equal(HttpStatusCode.NotFound, sessionResponse.Status);
        Assert.Equal("https://simcenter/errors/not-found", sessionResponse.Body.GetProperty("type").GetString());

        // 남의 데이터는 목록에도 나오지 않고, 주인은 여전히 볼 수 있다.
        Assert.Equal(0, (await GetOkAsync(stranger, SeasonsUrl)).GetProperty("total").GetInt32());
        Assert.Equal(0, (await GetOkAsync(stranger, SessionsUrl)).GetProperty("total").GetInt32());
        Assert.Equal(HttpStatusCode.OK, (await GetJsonAsync(owner.Client, $"{SeasonsUrl}/{seasonId}")).Status);
        Assert.Equal(HttpStatusCode.OK, (await GetJsonAsync(owner.Client, $"{SessionsUrl}/{sessionId}")).Status);
    }

    [Fact]
    public async Task UnknownGuid_Returns404()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var season = await client.GetAsync($"{SeasonsUrl}/{Guid.NewGuid()}");
        var session = await client.GetAsync($"{SessionsUrl}/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.NotFound, season.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, session.StatusCode);
    }

    [Fact]
    public async Task NonGuidId_Returns404()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var session = await client.GetAsync($"{SessionsUrl}/abc");
        var season = await client.GetAsync($"{SeasonsUrl}/abc");

        Assert.Equal(HttpStatusCode.NotFound, session.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, season.StatusCode);
    }

    [Fact]
    public async Task NoToken_Returns401()
    {
        var anonymous = _factory.CreateClient();
        var someId = Guid.NewGuid();

        foreach (var url in new[] { SeasonsUrl, $"{SeasonsUrl}/{someId}", SessionsUrl, $"{SessionsUrl}/{someId}" })
        {
            var response = await anonymous.GetAsync(url);

            Assert.True(HttpStatusCode.Unauthorized == response.StatusCode, $"{url} → {response.StatusCode}");
        }
    }

    [Theory]
    [InlineData("TimeTrial")]
    [InlineData("4")]
    [InlineData("Banana")]
    public async Task Sessions_InvalidSessionType_Returns400StandardProblem(string value)
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var (status, body) = await GetJsonAsync(client, $"{SessionsUrl}?sessionType={Uri.EscapeDataString(value)}");

        Assert.Equal(HttpStatusCode.BadRequest, status);
        Assert.Equal(ValidationErrorType, body.GetProperty("type").GetString());
        Assert.Equal(400, body.GetProperty("status").GetInt32());
        var messages = body.GetProperty("errors").GetProperty("sessionType");
        Assert.Equal("sessionType는 Practice/Qualifying/Race 중 하나여야 합니다.", messages[0].GetString());
    }

    // ── 헬퍼 ──

    private sealed record SeededUser(HttpClient Client, Guid UserId);

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);

    private sealed record JsonResponse(HttpStatusCode Status, JsonElement Body);

    /// <summary>GET이 200이어야 하는 호출용. 아니면 상태 코드와 본문을 담아 실패한다.</summary>
    private static async Task<JsonElement> GetOkAsync(HttpClient client, string url)
    {
        var response = await GetJsonAsync(client, url);

        Assert.True(HttpStatusCode.OK == response.Status, $"GET {url} → {response.Status} {response.Body}");
        return response.Body;
    }

    private static async Task<JsonResponse> GetJsonAsync(HttpClient client, string url)
    {
        using var response = await client.GetAsync(url);

        // 본문이 없는 응답(라우트 불일치 404 등)은 Undefined 요소로 돌려주어, 상태 코드 단언이 먼저 실패하게 한다.
        var text = await response.Content.ReadAsStringAsync();
        var body = string.IsNullOrWhiteSpace(text) ? default : JsonSerializer.Deserialize<JsonElement>(text);
        return new JsonResponse(response.StatusCode, body);
    }

    /// <summary>
    /// 새 사용자·장치로 2라운드(주말 22·23) × (예선 1 + 레이스)를 허브로 보낸다. 분류 시각은 예선 → 레이스 → 다음 라운드 순으로 흐른다.
    /// </summary>
    private async Task<SeededUser> SeedTwoRoundSeasonAsync()
    {
        var client = _factory.CreateClient();
        var userId = await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-QUERY-PC");
        await using var connection = await StartHubAsync(deviceKey);

        var start = DateTime.UtcNow - SeedSpan;
        var plan = new[]
        {
            (Weekend: Round1WeekendLink, Link: Round1QualifyingLink, Kind: "Qualifying1", Type: "Qualifying"),
            (Weekend: Round1WeekendLink, Link: Round1RaceLink, Kind: "Race", Type: "Race"),
            (Weekend: Round2WeekendLink, Link: Round2QualifyingLink, Kind: "Qualifying1", Type: "Qualifying"),
            (Weekend: Round2WeekendLink, Link: Round2RaceLink, Kind: "Race", Type: "Race"),
        };

        for (var i = 0; i < plan.Length; i++)
        {
            var step = plan[i];
            var payload = SessionClassifiedPayloads.Build(
                GridSize, StintsPerCar, SeasonLink, step.Weekend, step.Link,
                sessionKind: step.Kind, sessionType: step.Type, playerCarIndex: PlayerCarIndex,
                awardsPoints: step.Type == "Race");
            await SendAsync(connection, payload, start + (SeedStep * i));
        }

        return new SeededUser(client, userId);
    }

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
