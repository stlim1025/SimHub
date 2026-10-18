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
        _sut.Process(Lap(1, 1, s1: 27010, invalid: true)); // 랩 중 무효 발생 — 게임은 랩 끝까지 무효를 유지한다
        _sut.Process(Lap(1, 2, s1: 27010, s2: 30110, invalid: true));

        var events = _sut.Process(Lap(2, 0, last: 83452));

        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.False(finished.IsValid);
    }

    [Fact]
    public void FlashbackClearingInvalidFlag_MakesLapFinishedValid()
    {
        // 실제 F1 25 TT: 트랙 이탈로 무효가 켜졌다가 플래시백으로 되감으면 게임이 무효를 푼다(랩 끝 currentLapInvalid=false,
        // Session History lapValid=true). 랩 판정은 랩이 끝나는 순간의 게임 값을 따른다.
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));
        _sut.Process(Lap(1, 0));
        _sut.Process(Lap(1, 1, s1: 27010, invalid: true));
        _sut.Process(Lap(1, 1, s1: 27010)); // 플래시백
        _sut.Process(Lap(1, 2, s1: 27010, s2: 30110));

        var events = _sut.Process(Lap(2, 0, last: 83452));

        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.True(finished.IsValid);
    }

    [Fact]
    public void InvalidFlagOnNextLapsFirstFrame_DoesNotInvalidateCompletedLap()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));
        _sut.Process(Lap(1, 0));
        _sut.Process(Lap(1, 2, s1: 27010, s2: 30110));

        var events = _sut.Process(Lap(2, 0, last: 83452, invalid: true));

        Assert.True(Assert.IsType<LapFinished>(events[0]).IsValid);
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

    [Fact]
    public void LapFinished_CarriesSessionModeAndLinks()
    {
        _sut.Process(CareerSession(GameMode.DriverCareer, season: 11, weekend: 22, session: 33));
        var finished = FinishFirstLap();

        Assert.Equal(GameMode.DriverCareer, finished.GameMode);
        Assert.Equal(11u, finished.SeasonLinkId);
        Assert.Equal(22u, finished.WeekendLinkId);
        Assert.Equal(33u, finished.SessionLinkId);
    }

    [Fact]
    public void LapFinished_WithPlainSessionFrame_DefaultsToOtherAndZeroLinks()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));
        var finished = FinishFirstLap();

        Assert.Equal(GameMode.Other, finished.GameMode);
        Assert.Equal(0u, finished.SeasonLinkId);
        Assert.Equal(0u, finished.WeekendLinkId);
        Assert.Equal(0u, finished.SessionLinkId);
    }

    [Fact]
    public void RepeatedSessionFrame_UpdatesModeAndLinksForLaterLaps()
    {
        _sut.Process(CareerSession(GameMode.Other, season: 0, weekend: 0, session: 0));
        _sut.Process(CareerSession(GameMode.GrandPrix, season: 5, weekend: 6, session: 7)); // 같은 세션의 뒤 프레임

        var finished = FinishFirstLap();

        Assert.Equal(GameMode.GrandPrix, finished.GameMode);
        Assert.Equal(5u, finished.SeasonLinkId);
        Assert.Equal(6u, finished.WeekendLinkId);
        Assert.Equal(7u, finished.SessionLinkId);
    }

    [Fact]
    public void NewSession_ReplacesModeAndLinks()
    {
        _sut.Process(CareerSession(GameMode.DriverCareer, season: 11, weekend: 22, session: 33));
        _sut.Process(new SessionFrame("2002", 10, SessionType.TimeTrial, 2025)); // 맥락 없는 새 세션

        _sut.Process(new LapFrame("2002", 1, 0, 0, 0, 0, false, false));
        var events = _sut.Process(new LapFrame("2002", 2, 0, 0, 0, 83452, false, false));

        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.Equal(GameMode.Other, finished.GameMode);
        Assert.Equal(0u, finished.SeasonLinkId);
        Assert.Equal(0u, finished.WeekendLinkId);
        Assert.Equal(0u, finished.SessionLinkId);
    }

    // ---- D-44 스냅샷 · D-45 트레이스 ----

    private static SessionFrame ConditionsSession(Weather weather = Weather.Clear, int air = 21, int track = 31, int? rain = 4)
        => new(S1, 7, SessionType.TimeTrial, 2025, Weather: weather, AirTemperatureC: air, TrackTemperatureC: track, TrackLengthM: 5891, RainForecastPercent: rain);

    private static LapFrame At(int lapNo, float distanceM, int timeMs, int last = 0)
        => new(S1, lapNo, 0, 0, 0, last, false, false, LapDistanceM: distanceM, CurrentLapTimeMs: timeMs);

    private static CarTelemetryFrame Telemetry(int speed, string sessionRef = S1)
        => new(sessionRef, speed, 1f, 0f, 0f, 7, 11_000);

    private static CarStatusFrame Status(float fuel, float ers = 2_000_000f, string sessionRef = S1)
        => new(sessionRef, fuel, 10f, ers, 0f, 0f, 0f, 18, 16, 2);

    private static CarDamageFrame Damage(float wear) => new(
        S1, new WheelSet<float>(wear, wear, wear, wear), new WheelSet<int>(0, 0, 0, 0), new WheelSet<int>(0, 0, 0, 0),
        0, 0, 0, 0, 0, 0, 0, 0);

    /// <summary>이 거리·시간에서 Lap Data를 받은 뒤 Car Telemetry 1개를 받는다(거리 기준 표본).</summary>
    private IReadOnlyList<TelemetryEvent> DriveAt(int lapNo, float distanceM, int timeMs, int speed, int last = 0)
    {
        var events = _sut.Process(At(lapNo, distanceM, timeMs, last));
        _sut.Process(Telemetry(speed));
        return events;
    }

    [Fact]
    public void LapFinished_CarriesCarSnapshotConditionsAndTrace()
    {
        _sut.Process(ConditionsSession());
        _sut.Process(new ParticipantsFrame(S1, [new ParticipantInfo(0, "LIM", null, 1, 26, false)], PlayerCarIndex: 0));
        DriveAt(1, 0f, 0, speed: 100);
        _sut.Process(Status(fuel: 24.4f));   // 랩 시작 뒤 첫 값 = 시작 값
        _sut.Process(Damage(wear: 27f));
        DriveAt(1, 5f, 500, speed: 150);
        _sut.Process(Status(fuel: 22.7f));   // 랩이 끝나기 전 마지막 값 = 끝 값
        _sut.Process(Damage(wear: 31f));
        DriveAt(1, 10f, 900, speed: 200);

        var events = _sut.Process(At(2, 0f, 0, last: 83_452));

        var finished = Assert.IsType<LapFinished>(events[0]);
        var car = Assert.IsType<LapCarSnapshot>(finished.Car);
        Assert.Equal(1, car.TeamId);
        Assert.Equal(24.4f, car.FuelStartKg);
        Assert.Equal(22.7f, car.FuelEndKg);
        Assert.Equal(27f, car.TyreWearStart!.FrontLeft);
        Assert.Equal(31f, car.TyreWearEnd!.FrontLeft);
        Assert.Equal(new LapConditions(Weather.Clear, 21, 31, 4), finished.Conditions);
        var trace = Assert.IsType<LapTrace>(finished.Trace);
        Assert.Equal(new[] { 100, 150, 200 }, trace.SpeedKph);
        Assert.Equal(new[] { 0, 500, 900 }, trace.TimeMs);
    }

    [Fact]
    public void ValuesAfterLapTransition_BelongToNextLap()
    {
        _sut.Process(ConditionsSession());
        DriveAt(1, 0f, 0, speed: 100);
        _sut.Process(Status(fuel: 30f));
        DriveAt(1, 5f, 500, speed: 110);
        _sut.Process(At(2, 0f, 0, last: 83_000));

        _sut.Process(Telemetry(speed: 120));
        _sut.Process(Status(fuel: 29.9f));   // 새 랩의 시작 값
        DriveAt(2, 5f, 450, speed: 130);
        _sut.Process(Status(fuel: 28f));
        var events = _sut.Process(At(3, 0f, 0, last: 82_000));

        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.Equal(2, finished.LapNumber);
        Assert.Equal(29.9f, finished.Car!.FuelStartKg);
        Assert.Equal(28f, finished.Car.FuelEndKg);
        Assert.Equal(new[] { 120, 130 }, finished.Trace!.SpeedKph);
    }

    [Fact]
    public void LapFinished_WithoutCarFrames_HasNoCarConditionsOrTrace()
    {
        _sut.Process(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));

        var finished = FinishFirstLap();

        Assert.Null(finished.Car);
        Assert.Null(finished.Conditions);
        Assert.Null(finished.Trace);
    }

    [Fact]
    public void FirstLapJoinedMidway_HasNoStartValues()
    {
        _sut.Process(ConditionsSession());
        _sut.Process(At(3, 2_500f, 40_000));   // Agent가 랩 중간에 시작
        _sut.Process(Status(fuel: 20f));
        _sut.Process(Damage(wear: 40f));

        var events = _sut.Process(At(4, 0f, 0, last: 84_000));

        var car = Assert.IsType<LapFinished>(events[0]).Car!;
        Assert.Null(car.FuelStartKg);
        Assert.Null(car.TyreWearStart);
        Assert.Equal(20f, car.FuelEndKg);
    }

    [Fact]
    public void FirstLapSeenAtItsStart_CapturesStartValues()
    {
        _sut.Process(ConditionsSession());
        _sut.Process(At(1, 0f, 0));
        _sut.Process(Status(fuel: 100f));

        var events = _sut.Process(At(2, 0f, 0, last: 95_000));

        Assert.Equal(100f, Assert.IsType<LapFinished>(events[0]).Car!.FuelStartKg);
    }

    [Fact]
    public void CarFrames_FromOtherSession_AreIgnored()
    {
        _sut.Process(ConditionsSession());
        DriveAt(1, 0f, 0, speed: 100);
        DriveAt(1, 5f, 500, speed: 110);
        _sut.Process(Status(fuel: 50f, sessionRef: "stale"));
        _sut.Process(Telemetry(speed: 255, sessionRef: "stale"));

        var events = _sut.Process(At(2, 0f, 0, last: 83_000));

        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.Null(finished.Car);
        Assert.Equal(new[] { 100, 110 }, finished.Trace!.SpeedKph);
    }

    [Fact]
    public void FlashbackToPreviousLapNumber_DoesNotPolluteCurrentTrace()
    {
        _sut.Process(ConditionsSession());
        DriveAt(1, 0f, 0, speed: 100);
        DriveAt(1, 5f, 500, speed: 110);
        _sut.Process(At(2, 0f, 0, last: 83_000));
        _sut.Process(Telemetry(speed: 120));
        DriveAt(1, 5_800f, 82_000, speed: 255);   // 플래시백으로 이전 랩 끝으로 되돌아감 — 무시
        DriveAt(2, 0f, 0, speed: 121);
        DriveAt(2, 5f, 450, speed: 131);

        var events = _sut.Process(At(3, 0f, 0, last: 82_000));

        Assert.Equal(new[] { 121, 131 }, Assert.IsType<LapFinished>(events[0]).Trace!.SpeedKph);
    }

    [Fact]
    public void FlashbackAcrossLine_ThenRecrossing_DoesNotRepeatLapFinished()
    {
        _sut.Process(ConditionsSession());
        DriveAt(1, 0f, 0, speed: 100);
        _sut.Process(At(2, 0f, 0, last: 83_000));
        _sut.Process(At(1, 5_800f, 82_000));   // 플래시백으로 앞 랩 끝으로

        var events = _sut.Process(At(2, 0f, 0, last: 83_100));   // 다시 출발선을 건넘

        Assert.DoesNotContain(events, e => e is LapFinished);
    }

    [Fact]
    public void NewSession_DropsCarStateAndTrace()
    {
        _sut.Process(ConditionsSession());
        DriveAt(1, 0f, 0, speed: 100);
        _sut.Process(Status(fuel: 50f));
        _sut.Process(new SessionFrame("2002", 7, SessionType.TimeTrial, 2025));

        _sut.Process(new LapFrame("2002", 1, 0, 0, 0, 0, false, false));
        var events = _sut.Process(new LapFrame("2002", 2, 0, 0, 0, 83_452, false, false));

        var finished = Assert.IsType<LapFinished>(events[0]);
        Assert.Null(finished.Car);
        Assert.Null(finished.Conditions);
        Assert.Null(finished.Trace);
    }

    private static SessionFrame CareerSession(GameMode mode, uint season, uint weekend, uint session)
        => new(S1, 7, SessionType.Race, 2025, SessionKind.Race, mode, season, weekend, session);

    private LapFinished FinishFirstLap()
    {
        _sut.Process(Lap(1, 0));
        _sut.Process(Lap(1, 1, s1: 27010));
        _sut.Process(Lap(1, 2, s1: 27010, s2: 30110));
        var events = _sut.Process(Lap(2, 0, last: 83452));
        return Assert.IsType<LapFinished>(events[0]);
    }
}
