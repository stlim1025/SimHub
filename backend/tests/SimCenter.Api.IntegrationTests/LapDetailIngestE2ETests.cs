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

        // 5m 트레이스를 실은 랩도 허브 수신 한도(64KiB) 안에 든다 — 한도는 그대로 둔다.
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
