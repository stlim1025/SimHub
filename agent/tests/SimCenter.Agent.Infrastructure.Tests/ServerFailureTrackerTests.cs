using SimCenter.Agent.Infrastructure.Upload;

namespace SimCenter.Agent.Infrastructure.Tests;

public class ServerFailureTrackerTests
{
    private const int Threshold = 5;

    private static readonly TimeSpan BaseDelay = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan MaxDelay = TimeSpan.FromMinutes(5);
    private static readonly DateTime Now = new(2026, 10, 17, 9, 0, 0, DateTimeKind.Utc);

    private static ServerFailureTracker NewTracker() => new(Threshold, BaseDelay, MaxDelay);

    private static ServerFailure FailTimes(ServerFailureTracker tracker, Guid eventId, int times)
    {
        var last = default(ServerFailure);
        for (var i = 0; i < times; i++)
        {
            last = tracker.RecordFailure(eventId, Now);
        }

        return last;
    }

    [Fact]
    public void BelowThreshold_IsNotDeferred()
    {
        var tracker = NewTracker();
        var id = Guid.NewGuid();

        var failure = FailTimes(tracker, id, Threshold - 1);

        Assert.Equal(Threshold - 1, failure.Failures);
        Assert.Null(failure.RetryAt);
        Assert.False(tracker.IsDeferred(id, Now));
        Assert.Equal(0, tracker.DeferredCount);
        Assert.Equal(1, tracker.TrackedCount);
    }

    [Fact]
    public void AtThreshold_IsDeferredByBaseDelay()
    {
        var tracker = NewTracker();
        var id = Guid.NewGuid();

        var failure = FailTimes(tracker, id, Threshold);

        Assert.Equal(Now + BaseDelay, failure.RetryAt);
        Assert.True(tracker.IsDeferred(id, Now));
        Assert.True(tracker.IsDeferred(id, Now + BaseDelay - TimeSpan.FromTicks(1)));
        Assert.False(tracker.IsDeferred(id, Now + BaseDelay)); // 시각이 되면 다시 보낼 수 있다.
        Assert.Equal(1, tracker.DeferredCount);
    }

    [Theory]
    [InlineData(Threshold + 1, 60)]
    [InlineData(Threshold + 2, 120)]
    [InlineData(Threshold + 3, 240)]
    [InlineData(Threshold + 4, 300)] // 480초 → 최대 5분
    [InlineData(Threshold + 100, 300)] // 지수가 커져도 넘치지 않는다.
    public void FurtherFailures_DoubleTheDelay_UpToMax(int failures, int expectedSeconds)
    {
        var tracker = NewTracker();
        var id = Guid.NewGuid();

        var failure = FailTimes(tracker, id, failures);

        Assert.Equal(Now + TimeSpan.FromSeconds(expectedSeconds), failure.RetryAt);
    }

    [Fact]
    public void ClockMovedBackwards_DoesNotStretchTheDelay()
    {
        var tracker = NewTracker();
        var id = Guid.NewGuid();
        FailTimes(tracker, id, Threshold);

        // 벽시계가 1시간 되감기면 남은 시간이 최대 지연보다 길어진다 — 시계가 후퇴한 것으로 보고 바로 다시 보낸다.
        Assert.False(tracker.IsDeferred(id, Now - TimeSpan.FromHours(1)));
    }

    [Fact]
    public void Forget_RemovesRecord()
    {
        var tracker = NewTracker();
        var id = Guid.NewGuid();
        FailTimes(tracker, id, Threshold);

        tracker.Forget(id);

        Assert.False(tracker.IsDeferred(id, Now));
        Assert.Equal(0, tracker.DeferredCount);
        Assert.Equal(0, tracker.TrackedCount);
        Assert.Equal(1, tracker.RecordFailure(id, Now).Failures); // 처음부터 다시 센다.
    }

    [Fact]
    public void Clear_RemovesAllRecords()
    {
        var tracker = NewTracker();
        FailTimes(tracker, Guid.NewGuid(), Threshold);
        FailTimes(tracker, Guid.NewGuid(), 1);

        tracker.Clear();

        Assert.Equal(0, tracker.DeferredCount);
        Assert.Equal(0, tracker.TrackedCount);
    }

    [Fact]
    public void UnknownItem_IsNotDeferred()
    {
        Assert.False(NewTracker().IsDeferred(Guid.NewGuid(), Now));
    }

    [Fact]
    public void Items_AreTrackedIndependently()
    {
        var tracker = NewTracker();
        var poison = Guid.NewGuid();
        var other = Guid.NewGuid();

        FailTimes(tracker, poison, Threshold);
        FailTimes(tracker, other, 1);

        Assert.True(tracker.IsDeferred(poison, Now));
        Assert.False(tracker.IsDeferred(other, Now));
        Assert.Equal(1, tracker.DeferredCount);
        Assert.Equal(2, tracker.TrackedCount);
    }

    [Fact]
    public void InvalidSettings_Throw()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new ServerFailureTracker(0, BaseDelay, MaxDelay));
        Assert.Throws<ArgumentOutOfRangeException>(() => new ServerFailureTracker(Threshold, TimeSpan.Zero, MaxDelay));
        Assert.Throws<ArgumentOutOfRangeException>(() => new ServerFailureTracker(Threshold, MaxDelay, BaseDelay));
    }
}
