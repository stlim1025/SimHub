using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Agent.Core.Abstractions;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using SimCenter.Agent.Infrastructure.Pipeline;
using SimCenter.Agent.Infrastructure.Sinks;
using SimCenter.Agent.Infrastructure.Udp;

namespace SimCenter.Agent.Infrastructure.Tests;

public class TelemetryPipelineAnalyzerTests
{
    private const int ExpectedPacketFormat = 2025;
    private static readonly DateTime Now = new(2026, 10, 17, 9, 0, 0, DateTimeKind.Utc);

    private static EventMarker Frame(string sessionRef = "s1") => new(sessionRef, SessionBoundary.Start);

    private static ITelemetryAnalyzer Emitting(TelemetryEvent telemetryEvent, List<ITelemetryFrame>? seen = null) =>
        new FakeAnalyzer(frame =>
        {
            seen?.Add(frame);
            return [telemetryEvent];
        });

    private static ITelemetryAnalyzer Throwing(List<ITelemetryFrame>? seen = null) =>
        new FakeAnalyzer(frame =>
        {
            seen?.Add(frame);
            throw new InvalidOperationException("분석기 오류");
        });

    private static TelemetryPipeline NewPipeline(
        IEnumerable<ITelemetryAnalyzer> analyzers,
        ITelemetrySink sink,
        ILogger<TelemetryPipeline>? logger = null)
    {
        var clock = new FixedClock();
        return new TelemetryPipeline(
            new UdpTelemetryListener(port: 0, NullLogger<UdpTelemetryListener>.Instance),
            new F1PacketMapper(ExpectedPacketFormat, NullLogger<F1PacketMapper>.Instance),
            analyzers,
            new DomainEventFactory(clock, new SequentialIds(), new AgentIdentity("F1_25")),
            sink,
            new GameConnectionMonitor(clock, new ConnectionThresholds()),
            logger ?? NullLogger<TelemetryPipeline>.Instance);
    }

    [Theory]
    [InlineData(true)]    // 던지는 분석기가 앞
    [InlineData(false)]   // 던지는 분석기가 뒤 — 순서에 의존하지 않는다
    public async Task ThrowingAnalyzer_DoesNotBlockOthers(bool throwingFirst)
    {
        var sink = new CapturingSink();
        var healthy = Emitting(new LapStarted("s1", 1));
        ITelemetryAnalyzer[] analyzers = throwingFirst ? [Throwing(), healthy] : [healthy, Throwing()];
        var sut = NewPipeline(analyzers, sink);

        await sut.ProcessFramesAsync([Frame()], CancellationToken.None);

        var envelope = Assert.Single(sink.Envelopes);
        Assert.Equal(TelemetryEventType.LapStarted, envelope.Type);
    }

    [Fact]
    public async Task ThrowingAnalyzer_IsLoggedAsError_AndStillCalledForNextFrames()
    {
        var logger = new CapturingLogger<TelemetryPipeline>();
        var seen = new List<ITelemetryFrame>();
        var sut = NewPipeline([Throwing(seen)], new CapturingSink(), logger);

        await sut.ProcessFramesAsync([Frame("a"), Frame("b")], CancellationToken.None);

        Assert.Equal(2, seen.Count);   // 첫 프레임의 예외가 분석기를 죽이지 않는다
        Assert.Equal(2, logger.Entries.Count(e => e.Level == LogLevel.Error));
    }

    [Fact]
    public async Task EveryAnalyzer_SeesEveryFrame_InOrder()
    {
        var seenByFirst = new List<ITelemetryFrame>();
        var seenBySecond = new List<ITelemetryFrame>();
        var sut = NewPipeline(
            [Emitting(new LapStarted("a", 1), seenByFirst), Emitting(new LapStarted("b", 1), seenBySecond)],
            new CapturingSink());
        var frames = new ITelemetryFrame[] { Frame("a"), Frame("b"), Frame("c") };

        await sut.ProcessFramesAsync(frames, CancellationToken.None);

        Assert.Equal(frames, seenByFirst);
        Assert.Equal(frames, seenBySecond);
    }

    [Fact]
    public async Task EventsAreWrappedAndEmitted_PerFrame_PerAnalyzer()
    {
        var sink = new CapturingSink();
        var sut = NewPipeline([Emitting(new LapStarted("s1", 1)), Emitting(new SessionEnded("s1"))], sink);

        await sut.ProcessFramesAsync([Frame(), Frame()], CancellationToken.None);

        Assert.Equal(
            [TelemetryEventType.LapStarted, TelemetryEventType.SessionEnded, TelemetryEventType.LapStarted, TelemetryEventType.SessionEnded],
            sink.Envelopes.Select(e => e.Type));
        Assert.All(sink.Envelopes, e => Assert.Equal("F1_25", e.GameCode));
        Assert.Equal(sink.Envelopes.Count, sink.Envelopes.Select(e => e.EventId).Distinct().Count());   // 멱등키는 이벤트마다 새로
    }

    [Fact]
    public async Task SinkFailure_ForOneAnalyzer_DoesNotBlockTheOther()
    {
        var sink = new CapturingSink { FailOn = TelemetryEventType.LapStarted };
        var sut = NewPipeline([Emitting(new LapStarted("s1", 1)), Emitting(new SessionEnded("s1"))], sink);

        await sut.ProcessFramesAsync([Frame()], CancellationToken.None);

        var envelope = Assert.Single(sink.Envelopes);
        Assert.Equal(TelemetryEventType.SessionEnded, envelope.Type);
    }

    [Fact]
    public async Task Cancellation_IsNotSwallowed()
    {
        using var cts = new CancellationTokenSource();
        cts.Cancel();
        var sink = new CapturingSink { ThrowCancellation = true };
        var sut = NewPipeline([Emitting(new LapStarted("s1", 1))], sink);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => sut.ProcessFramesAsync([Frame()], cts.Token));
    }

    private sealed class FakeAnalyzer(Func<ITelemetryFrame, IReadOnlyList<TelemetryEvent>> process) : ITelemetryAnalyzer
    {
        public IReadOnlyList<TelemetryEvent> Process(ITelemetryFrame frame) => process(frame);
    }

    private sealed class CapturingSink : ITelemetrySink
    {
        public List<TelemetryEnvelope> Envelopes { get; } = [];

        public TelemetryEventType? FailOn { get; init; }

        public bool ThrowCancellation { get; init; }

        public Task EmitAsync(TelemetryEnvelope envelope, CancellationToken cancellationToken = default)
        {
            if (ThrowCancellation)
            {
                throw new OperationCanceledException();
            }

            if (envelope.Type == FailOn)
            {
                throw new InvalidOperationException("싱크 오류");
            }

            Envelopes.Add(envelope);
            return Task.CompletedTask;
        }
    }

    private sealed class FixedClock : IClock
    {
        public DateTime UtcNow => Now;
    }

    private sealed class SequentialIds : IIdGenerator
    {
        private int _next;

        public Guid NewId() => new(++_next, 0, 0, new byte[8]);
    }

    private sealed class CapturingLogger<T> : ILogger<T>
    {
        public List<(LogLevel Level, string Message)> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Entries.Add((logLevel, formatter(state, exception)));
    }
}
