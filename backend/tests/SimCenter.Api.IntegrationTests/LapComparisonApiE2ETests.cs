using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Infrastructure.Persistence;
using SimCenter.Infrastructure.Persistence.Migrations;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 랩 상세 비교 대상·필터·어시스트 한 바퀴(docs/15 §10, D-51): 허브 → DB → <c>GET /me/laps/{id}?compare=…</c>·<c>GET /laps/{id}/trace</c>.
/// 공개 규칙(남의 랩은 랭킹 적격만, 그 밖은 notFound/404)·이름 규칙(이름 비공개 = 익명, D-39)·같은 어시스트 필터.
/// 다른 테스트와 겹치지 않게 Suzuka(게임 트랙 13)만 쓴다 — 리더보드 최고 랩이 이 테스트의 랩으로 정해진다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class LapComparisonApiE2ETests : IClassFixture<ApiFactory>
{
    private const int SuzukaGameTrackId = 13;
    private const string RivalName = "공개 라이벌";
    private const string HiddenName = "숨은 라이벌";
    private const string AnonymousName = "익명 드라이버";

    private static readonly DateTime T0 = new(2026, 10, 18, 12, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public LapComparisonApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task CompareOptions_PrivacyAndAssists_RoundTrip()
    {
        // 나: 이 랩(98.0s, 어시스트 A) + 내 최고(97.0s).
        var (me, meHub) = await DriverAsync(name: null, showOnLeaderboard: true);
        await using var meConnection = meHub;
        await SubmitAsync(meConnection, Lap(2, 97_000, T0, car: Car(AssistsA)));
        await SubmitAsync(meConnection, Lap(3, 98_000, T0.AddMinutes(2), car: Car(AssistsA)));

        // 공개 라이벌: TT 92.0s(어시스트 A, 트레이스) + 레이스 85.0s(랭킹 부적격 = 비공개).
        var (rival, rivalHub) = await DriverAsync(RivalName, showOnLeaderboard: true);
        await using var rivalConnection = rivalHub;
        await SubmitAsync(rivalConnection, Lap(4, 92_000, T0, car: Car(AssistsA), trace: LapDetailPayloads.Trace(samples: 50).ToWire()));
        await SubmitAsync(rivalConnection, Lap(5, 85_000, T0.AddMinutes(1), car: Car(AssistsA), sessionType: "Race",
            trace: LapDetailPayloads.Trace(samples: 50).ToWire()));

        // 이름 비공개 라이벌: TT 90.0s(어시스트 B) — 리더보드 1위.
        var (_, hiddenHub) = await DriverAsync(HiddenName, showOnLeaderboard: false);
        await using var hiddenConnection = hiddenHub;
        await SubmitAsync(hiddenConnection, Lap(6, 90_000, T0, car: Car(AssistsB)));

        var current = await LapIdAsync(me, 98_000);
        var myBest = await LapIdAsync(me, 97_000);
        var rivalTt = await LapIdAsync(rival, 92_000);
        var rivalRace = await LapIdAsync(rival, 85_000);

        // 기본 = 내 최고 + 어시스트.
        var detail = await Detail(me, current, "");
        var comparison = detail.GetProperty("comparison");
        Assert.Equal("best", comparison.GetProperty("kind").GetString());
        Assert.Equal(myBest, comparison.GetProperty("lapId").GetGuid());
        Assert.True(comparison.GetProperty("isMine").GetBoolean());
        Assert.Equal(JsonValueKind.Null, comparison.GetProperty("displayName").ValueKind);
        Assert.Equal("Ferrari", comparison.GetProperty("team").GetProperty("name").GetString());
        Assert.Equal(JsonValueKind.Null, detail.GetProperty("comparisonUnavailable").ValueKind);
        var assists = detail.GetProperty("assists");
        Assert.Equal("Medium", assists.GetProperty("tractionControl").GetString());
        Assert.Equal("On", assists.GetProperty("antiLockBrakes").GetString());
        Assert.Equal("Off", assists.GetProperty("steeringAssist").GetString());
        Assert.Equal("Off", assists.GetProperty("brakingAssist").GetString());
        Assert.Equal("Manual", assists.GetProperty("gearbox").GetString());
        Assert.Equal("CornersOnly", assists.GetProperty("racingLine").GetString());

        // 리더보드 최고 = 이름 비공개 라이벌 → 익명.
        var leaderboard = (await Detail(me, current, "?compare=leaderboard")).GetProperty("comparison");
        Assert.Equal("leaderboard", leaderboard.GetProperty("kind").GetString());
        Assert.Equal(90_000, leaderboard.GetProperty("lapTimeMs").GetInt32());
        Assert.False(leaderboard.GetProperty("isMine").GetBoolean());
        Assert.Equal(AnonymousName, leaderboard.GetProperty("displayName").GetString());
        Assert.DoesNotContain(HiddenName, leaderboard.GetRawText());

        // 같은 어시스트 → 어시스트 B인 1위를 건너뛰고 공개 라이벌의 TT 랩(레이스 랩은 부적격이라 제외).
        var sameAssists = (await Detail(me, current, "?compare=leaderboard&sameAssists=true&sameSessionType=true")).GetProperty("comparison");
        Assert.Equal(rivalTt, sameAssists.GetProperty("lapId").GetGuid());
        Assert.Equal(RivalName, sameAssists.GetProperty("displayName").GetString());
        Assert.True(sameAssists.GetProperty("hasTrace").GetBoolean());
        Assert.Equal(new[] { "sameSessionType", "sameAssists" },
            sameAssists.GetProperty("appliedFilters").EnumerateArray().Select(f => f.GetString()));

        // 랩 ID: 남의 공개 랩은 되고, 비공개(레이스) 랩·없는 랩은 notFound.
        var byId = (await Detail(me, current, $"?compare=lap&compareLapId={rivalTt}")).GetProperty("comparison");
        Assert.Equal("lap", byId.GetProperty("kind").GetString());
        Assert.Equal(RivalName, byId.GetProperty("displayName").GetString());
        foreach (var hiddenId in new[] { rivalRace, Guid.NewGuid() })
        {
            var refused = await Detail(me, current, $"?compare=lap&compareLapId={hiddenId}");
            Assert.Equal(JsonValueKind.Null, refused.GetProperty("comparison").ValueKind);
            Assert.Equal("notFound", refused.GetProperty("comparisonUnavailable").GetString());
        }

        // 비교 안 함.
        var none = await Detail(me, current, "?compare=none");
        Assert.Equal(JsonValueKind.Null, none.GetProperty("comparison").ValueKind);
        Assert.Equal(JsonValueKind.Null, none.GetProperty("comparisonUnavailable").ValueKind);

        // 비교 트레이스: 내 랩·남의 공개 랩 = 200, 남의 비공개 랩·없는 랩·트레이스 없는 랩 = 404.
        Assert.Equal(HttpStatusCode.OK, (await me.GetAsync($"/api/v1/laps/{rivalTt}/trace")).StatusCode);
        var rivalTrace = await me.GetFromJsonAsync<JsonElement>($"/api/v1/laps/{rivalTt}/trace");
        Assert.Equal(50, rivalTrace.GetProperty("sampleCount").GetInt32());
        Assert.Equal(HttpStatusCode.NotFound, (await me.GetAsync($"/api/v1/laps/{rivalRace}/trace")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await me.GetAsync($"/api/v1/laps/{Guid.NewGuid()}/trace")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await me.GetAsync($"/api/v1/laps/{myBest}/trace")).StatusCode);
        // 주인은 자기 레이스 랩 트레이스를 읽을 수 있다.
        Assert.Equal(HttpStatusCode.OK, (await rival.GetAsync($"/api/v1/laps/{rivalRace}/trace")).StatusCode);
    }

    [Fact]
    public async Task InvalidCompareQuery_IsBadRequest_AndTraceNeedsLogin()
    {
        var (me, hub) = await DriverAsync(name: null, showOnLeaderboard: true);
        await using var connection = hub;
        await SubmitAsync(connection, Lap(2, 99_500, T0.AddHours(1)));
        var lapId = await LapIdAsync(me, 99_500);

        Assert.Equal(HttpStatusCode.BadRequest, (await me.GetAsync($"/api/v1/me/laps/{lapId}?compare=lap")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await me.GetAsync($"/api/v1/me/laps/{lapId}?compare=fastest")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await me.GetAsync($"/api/v1/me/laps/{lapId}?compare=7")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await me.GetAsync($"/api/v1/me/laps/{lapId}?compare=Leaderboard")).StatusCode);

        // 어시스트를 모르는 랩(details 없음) = assists null.
        var detail = await Detail(me, lapId, "");
        Assert.Equal(JsonValueKind.Null, detail.GetProperty("assists").ValueKind);

        var anonymous = _factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync($"/api/v1/laps/{lapId}/trace")).StatusCode);
    }

    [Fact]
    public async Task MigrationBackfill_ReadsAssistsFromStoredDetails()
    {
        var (me, hub) = await DriverAsync(name: null, showOnLeaderboard: true);
        await using var connection = hub;
        var details = new
        {
            status = new { tractionControl = "1", antiLockBrakes = 1 },                      // 문자열 → null
            session = new { steeringAssist = 1.5, brakingAssist = 3, gearboxAssist = 300, dynamicRacingLine = 2 }, // 소수·범위 밖 → null
        };
        await SubmitAsync(connection, Lap(7, 99_700, T0.AddHours(2), car: Car(details)));
        var lapId = await LapIdAsync(me, 99_700);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        // 옛 행처럼 열을 비운 뒤 마이그레이션의 채우기 문장을 다시 돌린다.
        await db.LapSnapshots.Where(s => s.LapId == lapId).ExecuteUpdateAsync(s => s
            .SetProperty(x => x.TractionControl, (int?)null).SetProperty(x => x.AntiLockBrakes, (int?)null)
            .SetProperty(x => x.SteeringAssist, (int?)null).SetProperty(x => x.BrakingAssist, (int?)null)
            .SetProperty(x => x.GearboxAssist, (int?)null).SetProperty(x => x.DynamicRacingLine, (int?)null));
        await db.Database.ExecuteSqlRawAsync(AddLapSnapshotAssists.BackfillSql);

        var snapshot = await db.LapSnapshots.AsNoTracking().SingleAsync(s => s.LapId == lapId);
        Assert.Equal(
            (null, 1, null, 3, null, 2),
            (snapshot.TractionControl, snapshot.AntiLockBrakes, snapshot.SteeringAssist, snapshot.BrakingAssist,
                snapshot.GearboxAssist, snapshot.DynamicRacingLine));
    }

    [Fact]
    public async Task Swagger_DescribesComparableTraceEndpoint()
    {
        var swagger = await _factory.CreateClient().GetFromJsonAsync<JsonElement>("/swagger/v1/swagger.json");

        Assert.True(swagger.GetProperty("paths").TryGetProperty("/api/v1/laps/{lapId}/trace", out _));
    }

    private static readonly object AssistsA = new
    {
        status = new { tractionControl = 1, antiLockBrakes = 1 },
        session = new { steeringAssist = 0, brakingAssist = 0, gearboxAssist = 1, dynamicRacingLine = 1 },
    };

    private static readonly object AssistsB = new
    {
        status = new { tractionControl = 0, antiLockBrakes = 0 },
        session = new { steeringAssist = 0, brakingAssist = 0, gearboxAssist = 1, dynamicRacingLine = 0 },
    };

    private static object Car(object details) => new { teamId = 1, engineDamage = 0, details };

    private static object Lap(int lapNumber, int lapTimeMs, DateTime at, object? car = null, object? trace = null, string sessionType = "TimeTrial")
        => LapDetailPayloads.LapFinished(
            lapNumber, lapTimeMs, isValid: true, at, sessionRef: "0xCOMPARE", car: car, trace: trace,
            gameTrackId: SuzukaGameTrackId, sessionType: sessionType);

    /// <summary>새 드라이버(로그인된 클라이언트 + 시작된 텔레메트리 연결). <paramref name="name"/>이 있으면 프로필 이름·공개 설정을 바꾼다.</summary>
    private async Task<(HttpClient Client, HubConnection Connection)> DriverAsync(string? name, bool showOnLeaderboard)
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        if (name is not null)
        {
            using var put = await client.PutAsJsonAsync("/api/v1/me/profile", new
            {
                displayName = name,
                showOnLeaderboard,
                avatarTeam = (string?)null,
                preferredGame = "F1_25",
                controller = "Gamepad",
                console = "PlayStation",
                units = "Metric",
                timeZoneId = "Europe/London",
                theme = "Dark",
            });
            put.EnsureSuccessStatusCode();
        }

        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "COMPARE-PC");
        var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        return (client, connection);
    }

    private static async Task SubmitAsync(HubConnection connection, object envelope)
    {
        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);
    }

    private static async Task<Guid> LapIdAsync(HttpClient client, int lapTimeMs)
    {
        var laps = await client.GetFromJsonAsync<JsonElement>("/api/v1/me/laps?pageSize=50");
        return laps.GetProperty("laps").GetProperty("items").EnumerateArray()
            .Single(l => l.GetProperty("lapTimeMs").GetInt32() == lapTimeMs)
            .GetProperty("lapId").GetGuid();
    }

    private static async Task<JsonElement> Detail(HttpClient client, Guid lapId, string query)
    {
        using var response = await client.GetAsync($"/api/v1/me/laps/{lapId}{query}");
        Assert.True(response.IsSuccessStatusCode, $"{response.StatusCode}: {await response.Content.ReadAsStringAsync()}");
        return await response.Content.ReadFromJsonAsync<JsonElement>();
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
