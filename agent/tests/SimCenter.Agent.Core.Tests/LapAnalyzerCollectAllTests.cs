using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

/// <summary>"전부 수집"(D-49, docs/15 §8)의 분석기 배선: extra 채널 → <c>trace.extra</c>, 상세 묶음·이벤트 → <c>car.details</c>.</summary>
public class LapAnalyzerCollectAllTests
{
    private const string S1 = "1001";
    private readonly LapAnalyzer _sut = new();

    private static LapFrame At(int lapNo, float distanceM, int timeMs, int last = 0)
        => new(S1, lapNo, 0, 0, 0, last, false, false, LapDistanceM: distanceM, CurrentLapTimeMs: timeMs);

    private static ExtraChannelsFrame Extra(double clutch, string sessionRef = S1)
        => new(sessionRef, new Dictionary<string, double> { ["clutch"] = clutch });

    private void DriveAt(int lapNo, float distanceM, int timeMs)
    {
        _sut.Process(At(lapNo, distanceM, timeMs));
        _sut.Process(new CarTelemetryFrame(S1, 200, 1f, 0f, 0f, 7, 11_000));
    }

    private void StartSession() => _sut.Process(new SessionFrame(S1, 7, SessionType.Race, 2025));

    [Fact]
    public void ExtraChannels_ReachLapFinishedTrace()
    {
        StartSession();
        _sut.Process(Extra(clutch: 40));
        DriveAt(1, 0f, 0);
        _sut.Process(Extra(clutch: 0));
        DriveAt(1, 5f, 400);

        var finished = Assert.IsType<LapFinished>(_sut.Process(At(2, 0f, 0, last: 90_000))[0]);

        Assert.Equal(new[] { 40d, 0d }, finished.Trace!.Extra!["clutch"]);
    }

    [Fact]
    public void Details_OnlyDetailsReceived_ProducesCarWithDetailsOnly()
    {
        StartSession();
        _sut.Process(At(1, 0f, 0));
        _sut.Process(new CarDetailsFrame(S1, "setup", new Dictionary<string, object?> { ["frontWing"] = 11 }));

        var finished = Assert.IsType<LapFinished>(_sut.Process(At(2, 0f, 0, last: 90_000))[0]);

        var car = Assert.IsType<LapCarSnapshot>(finished.Car);
        Assert.Null(car.TeamId);
        Assert.Null(car.FuelEndKg);
        var setup = Assert.IsAssignableFrom<IReadOnlyDictionary<string, object?>>(car.Details!["setup"]);
        Assert.Equal(11, setup["frontWing"]);
    }

    [Fact]
    public void Events_AreStampedWithLapTime_AndBelongToTheirLap()
    {
        StartSession();
        _sut.Process(At(1, 0f, 0));
        _sut.Process(At(1, 300f, 15_250));
        _sut.Process(new GameEventFrame(S1, "PENA", new Dictionary<string, object?> { ["penaltyType"] = 5 }));
        var lap1 = Assert.IsType<LapFinished>(_sut.Process(At(2, 0f, 10, last: 90_000))[0]);
        _sut.Process(new GameEventFrame(S1, "OVTK", new Dictionary<string, object?>()));
        var lap2 = Assert.IsType<LapFinished>(_sut.Process(At(3, 0f, 0, last: 89_000))[0]);

        var lap1Event = Assert.Single((LapEventEntry[])lap1.Car!.Details![LapDetailsTracker.EventsKey]!);
        Assert.Equal("PENA", lap1Event.Code);
        Assert.Equal(15_250, lap1Event.LapTimeMs);
        var lap2Event = Assert.Single((LapEventEntry[])lap2.Car!.Details![LapDetailsTracker.EventsKey]!);
        Assert.Equal("OVTK", lap2Event.Code);
        Assert.Equal(10, lap2Event.LapTimeMs);   // 새 랩 첫 Lap Data의 시간
    }

    [Fact]
    public void PlayerSessionHistory_ForCompletedLap_IsAttached()
    {
        StartSession();
        _sut.Process(At(1, 0f, 0));
        var entry = new LapHistoryEntry(1, 0, 30_100, 31_200, 0, true, true, true, false);
        _sut.Process(new SessionHistoryFrame(S1, 0, IsPlayer: true, [entry]));

        var finished = Assert.IsType<LapFinished>(_sut.Process(At(2, 0f, 0, last: 90_000))[0]);

        Assert.Equal(entry, finished.Car!.Details![LapDetailsTracker.SessionHistoryKey]);
    }

    [Fact]
    public void NewSession_DropsDetails()
    {
        StartSession();
        _sut.Process(new CarDetailsFrame(S1, "setup", new Dictionary<string, object?> { ["frontWing"] = 11 }));
        _sut.Process(new SessionFrame("2002", 7, SessionType.Race, 2025));
        _sut.Process(new LapFrame("2002", 1, 0, 0, 0, 0, false, false));

        var finished = Assert.IsType<LapFinished>(_sut.Process(new LapFrame("2002", 2, 0, 0, 0, 90_000, false, false))[0]);

        Assert.Null(finished.Car);
    }

    [Fact]
    public void ExtraChannels_FromOtherSession_AreIgnored()
    {
        StartSession();
        _sut.Process(Extra(clutch: 40, sessionRef: "other"));
        DriveAt(1, 0f, 0);
        DriveAt(1, 5f, 400);

        var finished = Assert.IsType<LapFinished>(_sut.Process(At(2, 0f, 0, last: 90_000))[0]);

        Assert.Null(finished.Trace!.Extra);
    }
}
