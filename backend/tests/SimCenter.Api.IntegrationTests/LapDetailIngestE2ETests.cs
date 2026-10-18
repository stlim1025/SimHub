using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Api.Hubs;
using SimCenter.Application.Laps;
using SimCenter.Domain.Enums;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// LapFinished 선택 영역(car·conditions·trace, 15 §4.3·§5) 인입 E2E: Agent → TelemetryHub → DB.
/// 맞는 영역은 랩과 같은 커밋으로 저장되고, 틀린 영역은 그 영역만 버려지며 랩은 언제나 저장된다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class LapDetailIngestE2ETests : IClassFixture<ApiFactory>
{
    private static readonly DateTime OccurredAt = new(2026, 10, 18, 10, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public LapDetailIngestE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task LapFinished_WithCarConditionsTrace_StoresSnapshotAndTrace()
    {
        var (userId, connection) = await ConnectAgentAsync();
        await using var _ = connection;
        var trace = LapDetailPayloads.Trace();
        var envelope = LapDetailPayloads.LapFinished(
            lapNumber: 5, lapTimeMs: 98_448, isValid: true, OccurredAt,
            car: LapDetailPayloads.Car(), conditions: LapDetailPayloads.Conditions(), trace: trace.ToWire());

        // 5m 트레이스를 실은 랩은 허브 수신 한도(1MiB, D-49) 안에 든다.
        Assert.True(TestApi.MeasureInvocationBytes(envelope) < TelemetryHub.MaxMessageBytes);

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var lap = await db.Laps.AsNoTracking().Include(l => l.Snapshot).SingleAsync(l => l.UserId == userId);
        Assert.Equal("DriverCareer", lap.GameMode);
        Assert.NotNull(lap.Snapshot);
        Assert.Equal(1, lap.Snapshot.TeamId);
        Assert.Equal(Weather.LightCloud, lap.Snapshot.Weather);
        Assert.Equal(31.0, lap.Snapshot.TyreWearEndFrontLeft);
        Assert.Equal(18.5, lap.Snapshot.TyreWearEndRearRight);
        Assert.Equal(988_000d, lap.Snapshot.ErsStoreEndJ);

        var stored = await db.LapTelemetryTraces.AsNoTracking().SingleAsync(t => t.LapId == lap.Id);
        Assert.Equal(5, stored.ResolutionM);
        Assert.Equal(LapDetailPayloads.TraceSamples, stored.SampleCount);
        var restored = LapTraceCodec.Decode(stored.Payload);
        Assert.Equal(trace.TimeMs, restored.TimeMs);
        Assert.Equal(trace.Gear, restored.Gear);
        Assert.Equal(trace.Rpm, restored.Rpm);
    }

    [Fact]
    public async Task LapFinished_WithInvalidSnapshotAndTrace_DiscardsOnlyThoseParts()
    {
        var (userId, connection) = await ConnectAgentAsync();
        await using var _ = connection;
        var badCar = new { teamId = 1, engineDamage = 250 };                      // 퍼센트 범위 밖
        var badConditions = new { weather = "Clear", airTempC = "hot" };          // 숫자 자리에 글자
        var badTrace = new { resolutionM = 5, timeMs = new[] { 0, 1 } };            // 채널 6개 없음

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", LapDetailPayloads.LapFinished(
            lapNumber: 2, lapTimeMs: 99_001, isValid: true, OccurredAt, car: badCar, conditions: badConditions, trace: badTrace));

        Assert.True(ack.Acknowledged, ack.RejectReason); // 랩은 절대 거부하지 않는다.
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var lap = await db.Laps.AsNoTracking().Include(l => l.Snapshot).SingleAsync(l => l.UserId == userId);
        Assert.Equal(99_001, lap.LapTimeMs);
        Assert.Null(lap.Snapshot);
        Assert.False(await db.LapTelemetryTraces.AnyAsync(t => t.LapId == lap.Id));
    }

    // ── D-49: 전부 수집 ──

    [Fact]
    public async Task LapFinished_OverOldLimit_WithExtraAndDetails_RoundTripsThroughApi()
    {
        var (client, connection) = await ConnectAgentWithClientAsync();
        await using var _ = connection;
        var trace = LapDetailPayloads.Trace();
        var extra = Enumerable.Range(0, ExtraChannelCount).ToDictionary(
            i => $"channel{i}", i => Enumerable.Range(0, LapDetailPayloads.TraceSamples).Select(s => Math.Round((s * 0.37) + i, 2)).ToArray());
        var car = new { teamId = 1, engineDamage = 30, details = new { setup = new { frontWing = 5, brakeBias = 56.5 }, events = new[] { new { code = "FLBK", t = 12.25 } } } };
        var envelope = LapDetailPayloads.LapFinished(5, 98_448, isValid: true, OccurredAt, car: car,
            trace: WithExtra(trace.ToWire(), extra));

        // 이전 한도(64KiB)를 넘지만 새 한도(1MiB, D-49) 안 — 연결이 끊기지 않고 Ack된다.
        Assert.InRange(TestApi.MeasureInvocationBytes(envelope), OldHubLimitBytes + 1, TelemetryHub.MaxMessageBytes);
        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);

        var lapId = (await client.GetFromJsonAsync<JsonElement>("/api/v1/me/laps"))
            .GetProperty("laps").GetProperty("items")[0].GetProperty("lapId").GetGuid();
        var body = await client.GetFromJsonAsync<JsonElement>($"/api/v1/me/laps/{lapId}/trace");
        var returned = body.GetProperty("extra");
        Assert.Equal(ExtraChannelCount, returned.EnumerateObject().Count());
        Assert.Equal(extra["channel7"], returned.GetProperty("channel7").EnumerateArray().Select(v => v.GetDouble()));
        Assert.Equal(trace.Rpm, body.GetProperty("rpm").EnumerateArray().Select(v => v.GetInt32()));

        var detail = await client.GetFromJsonAsync<JsonElement>($"/api/v1/me/laps/{lapId}");
        var details = detail.GetProperty("car").GetProperty("details");
        Assert.Equal(56.5, details.GetProperty("setup").GetProperty("brakeBias").GetDouble());
        Assert.Equal("FLBK", details.GetProperty("events")[0].GetProperty("code").GetString());
        Assert.Equal(1, detail.GetProperty("car").GetProperty("teamId").GetInt32());
    }

    [Fact]
    public async Task LapFinished_DetailsWithNul_SavesCarWithoutDetails()
    {
        // jsonb는 \u0000을 거부한다 — 그대로 넣으면 커밋이 실패해 같은 랩이 끝없이 재시도된다.
        var (userId, connection) = await ConnectAgentAsync();
        await using var _ = connection;
        var car = new { teamId = 1, engineDamage = 30, details = new { note = "a\u0000b" } };

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent",
            LapDetailPayloads.LapFinished(2, 99_100, isValid: true, OccurredAt, car: car));

        Assert.True(ack.Acknowledged, ack.RejectReason);
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var lap = await db.Laps.AsNoTracking().Include(l => l.Snapshot).SingleAsync(l => l.UserId == userId);
        Assert.Equal(30, lap.Snapshot!.EngineDamage);
        Assert.Null(lap.Snapshot.Details);
    }

    [Fact]
    public async Task SessionClassified_WithLapHistoryAndPositions_StoresJsonb()
    {
        var (userId, connection) = await ConnectAgentAsync();
        await using var _ = connection;
        var payload = new Dictionary<string, object?>(
            JsonSerializer.SerializeToElement(SessionClassifiedPayloads.Build(2, 1, 11, 22, 33)).EnumerateObject()
                .ToDictionary(p => p.Name, p => (object?)p.Value))
        {
            ["lapHistory"] = new[] { new { carIndex = 0, laps = new[] { new { lapTimeMs = 83_452, sector1Ms = 27_010, valid = true } } } },
            ["lapPositions"] = new { numLaps = 1, positions = new[] { new[] { 1, 2 } } },
        };

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", new
        {
            eventId = Guid.NewGuid(), gameCode = "F1_25", occurredAt = OccurredAt, type = "SessionClassified", payload,
        });

        Assert.True(ack.Acknowledged, ack.RejectReason);
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var session = await db.GameSessions.AsNoTracking().SingleAsync(s => s.UserId == userId);
        using var details = JsonDocument.Parse(session.Details!);
        Assert.Equal(83_452, details.RootElement.GetProperty("lapHistory")[0].GetProperty("laps")[0].GetProperty("lapTimeMs").GetInt32());
        Assert.Equal(2, details.RootElement.GetProperty("lapPositions").GetProperty("positions")[0][1].GetInt32());
    }

    private const int ExtraChannelCount = 60;
    private const int OldHubLimitBytes = 64 * 1024;

    private static Dictionary<string, object?> WithExtra(object traceWire, Dictionary<string, double[]> extra)
    {
        var wire = JsonSerializer.SerializeToElement(traceWire).EnumerateObject()
            .ToDictionary(p => p.Name, p => (object?)p.Value);
        wire["extra"] = extra;
        return wire;
    }

    private async Task<(HttpClient Client, HubConnection Connection)> ConnectAgentWithClientAsync()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "DETAIL-PC");

        var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        return (client, connection);
    }

    private async Task<(Guid UserId, HubConnection Connection)> ConnectAgentAsync()
    {
        var client = _factory.CreateClient();
        var userId = await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "DETAIL-PC");

        var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        return (userId, connection);
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
