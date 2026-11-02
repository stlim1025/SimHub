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
/// 이론상 최고 랩(<c>GET /tracks/{trackId}/theoretical-best</c>): 트레이스가 있는 내 Time Trial 랩들을 구간마다 이어 붙인다(레이스 랩은 쓰지 않는다).
/// 1km 트랙(10m 간격 100칸) — 코너 300~400m · 700~780m(횡 G 1.6) → 구간 [0, 270) · [270, 670) · [670, 1000).
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class TheoreticalBestApiE2ETests : IClassFixture<ApiFactory>
{
    private const int MonzaGameTrackId = 11;
    private const int SampleCount = 100;
    private const int ResolutionM = 10;
    private static readonly int[] Edges = [0, 27, 67, SampleCount - 1];
    private static readonly DateTime T0 = new(2026, 10, 25, 9, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public TheoreticalBestApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task TheoreticalBest_JoinsTheFastestSegmentsOfMyTimeTrialLaps()
    {
        var trackId = await TrackIdAsync();
        var me = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(me);
        await SubmitLapsAsync(me, "THEORETICAL-ME",
            LapDetailPayloads.LapFinished(1, 100_000, true, T0, trace: Trace([30_000, 40_000, 30_000]), gameTrackId: MonzaGameTrackId),
            LapDetailPayloads.LapFinished(2, 100_200, true, T0.AddMinutes(1), trace: Trace([29_500, 40_500, 30_200]), gameTrackId: MonzaGameTrackId),
            LapDetailPayloads.LapFinished(3, 95_000, true, T0.AddMinutes(2), trace: Trace([25_000, 40_000, 30_000]),
                gameTrackId: MonzaGameTrackId, sessionType: "Race"),
            // 비 오는 랩은 마른 노면 랩과 잇지 않고 따로 조건이 된다.
            LapDetailPayloads.LapFinished(4, 99_000, true, T0.AddMinutes(3), trace: Trace([29_000, 40_000, 30_000]),
                conditions: new { weather = "LightRain", airTempC = 18, trackTempC = 22, rainForecastPercent = 80 }, gameTrackId: MonzaGameTrackId));

        var response = await me.GetFromJsonAsync<JsonElement>($"/api/v1/tracks/{trackId}/theoretical-best");

        var groups = response.GetProperty("groups").EnumerateArray().ToList();
        Assert.Equal([false, true], groups.Select(g => g.GetProperty("isWet").GetBoolean()));
        Assert.Equal((1, 99_000), (groups[1].GetProperty("lapCount").GetInt32(), groups[1].GetProperty("theoreticalMs").GetInt32()));
        var group = groups[0];
        Assert.Equal(("TimeTrial", 2, 1000), (group.GetProperty("sessionType").GetString(), group.GetProperty("lapCount").GetInt32(), group.GetProperty("lapLengthM").GetInt32()));
        Assert.Equal((100_000, 99_500, 99_500),
            (group.GetProperty("bestLapMs").GetInt32(), group.GetProperty("theoreticalMs").GetInt32(), group.GetProperty("unlimitedMs").GetInt32()));
        Assert.False(group.GetProperty("hasBattery").GetBoolean());
        var segments = group.GetProperty("segments").EnumerateArray().ToList();
        Assert.Equal([29_500, 40_000, 30_000], segments.Select(s => s.GetProperty("timeMs").GetInt32()));
        Assert.Equal(group.GetProperty("bestLapId").GetGuid(), segments[1].GetProperty("lapId").GetGuid());
        Assert.NotEqual(group.GetProperty("bestLapId").GetGuid(), segments[0].GetProperty("lapId").GetGuid());

        Assert.Equal(HttpStatusCode.NotFound, (await me.GetAsync($"/api/v1/tracks/{Guid.NewGuid()}/theoretical-best")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await _factory.CreateClient().GetAsync($"/api/v1/tracks/{trackId}/theoretical-best")).StatusCode);

        // 다른 사용자에게는 내 랩이 재료가 되지 않는다.
        var other = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(other);
        var empty = await other.GetFromJsonAsync<JsonElement>($"/api/v1/tracks/{trackId}/theoretical-best");
        Assert.Empty(empty.GetProperty("groups").EnumerateArray());
    }

    /// <summary>구간 시간 [segmentMs]로 달린 1km 트레이스(와이어 모양). 횡 G만 추가 채널로 싣는다.</summary>
    private static object Trace(int[] segmentMs)
    {
        var time = new int[SampleCount];
        double elapsed = 0;
        for (var s = 0; s < segmentMs.Length; s++)
        {
            var (from, to) = (Edges[s], Edges[s + 1]);
            var span = s == segmentMs.Length - 1 ? to - from + 1 : to - from;
            for (var i = from + 1; i <= to; i++)
            {
                time[i] = (int)Math.Round(elapsed + segmentMs[s] * (double)(i - from) / span);
            }

            elapsed += segmentMs[s];
        }

        var flat = new int[SampleCount];
        return new
        {
            resolutionM = ResolutionM,
            timeMs = time,
            speedKph = Enumerable.Repeat(200, SampleCount).ToArray(),
            throttle = flat,
            brake = flat,
            steer = flat,
            gear = Enumerable.Repeat(6, SampleCount).ToArray(),
            rpm = Enumerable.Repeat(11_000, SampleCount).ToArray(),
            extra = new Dictionary<string, double[]>
            {
                ["gForceLateral"] = Enumerable.Range(0, SampleCount).Select(i => i is >= 30 and <= 40 or >= 70 and <= 78 ? 1.6 : 0).ToArray(),
            },
        };
    }

    private async Task<Guid> TrackIdAsync()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return await db.Tracks.Where(t => t.GameCode == GameCodes.F1_25 && t.GameTrackId == MonzaGameTrackId).Select(t => t.Id).SingleAsync();
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
