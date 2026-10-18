using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 시즌 가져오기 API E2E(docs/15 §12, D-55): 기록된 마이애미 예선(예전 Other 모드) → 미리보기 → 가져오기 → 시즌·세션 조회.
/// 실 PostgreSQL(테스트 DB <c>simcenter_test</c>)이 필요하다. 테스트마다 새 사용자라 같은 링크를 써도 섞이지 않는다.
/// 픽스처는 사용자가 준 원문 그대로다(Application.Tests의 Fixtures).
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class SeasonImportApiE2ETests : IClassFixture<ApiFactory>
{
    private const string SeasonsUrl = "/api/v1/me/seasons";
    private const string SessionsUrl = "/api/v1/me/sessions";
    private const string PreviewUrl = "/api/v1/me/seasons/import/preview";
    private const string ImportUrl = "/api/v1/me/seasons/import";

    private const long MiamiSeasonLink = 2160041047;
    private const long MiamiWeekendLink = 2160041547;
    private const int MiamiTrackId = 30;
    private const int GridSize = 22;
    private const int PlayerCarIndex = 2;

    private readonly ApiFactory _factory;

    public SeasonImportApiE2ETests(ApiFactory factory) => _factory = factory;

    private static string Fixture(string name) => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", name));

    private static string Summary => Fixture("f1laps_season_driver_career.md");

    private static string All => string.Join("\n\n", Fixture("ingame_season1.md"), Summary, Fixture("f1laps_session_sample.md"));

    [Fact]
    public async Task Import_summary_attaches_recorded_miami_and_shows_f1laps_standings()
    {
        var (client, connection) = await SeedMiamiQualifyingAsync();
        await using var _ = connection;

        var preview = await PostOkAsync(client, PreviewUrl, Summary);
        Assert.Equal(MiamiSeasonLink, preview.GetProperty("linkCandidate").GetProperty("seasonLinkId").GetInt64());
        Assert.Equal(3, preview.GetProperty("linkCandidate").GetProperty("sessions").GetArrayLength());
        Assert.False(preview.GetProperty("alreadyImported").GetBoolean());

        var seasonId = await ImportAsync(client, Summary);
        var detail = await GetOkAsync(client, $"{SeasonsUrl}/{seasonId}");

        Assert.Equal([1, 2, 3, 5, 6], Rounds(detail));
        var drivers = detail.GetProperty("standings").GetProperty("drivers");
        Assert.Equal(("Oscar Piastri", 52), (drivers[0].GetProperty("name").GetString(), drivers[0].GetProperty("points").GetInt32()));
        Assert.True(drivers[1].GetProperty("isPlayer").GetBoolean());
        Assert.Equal(50, drivers[1].GetProperty("points").GetInt32());

        var header = detail.GetProperty("season");
        Assert.Equal(("F1Laps", "Ferrari", "DriverCareer"),
            (header.GetProperty("importedFrom").GetString(), header.GetProperty("myTeamName").GetString(), header.GetProperty("gameMode").GetString()));

        // 옮긴 기록 세션은 이 시즌 소속이고 모드가 바뀌었다.
        var sessions = await GetOkAsync(client, $"{SessionsUrl}?pageSize=100");
        var miami = sessions.GetProperty("items").EnumerateArray().Where(s => s.GetProperty("trackName").GetString() == "Miami").ToList();
        Assert.Equal(3, miami.Count);
        Assert.All(miami, s =>
        {
            Assert.Equal(seasonId, s.GetProperty("seasonId").GetGuid());
            Assert.Equal("DriverCareer", s.GetProperty("gameMode").GetString());
        });
    }

    [Fact]
    public async Task Import_all_documents_uses_in_game_standings_and_keeps_session_details()
    {
        var (client, connection) = await SeedMiamiQualifyingAsync();
        await using var _ = connection;

        var preview = await PostOkAsync(client, PreviewUrl, All);
        Assert.Equal(4, preview.GetProperty("documents").GetArrayLength());

        var seasonId = await ImportAsync(client, All);
        var detail = await GetOkAsync(client, $"{SeasonsUrl}/{seasonId}");

        Assert.Equal([1, 2, 3, 4, 5, 6], Rounds(detail));
        var drivers = detail.GetProperty("standings").GetProperty("drivers");
        Assert.Equal(
            [("Lando NORRIS", 93), ("Oscar PIASTRI", 79), ("GOMDOL SUPER", 75)],
            drivers.EnumerateArray().Take(3).Select(d => (d.GetProperty("name").GetString()!, d.GetProperty("points").GetInt32())));
        var constructors = detail.GetProperty("standings").GetProperty("constructors");
        Assert.Equal(
            [("McLaren", 172), ("Mercedes", 127), ("Ferrari", 109)],
            constructors.EnumerateArray().Take(3).Select(c => (c.GetProperty("teamName").GetString()!, c.GetProperty("points").GetInt32())));

        // 호주 레이스 = 인게임 순위 + F1Laps 랩·셋업·벌칙.
        var australiaRace = detail.GetProperty("rounds")[0].GetProperty("sessions").EnumerateArray()
            .Single(s => s.GetProperty("sessionType").GetString() == "Race");
        var session = await GetOkAsync(client, $"{SessionsUrl}/{australiaRace.GetProperty("sessionId").GetGuid()}");
        Assert.Equal(GridSize, session.GetProperty("results").GetArrayLength());
        Assert.Equal(6, session.GetProperty("laps").GetArrayLength());
        Assert.Equal(25, session.GetProperty("setup").GetProperty("frontWing").GetInt32());
        Assert.Equal(3, session.GetProperty("penalties").GetArrayLength());
        Assert.Equal("Clear", session.GetProperty("session").GetProperty("weather").GetString());
        var hamilton = session.GetProperty("results").EnumerateArray().Single(r => r.GetProperty("name").GetString() == "Lewis HAMILTON");
        Assert.Equal(12_364, hamilton.GetProperty("gapMs").GetInt32());

        // 같은 링크로 다시 가져오면 409.
        using var again = await client.PostAsJsonAsync(ImportUrl, new { markdown = All });
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);

        // 앞으로 오는 같은 링크의 세션(이제 DriverCareer)은 이 시즌 6라운드에 붙고 점수가 더해진다.
        await SendAsync(connection, SessionClassifiedPayloads.Build(
            GridSize, 1, MiamiSeasonLink, MiamiWeekendLink, 4100, playerCarIndex: PlayerCarIndex, trackId: MiamiTrackId,
            sessionRef: "8100"));
        var after = await GetOkAsync(client, $"{SeasonsUrl}/{seasonId}");
        var miamiRound = after.GetProperty("rounds").EnumerateArray().Single(r => r.GetProperty("round").GetInt32() == 6);
        Assert.Contains(miamiRound.GetProperty("sessions").EnumerateArray(), s => s.GetProperty("sessionType").GetString() == "Race");
        var me = after.GetProperty("standings").GetProperty("drivers").EnumerateArray().Single(d => d.GetProperty("isPlayer").GetBoolean());
        Assert.Equal(75 + 19, me.GetProperty("points").GetInt32());
    }

    [Fact]
    public async Task Preview_bad_markdown_is_400_with_line_number()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        using var response = await client.PostAsJsonAsync(PreviewUrl, new { markdown = Summary.Replace("1:20.953", "1:2x.953", StringComparison.Ordinal) });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.StartsWith("9번째 줄:", body.GetProperty("errors").GetProperty("markdown")[0].GetString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Import_requires_user_token()
    {
        using var response = await _factory.CreateClient().PostAsJsonAsync(ImportUrl, new { markdown = Summary });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private static int[] Rounds(JsonElement detail)
        => detail.GetProperty("rounds").EnumerateArray().Select(r => r.GetProperty("round").GetInt32()).ToArray();

    private static async Task<Guid> ImportAsync(HttpClient client, string markdown)
    {
        using var response = await client.PostAsJsonAsync(ImportUrl, new { markdown });
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.Created, text);
        return JsonSerializer.Deserialize<JsonElement>(text).GetProperty("seasonId").GetGuid();
    }

    private static async Task<JsonElement> PostOkAsync(HttpClient client, string url, string markdown)
    {
        using var response = await client.PostAsJsonAsync(url, new { markdown });
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, text);
        return JsonSerializer.Deserialize<JsonElement>(text);
    }

    private static async Task<JsonElement> GetOkAsync(HttpClient client, string url)
    {
        using var response = await client.GetAsync(url);
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, text);
        return JsonSerializer.Deserialize<JsonElement>(text);
    }

    /// <summary>새 사용자·장치로 마이애미 Q1~Q3를 예전 모양(<c>Other</c> 모드 → uid 키, 시즌 없음)으로 보낸다.</summary>
    private async Task<(HttpClient Client, HubConnection Connection)> SeedMiamiQualifyingAsync()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-IMPORT-PC");
        var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();

        string[] kinds = ["Qualifying1", "Qualifying2", "Qualifying3"];
        for (var i = 0; i < kinds.Length; i++)
        {
            await SendAsync(connection, SessionClassifiedPayloads.Build(
                GridSize, 1, MiamiSeasonLink, MiamiWeekendLink, 3000 + i, sessionKind: kinds[i], sessionType: "Qualifying",
                playerCarIndex: PlayerCarIndex, trackId: MiamiTrackId, awardsPoints: false, gameMode: "Other", sessionRef: $"{7000 + i}"),
                DateTime.UtcNow.AddMinutes(-30 + i));
        }

        return (client, connection);
    }

    private static async Task SendAsync(HubConnection connection, object payload, DateTime? occurredAt = null)
    {
        var envelope = new
        {
            eventId = Guid.NewGuid(),
            gameCode = "F1_25",
            occurredAt = occurredAt ?? DateTime.UtcNow,
            type = "SessionClassified",
            payload,
        };

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
