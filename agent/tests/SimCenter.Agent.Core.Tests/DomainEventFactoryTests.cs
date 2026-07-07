using SimCenter.Agent.Core.Abstractions;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;

namespace SimCenter.Agent.Core.Tests;

public class DomainEventFactoryTests
{
    [Fact]
    public void Wrap_PopulatesEnvelope_FromClockIdAndIdentity()
    {
        var occurredAt = new DateTime(2026, 7, 7, 3, 0, 0, DateTimeKind.Utc);
        var eventId = Guid.Parse("019f3ac0-0000-7000-8000-000000000001");
        var factory = new DomainEventFactory(
            new FakeClock(occurredAt),
            new FixedIdGenerator(eventId),
            new AgentIdentity("A-01", "F1_25"));

        var payload = new LapStarted("1001", 3);

        var envelope = factory.Wrap(payload);

        Assert.Equal(eventId, envelope.EventId);
        Assert.Equal("A-01", envelope.RigCode);
        Assert.Equal("F1_25", envelope.GameCode);
        Assert.Equal(occurredAt, envelope.OccurredAt);
        Assert.Equal(TelemetryEventType.LapStarted, envelope.Type);
        Assert.Same(payload, envelope.Payload);
    }

    private sealed class FakeClock(DateTime utcNow) : IClock
    {
        public DateTime UtcNow { get; } = utcNow;
    }

    private sealed class FixedIdGenerator(Guid id) : IIdGenerator
    {
        public Guid NewId() => id;
    }
}
