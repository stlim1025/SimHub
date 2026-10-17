using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// Agent → TelemetryHub → DB 전체 경로 E2E(11 §10). 실 PostgreSQL(로컬 dev)이 필요하다.
/// 흐름: 회원가입 → 로그인 → 코드 발급 → 장치 연결 → 장치 키로 Hub 접속 → LapFinished 전송 → 장치 주인 귀속 확인
/// → 장치 연결 해제 → 이미 열린 연결로 보낸 다음 이벤트는 Reject.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class TelemetryIngestE2ETests : IClassFixture<ApiFactory>
{
    private const string RevokedDeviceReason = "연결이 해제된 장치입니다.";
    private const int LapTimeMs = 83452;

    private static readonly DateTime OccurredAt = new(2026, 7, 7, 9, 3, 21, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public TelemetryIngestE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task LapFinished_FromPairedDevice_IsAttributedAndPersisted()
    {
        var client = _factory.CreateClient();

        // 1. 가입·로그인 → 코드 발급 → 장치 연결(장치 키 1회 수신).
        var userId = await TestApi.RegisterAndLoginAsync(client);
        var (deviceId, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-PC");

        // 2. 장치 키로 Hub 접속. 실제 Agent처럼 WebSocket 한 연결을 유지한다(해제 후에도 같은 연결로 전송).
        await using var connection = BuildConnection(deviceKey);
        await connection.StartAsync();

        // 3. LapFinished 전송(봉투에 rigCode 없음).
        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", LapFinishedEnvelope(Guid.NewGuid()));
        Assert.True(ack.Acknowledged, ack.RejectReason);

        // 4. DB: 랩이 장치 주인에게, 그 장치로 귀속 저장됐다. 장치 마지막 수신 시각도 기록됐다.
        var (lapTrackId, sectorCount) = await AssertLapAttributedAsync(userId, deviceId);
        Assert.Equal(3, sectorCount);

        // 5. 내 랩 기록(REST): 개인 최고 + 섹터 3개.
        var myLaps = await client.GetFromJsonAsync<JsonElement>($"/api/v1/me/laps?trackId={lapTrackId}");
        Assert.Equal(LapTimeMs, myLaps.GetProperty("personalBest").GetProperty("lapTimeMs").GetInt32());
        Assert.Contains(myLaps.GetProperty("laps").GetProperty("items").EnumerateArray(), it =>
            it.GetProperty("lapTimeMs").GetInt32() == LapTimeMs && it.GetProperty("sectors").GetArrayLength() == 3);

        // 6. 랭킹 REST(monthly): 적격 랩이 TOP10에 반영된다(occurredAt 2026-07-07 → 서울 7월).
        var rankings = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/rankings?trackId={lapTrackId}&period=monthly&date=2026-07-07");
        Assert.Equal("2026-07", rankings.GetProperty("periodKey").GetString());
        Assert.Contains(rankings.GetProperty("entries").EnumerateArray(),
            e => e.GetProperty("bestLapTimeMs").GetInt32() == LapTimeMs);

        // 7. 장치 연결 해제 → 이미 열린 연결로 보낸 새 이벤트는 Reject.
        var revoke = await client.DeleteAsync($"/api/v1/me/agent-devices/{deviceId}");
        Assert.Equal(HttpStatusCode.NoContent, revoke.StatusCode);

        var rejected = await connection.InvokeAsync<SubmitAck>("SubmitEvent", LapFinishedEnvelope(Guid.NewGuid()));
        Assert.False(rejected.Acknowledged);
        Assert.Equal(RevokedDeviceReason, rejected.RejectReason);
    }

    /// <summary>사용자의 랩이 정확히 1개이고 연결한 장치로 귀속됐는지 확인한다. (트랙 ID, 섹터 수)를 돌려준다.</summary>
    private async Task<(Guid TrackId, int SectorCount)> AssertLapAttributedAsync(Guid userId, Guid deviceId)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var lap = Assert.Single(await db.Laps.Include(l => l.Sectors).Where(l => l.UserId == userId).ToListAsync());
        Assert.Equal(deviceId, lap.AgentDeviceId);
        Assert.Equal(LapTimeMs, lap.LapTimeMs);
        Assert.True(lap.IsRankingEligible);

        var device = await db.AgentDevices.SingleAsync(d => d.Id == deviceId);
        Assert.NotNull(device.LastSeenAt);

        return (lap.TrackId, lap.Sectors.Count);
    }

    private static object LapFinishedEnvelope(Guid eventId) => new
    {
        eventId,
        gameCode = "F1_25",
        occurredAt = OccurredAt,
        type = "LapFinished",
        payload = new
        {
            sessionRef = "0xSESSION",
            lapNumber = 4,
            lapTimeMs = LapTimeMs,
            sectors = new[]
            {
                new { sectorNumber = 1, sectorTimeMs = 27010 },
                new { sectorNumber = 2, sectorTimeMs = 30110 },
                new { sectorNumber = 3, sectorTimeMs = 26332 },
            },
            isValid = true,
            isOutOrInLap = false,
            trackId = 7, // Silverstone
            sessionType = "TimeTrial",
        },
    };

    /// <summary>
    /// TestServer WebSocket으로 Hub에 접속한다. LongPolling은 요청마다 인증을 다시 하므로
    /// "해제 후 이미 열린 연결로 전송" 경로(인입 서비스의 장치 재확인)를 검증하려면 WebSocket이 필요하다.
    /// </summary>
    private HubConnection BuildConnection(string deviceKey)
    {
        return new HubConnectionBuilder()
            .WithUrl(new Uri(_factory.Server.BaseAddress, "hubs/telemetry"), options =>
            {
                options.Transports = HttpTransportType.WebSockets;
                options.SkipNegotiation = true;
                options.WebSocketFactory = async (context, cancellationToken) =>
                {
                    var webSocketClient = _factory.Server.CreateWebSocketClient();
                    webSocketClient.ConfigureRequest = request => request.Headers["X-Agent-Key"] = deviceKey;
                    return await webSocketClient.ConnectAsync(context.Uri, cancellationToken);
                };
            })
            .AddJsonProtocol(json =>
            {
                json.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
                json.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
                json.PayloadSerializerOptions.Converters.Add(new JsonStringEnumConverter());
            })
            .Build();
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
