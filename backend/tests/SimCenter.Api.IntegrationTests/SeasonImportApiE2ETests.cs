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

    private static string MyTeam => Fixture("f1laps_myteam_sample.md");

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
    public async Task Season_tab_lists_full_calendar_with_my_round_values()
    {
        var (client, connection) = await SeedMiamiQualifyingAsync();
        await using var _ = connection;

        var seasonId = await ImportAsync(client, Summary);
        var detail = await GetOkAsync(client, $"{SeasonsUrl}/{seasonId}");

        // 시즌 탭(docs/15 §12): F1 25 캘린더 24개, 가져온 라운드 + 옮긴 마이애미 예선.
        var calendar = detail.GetProperty("calendar").EnumerateArray().ToList();
        Assert.Equal(Enumerable.Range(1, 24), calendar.Select(r => r.GetProperty("round").GetInt32()));
        Assert.Equal(("Melbourne", "AU"), (calendar[0].GetProperty("trackName").GetString(), calendar[0].GetProperty("countryCode").GetString()));

        var australia = calendar[0];
        Assert.Equal((1, 25, 100), (australia.GetProperty("racePosition").GetInt32(), australia.GetProperty("points").GetInt32(),
            australia.GetProperty("raceAiDifficulty").GetInt32()));
        Assert.NotEqual(JsonValueKind.Null, australia.GetProperty("raceSessionId").ValueKind);
        var china = calendar[1];
        Assert.Equal((14, 103), (china.GetProperty("qualiPosition").GetInt32(), china.GetProperty("qualiAiDifficulty").GetInt32()));

        var miami = calendar[5];
        Assert.Equal(JsonValueKind.Null, miami.GetProperty("raceSessionId").ValueKind);
        Assert.NotEqual(JsonValueKind.Null, miami.GetProperty("firstSessionId").ValueKind);
        Assert.Equal(JsonValueKind.Null, calendar[3].GetProperty("weekendId").ValueKind);   // 바레인: 달리지 않음
        Assert.Equal("Ferrari", calendar[3].GetProperty("myTeamName").GetString());

        var header = detail.GetProperty("season");
        Assert.Equal(1, header.GetProperty("seasonNumber").GetInt32());
        Assert.False(string.IsNullOrEmpty(header.GetProperty("myDriverName").GetString()));
    }

    [Fact]
    public async Task Race_recorded_before_import_but_missing_from_ingame_table_is_added_once()
    {
        var (client, connection) = await SeedMiamiQualifyingAsync();
        await using var _ = connection;
        await SendAsync(connection, SessionClassifiedPayloads.Build(
            GridSize, 1, MiamiSeasonLink, MiamiWeekendLink, 4100, playerCarIndex: PlayerCarIndex, trackId: MiamiTrackId,
            gameMode: "Other", sessionRef: "8100"), DateTime.UtcNow.AddMinutes(-10));

        var preview = await PostOkAsync(client, PreviewUrl, All);
        var seasonId = await ImportAsync(client, All);
        var detail = await GetOkAsync(client, $"{SeasonsUrl}/{seasonId}");

        // 인게임 표는 SAU(5라운드)까지라 가져오기 전에 끝난 마이애미 레이스(19점)가 TOT(75)에 없다 — 넣으면 기준선을 넘는다.
        // 그래서 한 번만 더한다(BaselineCoverage). 미리보기도 같다.
        var me = detail.GetProperty("standings").GetProperty("drivers").EnumerateArray().Single(d => d.GetProperty("isPlayer").GetBoolean());
        Assert.Equal(94, me.GetProperty("points").GetInt32());
        var previewMe = preview.GetProperty("drivers").EnumerateArray().Single(d => d.GetProperty("isPlayer").GetBoolean());
        Assert.Equal(94, previewMe.GetProperty("points").GetInt32());
        Assert.Equal(4, preview.GetProperty("linkCandidate").GetProperty("sessions").GetArrayLength());
    }

    [Fact]
    public async Task Import_merges_into_season_already_recorded_with_same_link()
    {
        // 실제 상황: 예전 Other 모드 예선(시즌 없음) 뒤, 고친 Agent로 달린 레이스(DriverCareer)가 같은 링크로 시즌을 먼저 만들었다.
        var (client, connection) = await SeedMiamiQualifyingAsync();
        await using var _ = connection;
        await SendAsync(connection, SessionClassifiedPayloads.Build(
            GridSize, 1, MiamiSeasonLink, MiamiWeekendLink, 4200, sessionKind: "Race2", playerCarIndex: PlayerCarIndex,
            trackId: MiamiTrackId, gameMode: "DriverCareer", sessionRef: "8200"), DateTime.UtcNow.AddMinutes(-5));
        var recorded = (await GetOkAsync(client, SeasonsUrl)).GetProperty("items")[0].GetProperty("seasonId").GetGuid();

        var preview = await PostOkAsync(client, PreviewUrl, All);
        Assert.False(preview.GetProperty("alreadyImported").GetBoolean());
        var seasonId = await ImportAsync(client, All);

        Assert.Equal(recorded, seasonId);
        Assert.Single((await GetOkAsync(client, SeasonsUrl)).GetProperty("items").EnumerateArray());
        var detail = await GetOkAsync(client, $"{SeasonsUrl}/{seasonId}");
        Assert.Equal([1, 2, 3, 4, 5, 6], Rounds(detail));
        var drivers = detail.GetProperty("standings").GetProperty("drivers");
        // 노리스 = 인게임 TOT 93 + 표에 없는 마이애미 레이스 1점.
        Assert.Equal(94, drivers[0].GetProperty("points").GetInt32());
        var miami = detail.GetProperty("rounds").EnumerateArray().Single(r => r.GetProperty("round").GetInt32() == 6);
        Assert.Equal(4, miami.GetProperty("sessions").GetArrayLength());

        // 같은 내용을 다시 가져오면 이제는 409.
        using var again = await client.PostAsJsonAsync(ImportUrl, new { markdown = All });
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
    }

    [Fact]
    public async Task Deleting_imported_season_removes_its_imported_sessions_from_session_list()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var seasonId = await ImportAsync(client, MyTeam);
        Assert.True((await GetOkAsync(client, $"{SessionsUrl}?pageSize=100")).GetProperty("total").GetInt32() > 0);

        using (var deleted = await client.DeleteAsync($"{SeasonsUrl}/{seasonId}"))
        {
            Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        }

        // 지운 시즌의 가져온 세션은 세션 목록에 남지 않는다(다시 가져오지 않아도).
        Assert.Equal(0, (await GetOkAsync(client, $"{SessionsUrl}?pageSize=100")).GetProperty("total").GetInt32());
    }

    [Fact]
    public async Task My_team_import_shows_custom_team_and_can_be_reimported_after_delete()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var seasonId = await ImportAsync(client, MyTeam);
        var detail = await GetOkAsync(client, $"{SeasonsUrl}/{seasonId}");

        // 내 팀(My Team) = 헤더 팀 이름, AI = F1 25 팀(Kick Sauber → Sauber).
        Assert.Equal("TEAM ALPHA", detail.GetProperty("season").GetProperty("myTeamName").GetString());
        var drivers = detail.GetProperty("standings").GetProperty("drivers").EnumerateArray().ToList();
        Assert.Equal("TEAM ALPHA", drivers.Single(d => d.GetProperty("isPlayer").GetBoolean()).GetProperty("teamName").GetString());
        Assert.Equal("TEAM ALPHA", TeamOf(drivers, "Mark Webber"));
        Assert.Equal("Sauber", TeamOf(drivers, "Nico Hulkenberg"));
        Assert.Equal("Haas", TeamOf(drivers, "Oliver Bearman"));
        var constructors = detail.GetProperty("standings").GetProperty("constructors");
        Assert.Equal(
            [("TEAM ALPHA", 62), ("Red Bull Racing", 43), ("Haas", 30), ("Sauber", 25)],
            constructors.EnumerateArray().Select(c => (c.GetProperty("teamName").GetString()!, c.GetProperty("points").GetInt32())));
        Assert.Equal("TEAM ALPHA", detail.GetProperty("calendar")[0].GetProperty("myTeamName").GetString());

        var australiaRace = detail.GetProperty("rounds")[0].GetProperty("sessions").EnumerateArray()
            .Single(s => s.GetProperty("sessionType").GetString() == "Race");
        var session = await GetOkAsync(client, $"{SessionsUrl}/{australiaRace.GetProperty("sessionId").GetGuid()}");
        var results = session.GetProperty("results").EnumerateArray().ToList();
        Assert.Equal("TEAM ALPHA", results.Single(r => r.GetProperty("isPlayer").GetBoolean()).GetProperty("teamName").GetString());
        Assert.Equal("Red Bull Racing", TeamOf(results, "Max Verstappen"));
        Assert.Equal("TEAM ALPHA", TeamOf(results, "Mark Webber"));
        Assert.Equal("TEAM ALPHA", session.GetProperty("session").GetProperty("myTeam").GetProperty("name").GetString());

        var sessionCount = (await GetOkAsync(client, $"{SessionsUrl}?pageSize=100")).GetProperty("total").GetInt32();

        // 시즌을 지우고(soft delete) 같은 문서를 다시 가져오면 409가 아니고, 옛 가져온 세션은 겹쳐 남지 않는다.
        using (var deleted = await client.DeleteAsync($"{SeasonsUrl}/{seasonId}"))
        {
            Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        }

        var preview = await PostOkAsync(client, PreviewUrl, MyTeam);
        Assert.False(preview.GetProperty("alreadyImported").GetBoolean());
        var again = await ImportAsync(client, MyTeam);

        Assert.NotEqual(seasonId, again);
        Assert.Single((await GetOkAsync(client, SeasonsUrl)).GetProperty("items").EnumerateArray());
        Assert.Equal(sessionCount, (await GetOkAsync(client, $"{SessionsUrl}?pageSize=100")).GetProperty("total").GetInt32());
        var reimported = await GetOkAsync(client, $"{SeasonsUrl}/{again}");
        Assert.Equal("TEAM ALPHA", reimported.GetProperty("season").GetProperty("myTeamName").GetString());
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

    private static string? TeamOf(IEnumerable<JsonElement> rows, string name)
        => rows.Single(r => r.GetProperty("name").GetString() == name).GetProperty("teamName").GetString();

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
