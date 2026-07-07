using SimCenter.Agent.Core.Abstractions;
using SimCenter.Agent.Core.Connection;

namespace SimCenter.Agent.Core.Tests;

public class GameConnectionMonitorTests
{
    private static readonly DateTime T0 = new(2026, 7, 7, 3, 0, 0, DateTimeKind.Utc);

    private static (GameConnectionMonitor monitor, MutableClock clock) Create()
    {
        var clock = new MutableClock(T0);
        var thresholds = new ConnectionThresholds { ConnectedWithinMs = 2000, WaitingWithinMs = 6000 };
        return (new GameConnectionMonitor(clock, thresholds), clock);
    }

    [Fact]
    public void BeforeListening_WithNoDatagram_IsDisconnected()
    {
        var (monitor, _) = Create();

        var snapshot = monitor.GetSnapshot();

        Assert.Equal(ConnectionState.Disconnected, snapshot.State);
        Assert.Null(snapshot.LastDatagramAt);
        Assert.Equal(0, snapshot.TotalDatagrams);
    }

    [Fact]
    public void AfterListening_WithinWaitingWindow_IsWaiting()
    {
        var (monitor, clock) = Create();
        monitor.MarkListening();

        clock.Advance(TimeSpan.FromSeconds(3)); // < WaitingWithinMs(6s)

        Assert.Equal(ConnectionState.Waiting, monitor.GetSnapshot().State);
    }

    [Fact]
    public void AfterListening_PastWaitingWindow_WithoutDatagram_IsDisconnected()
    {
        var (monitor, clock) = Create();
        monitor.MarkListening();

        clock.Advance(TimeSpan.FromSeconds(7)); // > WaitingWithinMs(6s)

        Assert.Equal(ConnectionState.Disconnected, monitor.GetSnapshot().State);
    }

    [Fact]
    public void RecentDatagram_IsConnected_AndRecordsPacketFormat()
    {
        var (monitor, clock) = Create();
        monitor.MarkListening();

        monitor.RecordDatagram(2025);

        var snapshot = monitor.GetSnapshot();
        Assert.Equal(ConnectionState.Connected, snapshot.State);
        Assert.Equal(1, snapshot.TotalDatagrams);
        Assert.Equal(2025, snapshot.DetectedPacketFormat);
        Assert.Equal(clock.UtcNow, snapshot.LastDatagramAt);
    }

    [Fact]
    public void StaleDatagram_BetweenThresholds_IsWaiting()
    {
        var (monitor, clock) = Create();
        monitor.MarkListening();
        monitor.RecordDatagram(2025);

        clock.Advance(TimeSpan.FromSeconds(3)); // 2s..6s → Waiting

        Assert.Equal(ConnectionState.Waiting, monitor.GetSnapshot().State);
    }

    [Fact]
    public void StaleDatagram_PastWaitingWindow_IsDisconnected()
    {
        var (monitor, clock) = Create();
        monitor.MarkListening();
        monitor.RecordDatagram(2025);

        clock.Advance(TimeSpan.FromSeconds(7)); // > 6s

        Assert.Equal(ConnectionState.Disconnected, monitor.GetSnapshot().State);
    }

    [Fact]
    public void ListenerFailure_ForcesDisconnected_EvenWithRecentDatagram()
    {
        var (monitor, _) = Create();
        monitor.MarkListening();
        monitor.RecordDatagram(2025);

        monitor.MarkListenerFailed("UDP 바인딩 실패: 포트 사용 중");

        var snapshot = monitor.GetSnapshot();
        Assert.Equal(ConnectionState.Disconnected, snapshot.State);
        Assert.Equal("UDP 바인딩 실패: 포트 사용 중", snapshot.ListenerError);
    }

    [Fact]
    public void MarkListening_ClearsPreviousListenerError()
    {
        var (monitor, _) = Create();
        monitor.MarkListenerFailed("boom");

        monitor.MarkListening();

        Assert.Null(monitor.GetSnapshot().ListenerError);
    }

    private sealed class MutableClock(DateTime start) : IClock
    {
        private DateTime _now = start;
        public DateTime UtcNow => _now;
        public void Advance(TimeSpan by) => _now += by;
    }
}
