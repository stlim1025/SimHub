using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Domain.Constants;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 트랙 개요(<c>GET /tracks/{trackId}/overview</c>): 정적 트랙 정보, 내 통계, 전체 기간 Time Trial 상위(사용자별 최고, 공개 설정),
/// 내 유효 랩 빠른 순, 월드 위치 채널이 있는 트레이스의 가장 빠른 내 랩. 다른 테스트와 겹치지 않게 Hockenheim(F1 25, 8)을 쓴다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class TrackOverviewApiE2ETests : IClassFixture<ApiFactory>
{
    private const int HockenheimGameTrackId = 8;
    private const string RivalName = "Overview Rival";
    private static readonly DateTime T0 = new(2026, 10, 20, 9, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public TrackOverviewApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Overview_CombinesTrackFactsStatsTopTimeTrialAndMapLap()
    {
        var trackId = await TrackIdAsync();

        // 라이벌: TT 87.0s(Ferrari 스냅샷), 88.0s.
        var rival = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(rival);
        await RenameAsync(rival, RivalName);
        await SubmitLapsAsync(rival, "OVERVIEW-RIVAL",
            LapDetailPayloads.LapFinished(1, 87_000, true, T0, car: LapDetailPayloads.Car(), gameTrackId: HockenheimGameTrackId),
            LapDetailPayloads.LapFinished(2, 88_000, true, T0.AddMinutes(1), gameTrackId: HockenheimGameTrackId));

        // 나: TT 90.0s(트레이스 + 월드 위치), TT 89.0s(트레이스만), 무효 TT 85.0s, Race 95.0s.
        var me = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(me);
        var trace = LapDetailPayloads.Trace(samples: 40);
        await SubmitLapsAsync(me, "OVERVIEW-ME",
            LapDetailPayloads.LapFinished(1, 90_000, true, T0, car: LapDetailPayloads.Car(), trace: WithWorldPositions(trace),
                gameTrackId: HockenheimGameTrackId),
            LapDetailPayloads.LapFinished(2, 89_000, true, T0.AddMinutes(1), trace: trace.ToWire(), gameTrackId: HockenheimGameTrackId),
            LapDetailPayloads.LapFinished(3, 85_000, false, T0.AddMinutes(2), gameTrackId: HockenheimGameTrackId),
            LapDetailPayloads.LapFinished(4, 95_000, true, T0.AddMinutes(3), gameTrackId: HockenheimGameTrackId, sessionType: "Race"));

        var overview = await me.GetFromJsonAsync<JsonElement>($"/api/v1/tracks/{trackId}/overview");

        var track = overview.GetProperty("track");
        Assert.Equal((trackId, GameCodes.F1_25, "DE"),
            (track.GetProperty("trackId").GetGuid(), track.GetProperty("gameCode").GetString(), track.GetProperty("countryCode").GetString()));
        Assert.Equal(("Hockenheimring", "German Grand Prix", 4.574, "1:13.780"),
            (track.GetProperty("circuitName").GetString(), track.GetProperty("grandPrixName").GetString(),
                track.GetProperty("lengthKm").GetDouble(), track.GetProperty("f1LapRecord").GetString()));

        var stats = overview.GetProperty("myStats");
        Assert.Equal(4, stats.GetProperty("lapCount").GetInt32());
        Assert.Equal(1, stats.GetProperty("sessionCount").GetInt32()); // 같은 링크 → 같은 세션 키
        Assert.Equal(89_000, stats.GetProperty("bestLapMs").GetInt32());
        Assert.Equal(89_000, stats.GetProperty("bestTimeTrialLapMs").GetInt32());
        Assert.Equal(91_333, stats.GetProperty("averageLapMs").GetInt32()); // 유효 랩 (90+89+95)/3
        Assert.Equal(JsonValueKind.Null, stats.GetProperty("averageAiDifficulty").ValueKind);

        var top = overview.GetProperty("topTimeTrial").EnumerateArray().ToList();
        Assert.Equal(2, top.Count); // 사용자별 최고 1줄
        Assert.Equal((1, RivalName, "Ferrari", 87_000),
            (top[0].GetProperty("rank").GetInt32(), top[0].GetProperty("displayName").GetString(),
                top[0].GetProperty("teamName").GetString(), top[0].GetProperty("lapTimeMs").GetInt32()));
        Assert.Equal((2, 89_000, JsonValueKind.Null),
            (top[1].GetProperty("rank").GetInt32(), top[1].GetProperty("lapTimeMs").GetInt32(), top[1].GetProperty("teamName").ValueKind));

        var myBest = overview.GetProperty("myBestLaps").EnumerateArray().ToList();
        Assert.Equal([89_000, 90_000, 95_000], myBest.Select(l => l.GetProperty("lapTimeMs").GetInt32()));
        Assert.Equal(("TimeTrial", "Ferrari"), (myBest[1].GetProperty("sessionType").GetString(), myBest[1].GetProperty("teamName").GetString()));
        Assert.Equal("Race", myBest[2].GetProperty("sessionType").GetString());

        // 89.0s 트레이스에는 월드 위치가 없다 → 지도는 90.0s 랩.
        Assert.Equal(myBest[1].GetProperty("lapId").GetGuid(), overview.GetProperty("mapLapId").GetGuid());
    }

    [Fact]
    public async Task Overview_WithoutLaps_HasEmptyStats_AndUnknownTrackIs404()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var madrid = await TrackIdAsync(GameCodes.F1_26, 42);

        var overview = await client.GetFromJsonAsync<JsonElement>($"/api/v1/tracks/{madrid}/overview");

        var stats = overview.GetProperty("myStats");
        Assert.Equal((0, 0), (stats.GetProperty("lapCount").GetInt32(), stats.GetProperty("sessionCount").GetInt32()));
        Assert.Equal(JsonValueKind.Null, stats.GetProperty("bestLapMs").ValueKind);
        Assert.Equal(JsonValueKind.Null, stats.GetProperty("averageLapMs").ValueKind);
        Assert.Empty(overview.GetProperty("myBestLaps").EnumerateArray());
        Assert.Equal(JsonValueKind.Null, overview.GetProperty("mapLapId").ValueKind);
        Assert.Equal(("Madring", "Spanish Grand Prix"),
            (overview.GetProperty("track").GetProperty("circuitName").GetString(), overview.GetProperty("track").GetProperty("grandPrixName").GetString()));
        Assert.Equal(JsonValueKind.Null, overview.GetProperty("track").GetProperty("lengthKm").ValueKind);

        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/api/v1/tracks/{Guid.NewGuid()}/overview")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await _factory.CreateClient().GetAsync($"/api/v1/tracks/{madrid}/overview")).StatusCode);
    }

    private static object WithWorldPositions(LapDetailPayloads.TraceChannels t) => new
    {
        resolutionM = t.ResolutionM,
        timeMs = t.TimeMs,
        speedKph = t.SpeedKph,
        throttle = t.Throttle,
        brake = t.Brake,
        steer = t.Steer,
        gear = t.Gear,
        rpm = t.Rpm,
        extra = new Dictionary<string, double[]>
        {
            ["worldPosX"] = t.TimeMs.Select(v => v / 10.0).ToArray(),
            ["worldPosZ"] = t.TimeMs.Select(v => -v / 10.0).ToArray(),
        },
    };

    private Task<Guid> TrackIdAsync() => TrackIdAsync(GameCodes.F1_25, HockenheimGameTrackId);

    private async Task<Guid> TrackIdAsync(string gameCode, int gameTrackId)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return await db.Tracks.Where(t => t.GameCode == gameCode && t.GameTrackId == gameTrackId).Select(t => t.Id).SingleAsync();
    }

    private static async Task RenameAsync(HttpClient client, string displayName)
    {
        using var put = await client.PutAsJsonAsync("/api/v1/me/profile", new
        {
            displayName,
            showOnLeaderboard = true,
            avatarTeam = (string?)null,
            preferredGame = "F1_25",
            controller = "Gamepad",
            console = "PlayStation",
            units = "Metric",
            timeZoneId = "Asia/Seoul",
            theme = "Light",
        });
        put.EnsureSuccessStatusCode();
    }

    private async Task SubmitLapsAsync(HttpClient client, string deviceName, params object[] envelopes)
    {
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, deviceName);
        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        foreach (var envelope in envelopes)
        {
            var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
            Assert.True(ack.Acknowledged, ack.RejectReason);
        }
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
