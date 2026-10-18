using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using SimCenter.Domain.Constants;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 랩 상세 한 바퀴(15 §7): Agent → TelemetryHub → DB → <c>GET /me/laps</c>·<c>/me/laps/{id}</c>·<c>/me/laps/{id}/trace</c>.
/// 목록의 팀·날씨·트레이스 유무, <c>validOnly</c>, 상세의 국가·세션 연결·스냅샷·비교 대상, 트레이스 복원, 남의 랩 404(D-34).
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class LapDetailApiE2ETests : IClassFixture<ApiFactory>
{
    private const int BestValidMs = 97_003;
    private const int InvalidFastMs = 95_000;
    private const int CurrentMs = 98_448;

    private static readonly DateTime T0 = new(2026, 10, 18, 11, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public LapDetailApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task HubToApi_RoundTrip_ListDetailAndTrace()
    {
        var (client, trace) = await SeedThreeLapsAsync();
        var trackId = await JeddahTrackIdAsync(client);

        // 목록: 새 필드(랩 번호·모드·팀·날씨·트레이스 유무). 최근 순 = current → invalid → best.
        var list = await client.GetFromJsonAsync<JsonElement>($"/api/v1/me/laps?trackId={trackId}");
        var items = Items(list);
        Assert.Equal(new[] { CurrentMs, InvalidFastMs, BestValidMs }, items.Select(LapTime));
        var current = items[0];
        Assert.Equal(5, current.GetProperty("lapNumber").GetInt32());
        Assert.Equal("DriverCareer", current.GetProperty("gameMode").GetString());
        Assert.Equal("Ferrari", current.GetProperty("team").GetProperty("name").GetString());
        Assert.Equal("#E8002D", current.GetProperty("team").GetProperty("color").GetString());
        Assert.Equal("LightCloud", current.GetProperty("weather").GetString());
        Assert.True(current.GetProperty("hasTrace").GetBoolean());
        Assert.Equal(JsonValueKind.Null, items[2].GetProperty("team").ValueKind); // 스냅샷 없는 랩
        Assert.Equal(JsonValueKind.Null, items[2].GetProperty("weather").ValueKind);

        // validOnly: 무효 랩 제외.
        var valid = await client.GetFromJsonAsync<JsonElement>($"/api/v1/me/laps?trackId={trackId}&validOnly=true");
        Assert.Equal(new[] { CurrentMs, BestValidMs }, Items(valid).Select(LapTime));
        Assert.Equal(2, valid.GetProperty("laps").GetProperty("total").GetInt32());

        var currentId = current.GetProperty("lapId").GetGuid();
        var bestId = items[2].GetProperty("lapId").GetGuid();
        await AssertDetailAsync(client, currentId, bestId, trackId);
        await AssertTraceAsync(client, currentId, trace);

        // 트레이스 없는 랩의 /trace는 404.
        var noTrace = await client.GetAsync($"/api/v1/me/laps/{items[1].GetProperty("lapId").GetGuid()}/trace");
        Assert.Equal(HttpStatusCode.NotFound, noTrace.StatusCode);
    }

    [Fact]
    public async Task OtherUsersLap_DetailAndTrace_AreNotFound()
    {
        var (owner, _) = await SeedThreeLapsAsync();
        var trackId = await JeddahTrackIdAsync(owner);
        var lapId = Items(await owner.GetFromJsonAsync<JsonElement>($"/api/v1/me/laps?trackId={trackId}"))[0]
            .GetProperty("lapId").GetGuid();

        var stranger = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(stranger);

        Assert.Equal(HttpStatusCode.NotFound, (await stranger.GetAsync($"/api/v1/me/laps/{lapId}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await stranger.GetAsync($"/api/v1/me/laps/{lapId}/trace")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await owner.GetAsync($"/api/v1/me/laps/{Guid.NewGuid()}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await owner.GetAsync("/api/v1/me/laps/not-a-guid")).StatusCode);
    }

    private static async Task AssertDetailAsync(HttpClient client, Guid currentId, Guid bestId, Guid trackId)
    {
        var detail = await client.GetFromJsonAsync<JsonElement>($"/api/v1/me/laps/{currentId}");

        Assert.Equal(currentId, detail.GetProperty("lap").GetProperty("lapId").GetGuid());
        Assert.Equal(trackId, detail.GetProperty("trackId").GetGuid());
        Assert.Equal("SA", detail.GetProperty("countryCode").GetString());

        // 같은 세션 키(link:11:22:33)의 내 세션.
        var sessions = await client.GetFromJsonAsync<JsonElement>("/api/v1/me/sessions");
        var sessionId = Assert.Single(sessions.GetProperty("items").EnumerateArray()).GetProperty("sessionId").GetGuid();
        Assert.Equal(sessionId, detail.GetProperty("sessionId").GetGuid());

        var car = detail.GetProperty("car");
        Assert.Equal(16, car.GetProperty("visualTyreCompound").GetInt32());
        Assert.Equal(31.0, car.GetProperty("tyreWearEnd").GetProperty("frontLeft").GetDouble());
        Assert.Equal(18.5, car.GetProperty("tyreWearEnd").GetProperty("rearRight").GetDouble());
        Assert.Equal(5.0, car.GetProperty("brakeDamage").GetProperty("rearLeft").GetDouble());
        Assert.Equal(20, car.GetProperty("sidepodDamage").GetInt32());
        Assert.Equal(22.7, car.GetProperty("fuelEndKg").GetDouble());
        Assert.Equal(2_100_000, car.GetProperty("ersDeployedJ").GetDouble());

        var conditions = detail.GetProperty("conditions");
        Assert.Equal("LightCloud", conditions.GetProperty("weather").GetString());
        Assert.Equal(21, conditions.GetProperty("airTempC").GetInt32());
        Assert.Equal(31, conditions.GetProperty("trackTempC").GetInt32());
        Assert.Equal(4, conditions.GetProperty("rainForecastPercent").GetInt32());

        // 비교 = 같은 트랙의 내 최고 "유효" 랩(더 빠른 무효 랩이 아니다).
        var comparison = detail.GetProperty("comparison");
        Assert.Equal(bestId, comparison.GetProperty("lapId").GetGuid());
        Assert.Equal(BestValidMs, comparison.GetProperty("lapTimeMs").GetInt32());
        Assert.Equal(3, comparison.GetProperty("sectors").GetArrayLength());
        Assert.True(comparison.GetProperty("hasTrace").GetBoolean());
    }

    private static async Task AssertTraceAsync(HttpClient client, Guid lapId, LapDetailPayloads.TraceChannels sent)
    {
        var trace = await client.GetFromJsonAsync<JsonElement>($"/api/v1/me/laps/{lapId}/trace");

        Assert.Equal(lapId, trace.GetProperty("lapId").GetGuid());
        Assert.Equal(sent.ResolutionM, trace.GetProperty("resolutionM").GetInt32());
        Assert.Equal(sent.TimeMs.Length, trace.GetProperty("sampleCount").GetInt32());
        Assert.Equal(sent.TimeMs, Ints(trace, "timeMs"));
        Assert.Equal(sent.SpeedKph, Ints(trace, "speedKph"));
        Assert.Equal(sent.Throttle, Ints(trace, "throttle"));
        Assert.Equal(sent.Brake, Ints(trace, "brake"));
        Assert.Equal(sent.Steer, Ints(trace, "steer"));
        Assert.Equal(sent.Gear, Ints(trace, "gear"));
        Assert.Equal(sent.Rpm, Ints(trace, "rpm"));
    }

    /// <summary>
    /// 한 사용자로 Jeddah 랩 3개(최고 유효 + 트레이스 / 더 빠른 무효 + 스냅샷 / 현재 = 스냅샷·날씨·트레이스)와
    /// 같은 세션(링크 11:22:33)의 순위표를 보낸다. 로그인된 클라이언트와 현재 랩의 트레이스를 돌려준다.
    /// </summary>
    private async Task<(HttpClient Client, LapDetailPayloads.TraceChannels Trace)> SeedThreeLapsAsync()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "DETAIL-API-PC");
        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();

        var bestTrace = LapDetailPayloads.Trace(samples: 400);
        var currentTrace = LapDetailPayloads.Trace();

        await SubmitAsync(connection, LapDetailPayloads.LapFinished(
            3, BestValidMs, isValid: true, T0, trace: bestTrace.ToWire(), sessionType: "Race"));
        await SubmitAsync(connection, LapDetailPayloads.LapFinished(
            4, InvalidFastMs, isValid: false, T0.AddMinutes(2), car: LapDetailPayloads.Car(), sessionType: "Race"));
        await SubmitAsync(connection, LapDetailPayloads.LapFinished(
            5, CurrentMs, isValid: true, T0.AddMinutes(4), car: LapDetailPayloads.Car(),
            conditions: LapDetailPayloads.Conditions(), trace: currentTrace.ToWire(), sessionType: "Race"));
        await SubmitAsync(connection, new
        {
            eventId = Guid.NewGuid(),
            gameCode = GameCodes.F1_25,
            occurredAt = T0.AddMinutes(30),
            type = "SessionClassified",
            payload = SessionClassifiedPayloads.Build(
                carCount: 2, stintsPerCar: 1, seasonLink: 11, weekendLink: 22, sessionLink: 33,
                trackId: LapDetailPayloads.JeddahGameTrackId),
        });

        return (client, currentTrace);
    }

    private static async Task SubmitAsync(HubConnection connection, object envelope)
    {
        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);
    }

    private static async Task<Guid> JeddahTrackIdAsync(HttpClient client)
    {
        var tracks = await client.GetFromJsonAsync<JsonElement>("/api/v1/me/tracks");
        return Assert.Single(tracks.GetProperty("items").EnumerateArray()).GetProperty("trackId").GetGuid();
    }

    private static List<JsonElement> Items(JsonElement myLaps)
        => myLaps.GetProperty("laps").GetProperty("items").EnumerateArray().ToList();

    private static int LapTime(JsonElement lap) => lap.GetProperty("lapTimeMs").GetInt32();

    private static int[] Ints(JsonElement body, string name)
        => body.GetProperty(name).EnumerateArray().Select(v => v.GetInt32()).ToArray();

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
