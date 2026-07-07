using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

public class LapAnalyzerTests
{
    private const string S1 = "1001";
    private readonly LapAnalyzer _sut = new();

    private static LapFrame Lap(int lapNo, int sector, int s1 = 0, int s2 = 0, int last = 0, bool invalid = false, bool outin = false)
        => new(S1, lapNo, sector, s1, s2, last, invalid, outin);

    [Fact]
    public void SessionFrame_First_EmitsSessionStarted()
    {
        var events = _sut.Process(new SessionFrame(S1, TrackId: 7, SessionType.TimeTrial, PacketFormat: 2025));

        var started = Assert.IsType<SessionStarted>(Assert.Single(events));
        Assert.Equal(S1, started.SessionRef);
        Assert.Equal(7, started.TrackId);
        Assert.Equal(SessionType.TimeTrial, started.SessionType);
    }

    [Fact]
    public void FirstLap_EmitsLapStarted_WithoutLapFinished()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));

        var events = _sut.Process(Lap(lapNo: 1, sector: 0));

        var started = Assert.IsType<LapStarted>(Assert.Single(events));
        Assert.Equal(1, started.LapNumber);
    }

    [Fact]
    public void SectorChanges_EmitSectorCompleted_WithFinalizedTimes()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));
        _sut.Process(Lap(1, sector: 0));

        var s1Events = _sut.Process(Lap(1, sector: 1, s1: 27010));
        var s2Events = _sut.Process(Lap(1, sector: 2, s1: 27010, s2: 30110));

        var sc1 = Assert.IsType<SectorCompleted>(Assert.Single(s1Events));
        Assert.Equal(1, sc1.SectorNumber);
        Assert.Equal(27010, sc1.SectorTimeMs);

        var sc2 = Assert.IsType<SectorCompleted>(Assert.Single(s2Events));
        Assert.Equal(2, sc2.SectorNumber);
        Assert.Equal(30110, sc2.SectorTimeMs);
    }

    [Fact]
    public void LapRollover_EmitsLapFinished_WithThreeSectorsAndLapStarted()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));
        _sut.Process(Lap(1, 0));
        _sut.Process(Lap(1, 1, s1: 27010));
        _sut.Process(Lap(1, 2, s1: 27010, s2: 30110));

        var events = _sut.Process(Lap(2, 0, last: 83452));

        Assert.Equal(2, events.Count);
        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.Equal(1, finished.LapNumber);
        Assert.Equal(83452, finished.LapTimeMs);
        Assert.True(finished.IsValid);
        Assert.False(finished.IsOutOrInLap);
        Assert.Equal(7, finished.TrackId);
        Assert.Equal(SessionType.TimeTrial, finished.SessionType);
        Assert.Collection(finished.Sectors,
            s => { Assert.Equal(1, s.SectorNumber); Assert.Equal(27010, s.SectorTimeMs); },
            s => { Assert.Equal(2, s.SectorNumber); Assert.Equal(30110, s.SectorTimeMs); },
            s => { Assert.Equal(3, s.SectorNumber); Assert.Equal(26332, s.SectorTimeMs); }); // 83452-27010-30110

        var started = Assert.IsType<LapStarted>(events[1]);
        Assert.Equal(2, started.LapNumber);
    }

    [Fact]
    public void RepeatedIdenticalFrame_EmitsNothing_EdgeTriggered()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));
        _sut.Process(Lap(1, 0));
        _sut.Process(Lap(1, 1, s1: 27010)); // sector edge

        var repeat = _sut.Process(Lap(1, 1, s1: 27010)); // same sector again

        Assert.Empty(repeat);
    }

    [Fact]
    public void InvalidFlagDuringLap_MakesLapFinishedInvalid()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));
        _sut.Process(Lap(1, 0));
        _sut.Process(Lap(1, 1, s1: 27010, invalid: true)); // 랩 중 무효 발생
        _sut.Process(Lap(1, 2, s1: 27010, s2: 30110));

        var events = _sut.Process(Lap(2, 0, last: 83452));

        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.False(finished.IsValid);
    }

    [Fact]
    public void OutOrInLapFlag_PropagatesToLapFinished()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));
        _sut.Process(Lap(1, 0, outin: true));
        _sut.Process(Lap(1, 1, s1: 27010));
        _sut.Process(Lap(1, 2, s1: 27010, s2: 30110));

        var events = _sut.Process(Lap(2, 0, last: 83452));

        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.True(finished.IsOutOrInLap);
    }

    [Fact]
    public void SessionUidChange_EndsPreviousAndStartsNew()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));

        var events = _sut.Process(new SessionFrame("2002", 10, SessionType.Race, 2025));

        Assert.Equal(2, events.Count);
        Assert.IsType<SessionEnded>(events[0]);
        Assert.Equal(S1, events[0].SessionRef);
        var started = Assert.IsType<SessionStarted>(events[1]);
        Assert.Equal("2002", started.SessionRef);
    }

    [Fact]
    public void EndMarker_EmitsSessionEnded_ThenLapFramesIgnored()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));

        var ended = _sut.Process(new EventMarker(S1, SessionBoundary.End));
        Assert.IsType<SessionEnded>(Assert.Single(ended));

        var afterEnd = _sut.Process(Lap(1, 0));
        Assert.Empty(afterEnd);
    }

    [Fact]
    public void LapFrame_BeforeSession_IsIgnored()
    {
        var events = _sut.Process(Lap(1, 0));
        Assert.Empty(events);
    }
}
