using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using SimCenter.Domain.Constants;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// F1 26(2026 시즌팩) 자동 분류 + 게임별 조회 필터. 옛 Agent처럼 <c>F1_25</c>로 보내도 2026 팀이 있으면 F1 26으로 저장되고,
/// <c>/me/tracks</c>·<c>/me/seasons</c>·<c>/me/sessions</c>의 <c>gameCode</c> 쿼리가 그 게임만 돌려준다(생략하면 전체, 모르는 코드는 400).
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class GameFilterApiE2ETests : IClassFixture<ApiFactory>
{
    private const long SeasonLink = 61;
    private const long WeekendLink = 62;
    private const long SessionLink = 63;
    private const int GridSize = 4;
    private const int StintsPerCar = 1;
    private const int Season2026GridFirstTeamId = 220;
    private const int AudiTeamId = 229;

    private static readonly DateTime OccurredAt = DateTime.UtcNow.AddMinutes(-10);

    private readonly ApiFactory _factory;

    public GameFilterApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task SeasonPackEvents_SentAsF1_25_AreStoredAndFilteredAsF1_26()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "GAME-FILTER-PC");
        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();

        var sessionAck = await connection.InvokeAsync<SubmitAck>("SubmitEvent", Envelope("SessionClassified",
            SessionClassifiedPayloads.Build(GridSize, StintsPerCar, SeasonLink, WeekendLink, SessionLink, firstTeamId: Season2026GridFirstTeamId)));
        var lapAck = await connection.InvokeAsync<SubmitAck>("SubmitEvent", Envelope("LapFinished", TimeTrialLap()));

        Assert.True(sessionAck.Acknowledged, sessionAck.RejectReason);
        Assert.True(lapAck.Acknowledged, lapAck.RejectReason);

        Assert.Equal(1, await CountAsync(client, "/api/v1/me/sessions?gameCode=F1_26"));
        Assert.Equal(0, await CountAsync(client, "/api/v1/me/sessions?gameCode=F1_25"));
        Assert.Equal(1, await CountAsync(client, "/api/v1/me/sessions"));

        Assert.Equal(1, await CountAsync(client, "/api/v1/me/seasons?gameCode=F1_26"));
        Assert.Equal(0, await CountAsync(client, "/api/v1/me/seasons?gameCode=F1_25"));

        var myTracks2026 = await ItemsAsync(client, "/api/v1/me/tracks?gameCode=F1_26");
        var myTrack = Assert.Single(myTracks2026);
        Assert.Equal(GameCodes.F1_26, myTrack.GetProperty("gameCode").GetString());
        Assert.Empty(await ItemsAsync(client, "/api/v1/me/tracks?gameCode=F1_25"));

        // 그 트랙의 F1 26 랭킹에 랩이 올라간다.
        var ranking = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/rankings?trackId={myTrack.GetProperty("trackId").GetGuid()}&gameCode=F1_26");
        Assert.NotEmpty(ranking.GetProperty("entries").EnumerateArray());
    }

    [Theory]
    [InlineData("/api/v1/me/sessions?gameCode=ACC")]
    [InlineData("/api/v1/me/seasons?gameCode=f1_26")]
    [InlineData("/api/v1/me/tracks?gameCode=F1_24")]
    [InlineData("/api/v1/tracks?gameCode=X")]
    public async Task UnknownGameCode_Is400(string url)
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        using var response = await client.GetAsync(url);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private static object TimeTrialLap() => new
    {
        sessionRef = "0xGAMEFILTER",
        lapNumber = 2,
        lapTimeMs = 90123,
        sectors = new[] { new { sectorNumber = 1, sectorTimeMs = 90123 } },
        isValid = true,
        isOutOrInLap = false,
        trackId = SessionClassifiedPayloads.SeedTrackId,
        sessionType = "TimeTrial",
        car = new { teamId = AudiTeamId },
    };

    private static object Envelope(string type, object payload) => new
    {
        eventId = Guid.NewGuid(),
        gameCode = GameCodes.F1_25,
        occurredAt = OccurredAt,
        type,
        payload,
    };

    private static async Task<int> CountAsync(HttpClient client, string url)
        => (await client.GetFromJsonAsync<JsonElement>(url)).GetProperty("total").GetInt32();

    private static async Task<List<JsonElement>> ItemsAsync(HttpClient client, string url)
        => (await client.GetFromJsonAsync<JsonElement>(url)).GetProperty("items").EnumerateArray().ToList();

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
