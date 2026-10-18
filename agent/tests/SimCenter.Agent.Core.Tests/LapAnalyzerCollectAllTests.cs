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
