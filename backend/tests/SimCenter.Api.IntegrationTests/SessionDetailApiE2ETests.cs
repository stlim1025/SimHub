using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.SignalR.Client;
using SimCenter.Domain.Constants;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 세션 상세 F1Laps 카드(docs/15 §11, D-52~D-54) 한 바퀴: Agent → TelemetryHub(랩 3개 + 스냅샷 details, 순위표 + 랩 기록·순위) → DB →
/// <c>GET /me/sessions</c>·<c>/me/sessions/{id}</c>. 국가·내 팀(v1.26 팀 ID 221)·시즌 번호, Laps · Engine Wear · Tyre Stints · Penalties · GAP.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class SessionDetailApiE2ETests : IClassFixture<ApiFactory>
{
    private const int FerrariV126TeamId = 221;
    private static readonly int[] LapTimes = [92_412, 90_044, 89_500];
    private static readonly DateTime T0 = new(2026, 10, 18, 13, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public SessionDetailApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task HubToApi_SessionListAndDetailCards()
    {
        var client = await SeedRaceAsync();

        var list = await client.GetFromJsonAsync<JsonElement>("/api/v1/me/sessions");
        var item = Assert.Single(list.GetProperty("items").EnumerateArray());
        Assert.Equal("SA", item.GetProperty("countryCode").GetString());
        Assert.Equal("Ferrari", item.GetProperty("myTeam").GetProperty("name").GetString());
        Assert.Equal("#E8002D", item.GetProperty("myTeam").GetProperty("color").GetString());
        Assert.Equal(1, item.GetProperty("seasonNumber").GetInt32());

        var detail = await client.GetFromJsonAsync<JsonElement>($"/api/v1/me/sessions/{item.GetProperty("sessionId").GetGuid()}");

        AssertHeader(detail.GetProperty("session"));
        AssertLaps(detail.GetProperty("laps"));
        AssertResults(detail.GetProperty("results"));

        var wear = detail.GetProperty("engineWear");
        Assert.Equal(14, wear.GetProperty("ice").GetInt32());              // 마지막 랩(3)의 값
        Assert.Equal(10, wear.GetProperty("turboCharger").GetInt32());
        Assert.Equal(10, wear.GetProperty("gearbox").GetInt32());          // 스냅샷 gearboxDamage
        Assert.Equal(30, wear.GetProperty("engineDamage").GetInt32());

        Assert.Equal(8, detail.GetProperty("setup").GetProperty("frontWing").GetInt32());

        var stints = detail.GetProperty("tyreStints").EnumerateArray().ToList();
        Assert.Single(stints);                                             // 1~3랩 = 첫 스틴트(끝 5랩)
        Assert.Equal("Medium", stints[0].GetProperty("visualCompound").GetString());
        var points = stints[0].GetProperty("laps").EnumerateArray().ToList();
        Assert.Equal(3, points.Count);
        Assert.Equal(LapTimes[2], points[2].GetProperty("lapTimeMs").GetInt32());
        Assert.Equal(77.1, points[2].GetProperty("tyreLifeRemaining").GetDouble()); // 100 − 평균(31, 18, 24, 18.5)

        var penalty = Assert.Single(detail.GetProperty("penalties").EnumerateArray()); // 두 랩에 실린 같은 이벤트는 한 번
        Assert.Equal(2, penalty.GetProperty("lap").GetInt32());
        Assert.True(penalty.GetProperty("isPlayer").GetBoolean());
        Assert.Equal("Small Collision", penalty.GetProperty("infringement").GetString());
        Assert.Equal("Warning", penalty.GetProperty("penalty").GetString());

        Assert.Empty(detail.GetProperty("qualifyingPositions").EnumerateArray());
        Assert.Equal(LapTimes[2], detail.GetProperty("myBestLap").GetProperty("lapTimeMs").GetInt32());
    }

    private static void AssertHeader(JsonElement header)
    {
        Assert.Equal("SA", header.GetProperty("countryCode").GetString());
        Assert.Equal(85, header.GetProperty("aiDifficulty").GetInt32());
        Assert.Equal("LightCloud", header.GetProperty("weather").GetString());
        Assert.Equal(1, header.GetProperty("seasonNumber").GetInt32());
        Assert.Equal("Ferrari", header.GetProperty("myTeam").GetProperty("name").GetString());
    }

    private static void AssertLaps(JsonElement lapsJson)
    {
        var laps = lapsJson.EnumerateArray().ToList();
        Assert.Equal(new[] { 1, 2, 3 }, laps.Select(l => l.GetProperty("lapNumber").GetInt32()));
        Assert.Equal(new[] { 2, 1, 1 }, laps.Select(l => l.GetProperty("position").GetInt32()));
        Assert.Equal(-1, laps[0].GetProperty("positionChange").GetInt32());   // 그리드 1 → 2위
        Assert.Equal(1, laps[1].GetProperty("positionChange").GetInt32());
        Assert.All(laps, l => Assert.Equal("Medium", l.GetProperty("visualCompound").GetString()));
        Assert.Equal(new[] { false, true, false }, laps.Select(l => l.GetProperty("inPit").GetBoolean()));
        Assert.True(laps[2].GetProperty("isBestLap").GetBoolean());
        Assert.Equal(LapTimes[0] - LapTimes[2], laps[0].GetProperty("gapToBestMs").GetInt32());
        Assert.Equal(3, laps[0].GetProperty("sectors").GetArrayLength());
        Assert.Equal(3, laps[0].GetProperty("bestSectors").GetArrayLength());
        Assert.All(laps, l => Assert.Equal(JsonValueKind.String, l.GetProperty("lapId").ValueKind));
    }

    private static void AssertResults(JsonElement resultsJson)
    {
        var results = resultsJson.EnumerateArray().ToList();
        Assert.Equal(0, results[0].GetProperty("gapMs").GetInt32());
        Assert.Equal(1_500, results[1].GetProperty("gapMs").GetInt32());
        Assert.Equal(0, results[1].GetProperty("positionChange").GetInt32());
        Assert.Equal("Ferrari", results[0].GetProperty("teamName").GetString());
    }

    /// <summary>한 사용자로 Jeddah 레이스(링크 41:42:43) 랩 1~3 + 순위표 2대(나 = 차 0, 1위)를 보낸다.</summary>
    private async Task<HttpClient> SeedRaceAsync()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "SESSION-DETAIL-PC");
        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();

        for (var i = 0; i < LapTimes.Length; i++)
        {
            var lapNumber = i + 1;
            var envelope = JsonSerializer.SerializeToNode(LapDetailPayloads.LapFinished(
                lapNumber, LapTimes[i], isValid: true, T0.AddMinutes(2 * lapNumber),
                car: LapDetailPayloads.Car(), conditions: LapDetailPayloads.Conditions(), sessionType: "Race"))!;
            var payload = envelope["payload"]!;
            payload["seasonLinkId"] = 41L;
            payload["weekendLinkId"] = 42L;
            payload["sessionLinkId"] = 43L;
            payload["car"]!["details"] = SnapshotDetails(lapNumber);
            payload["car"]!["teamId"] = FerrariV126TeamId; // 같은 세션의 내 차 = v1.26 팀(2026 시즌팩 → F1 26)
            await SubmitAsync(connection, envelope);
        }

        await SubmitAsync(connection, ClassifiedEnvelope());
        return client;
    }

    /// <summary>Agent의 <c>car.details</c> 모양(f1_25_udp_spec §7). 2·3랩 모두 같은 PENA를 싣는다(중복 제거 확인), 2랩은 피트 중.</summary>
    private static JsonNode SnapshotDetails(int lapNumber)
    {
        var events = lapNumber >= 2
            ? """[{"code":"PENA","lapTimeMs":15000,"details":{"penaltyType":5,"infringementType":4,"vehicleIndex":0,"otherVehicleIndex":1,"timeS":255,"lapNumber":2,"placesGained":255}}]"""
            : "[]";
        return JsonNode.Parse($$"""
            {
              "setup": { "frontWing": 8, "rearWing": 6, "brakeBias": 56 },
              "damage": { "engineMguhWear": 9, "engineEsWear": 7, "engineCeWear": 6, "engineIceWear": {{11 + lapNumber}}, "engineMgukWear": 8, "engineTcWear": 10 },
              "lapData": { "carIndex": 0, "pitStatus": {{(lapNumber == 2 ? 1 : 0)}} },
              "events": {{events}}
            }
            """)!;
    }

    private static JsonNode ClassifiedEnvelope()
    {
        var payload = JsonSerializer.SerializeToNode(SessionClassifiedPayloads.Build(
            carCount: 2, stintsPerCar: 2, seasonLink: 41, weekendLink: 42, sessionLink: 43,
            trackId: LapDetailPayloads.JeddahGameTrackId))!;
        payload["results"]![0]!["teamId"] = FerrariV126TeamId;
        // results[].lapHistory(Agent D-49 모양) → 인입이 최상위 lapHistory로 모은다(SessionDetailsCapture.HistoryFromResults).
        var history = LapTimes.Select((t, i) =>
            $$"""{"lapNumber":{{i + 1}},"lapTimeMs":{{t}},"sector1TimeMs":30000,"sector2TimeMs":31000,"sector3TimeMs":{{t - 61000}},"lapValid":true,"sector1Valid":true,"sector2Valid":true,"sector3Valid":true}""");
        payload["results"]![0]!["lapHistory"] = JsonNode.Parse("[" + string.Join(',', history) + "]");
        payload["lapPositions"] = JsonNode.Parse("""
            [{"lapNumber":1,"positions":[2,1]},{"lapNumber":2,"positions":[1,2]},{"lapNumber":3,"positions":[1,2]}]
            """);

        return new JsonObject
        {
            ["eventId"] = Guid.NewGuid(),
            ["gameCode"] = GameCodes.F1_25,
            ["occurredAt"] = T0.AddMinutes(30),
            ["type"] = "SessionClassified",
            ["payload"] = payload,
        };
    }

    private static async Task SubmitAsync(HubConnection connection, JsonNode envelope)
    {
        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
