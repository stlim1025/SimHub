using System.Text.Json;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Outbox;
using SimCenter.Agent.Infrastructure.Sinks;

namespace SimCenter.Agent.Infrastructure.Tests;

public class TelemetryOutboxTests
{
    // 연결이 하나로 유지되므로 :memory: DB가 테스트 수명 동안 보존된다.
    private static TelemetryOutbox NewOutbox()
        => new(Options.Create(new AgentOptions { OutboxPath = ":memory:" }));

    private static DateTime At(int second) => new(2026, 7, 7, 9, 0, second, DateTimeKind.Utc);

    [Fact]
    public async Task EnqueueThenGetPending_ReturnsInOccurredAtOrder()
    {
        await using var outbox = NewOutbox();
        var first = Guid.NewGuid();
        var second = Guid.NewGuid();

        // 나중 시각을 먼저 넣어도 occurredAt 순으로 나와야 한다.
        await outbox.EnqueueAsync(second, At(30), "{\"n\":2}");
        await outbox.EnqueueAsync(first, At(10), "{\"n\":1}");

        var pending = await outbox.GetPendingAsync(10);

        Assert.Equal(2, pending.Count);
        Assert.Equal(first, pending[0].EventId);
        Assert.Equal(second, pending[1].EventId);
    }

    [Fact]
    public async Task Delete_RemovesItem()
    {
        await using var outbox = NewOutbox();
        var id = Guid.NewGuid();
        await outbox.EnqueueAsync(id, At(10), "{}");

        await outbox.DeleteAsync(id);

        Assert.Equal(0, await outbox.CountAsync());
        Assert.Empty(await outbox.GetPendingAsync(10));
    }

    [Fact]
    public async Task Enqueue_DuplicateEventId_IsIgnored()
    {
        await using var outbox = NewOutbox();
        var id = Guid.NewGuid();

        await outbox.EnqueueAsync(id, At(10), "{\"v\":1}");
        await outbox.EnqueueAsync(id, At(20), "{\"v\":2}");

        Assert.Equal(1, await outbox.CountAsync());
    }

    [Fact]
    public async Task OutboxSink_SerializesLapFinished_ToServerWireContract()
    {
        await using var outbox = NewOutbox();
        var sink = new OutboxTelemetrySink(outbox);

        var payload = new LapFinished(
            SessionRef: "0xSESSION",
            LapNumber: 4,
            LapTimeMs: 83452,
            Sectors: [new LapSectorDto(1, 27010), new LapSectorDto(2, 30110), new LapSectorDto(3, 26332)],
            IsValid: true,
            IsOutOrInLap: false,
            TrackId: 7,
            SessionType: SessionType.TimeTrial);

        var envelope = new TelemetryEnvelope(
            Guid.NewGuid(), "A-01", "F1_25",
            new DateTime(2026, 7, 7, 9, 3, 21, DateTimeKind.Utc),
            TelemetryEventType.LapFinished, payload);

        await sink.EmitAsync(envelope);

        var json = (await outbox.GetPendingAsync(1))[0].PayloadJson;
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        // 봉투: camelCase, type은 문자열.
        Assert.Equal("A-01", root.GetProperty("rigCode").GetString());
        Assert.Equal("LapFinished", root.GetProperty("type").GetString());

        // payload: 런타임 타입(LapFinished)의 모든 필드 + enum 문자열.
        var p = root.GetProperty("payload");
        Assert.Equal(83452, p.GetProperty("lapTimeMs").GetInt32());
        Assert.Equal(7, p.GetProperty("trackId").GetInt32());
        Assert.False(p.GetProperty("isOutOrInLap").GetBoolean());
        Assert.Equal("TimeTrial", p.GetProperty("sessionType").GetString());
        Assert.Equal(3, p.GetProperty("sectors").GetArrayLength());
        Assert.Equal(27010, p.GetProperty("sectors")[0].GetProperty("sectorTimeMs").GetInt32());
    }
}
