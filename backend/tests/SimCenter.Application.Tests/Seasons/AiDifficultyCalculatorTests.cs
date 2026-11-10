using SimCenter.Application.Seasons.AiDifficulty;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Seasons;

public class AiDifficultyCalculatorTests
{
    private const string GameCode = "F1_26";
    private const int MyTeam = 222;          // Red Bull(v1.26 그리드 ID)
    private const int OtherTeam = 221;       // Ferrari
    private static readonly DateTime Start = new(2026, 10, 1, 12, 0, 0, DateTimeKind.Utc);

    // ---- 도우미 ----

    private static Guid Id(int n) => new($"00000000-0000-0000-0000-{n:D12}");

    private static WeekendRow Weekend(int n, int trackId = 0)
        => new(Id(1000 + n), Id(1), $"Track {n}", Start.AddDays(n), TrackId: Id(2000 + (trackId == 0 ? n : trackId)));

    /// <summary>세션 하나: 나(팀 <see cref="MyTeam"/>), 팀메이트(같은 팀), AI 한 명(다른 팀).</summary>
    private static IEnumerable<AiPaceRow> Session(
        int weekend, int session, SessionType type, SessionKind kind, int ai,
        (int Position, int Best, int Total, int Laps, ResultStatus Status) me,
        (int Position, int Best, int Total, int Laps, ResultStatus Status) mate,
        int otherBest = 90_000, int mateTeam = MyTeam, int hours = 0)
    {
        var at = Start.AddDays(weekend).AddHours(session + hours);
        AiPaceRow Row(string key, int car, int? team, bool player, (int Position, int Best, int Total, int Laps, ResultStatus Status) v)
            => new(Id(1000 + weekend), Id(session), $"s{session}", type, kind, at, ai, key, key.ToUpperInvariant(), car, team,
                player, !player, v.Position, v.Position, v.Status, v.Best, v.Total, v.Laps);

        yield return Row("me", 0, MyTeam, true, me);
        yield return Row("mate", 1, mateTeam, false, mate);
        yield return Row("other", 2, OtherTeam, false, (3, otherBest, 0, 0, ResultStatus.Finished));
    }

    private static (int, int, int, int, ResultStatus) Q(int position, int best) => (position, best, 0, 0, ResultStatus.Finished);

    private static (int, int, int, int, ResultStatus) R(int position, int total, int laps = 10, ResultStatus status = ResultStatus.Finished)
        => (position, 0, total, laps, status);

    private static SeasonAiDifficultyDto Calculate(
        IEnumerable<WeekendRow> weekends,
        IEnumerable<AiPaceRow> rows,
        IEnumerable<SessionLapWeatherRow>? weather = null,
        IEnumerable<TimeTrialLapRow>? timeTrial = null)
    {
        var list = weekends.ToList();
        return AiDifficultyCalculator.Calculate(
            GameCode,
            list,
            RoundNumbering.Assign(list),
            rows.ToList(),
            (weather ?? []).ToList(),
            (timeTrial ?? []).ToList());
    }

    /// <summary>주말 n: 예선(나 vs 팀메이트 최고 랩) + 레이스(10랩 총 시간).</summary>
    private static IEnumerable<AiPaceRow> RaceWeekend(int n, int ai, int myQuali, int mateQuali, int myTotal, int mateTotal)
        => Session(n, n * 10, SessionType.Qualifying, SessionKind.Qualifying3, ai, Q(2, myQuali), Q(1, mateQuali))
            .Concat(Session(n, n * 10 + 1, SessionType.Race, SessionKind.Race, ai, R(1, myTotal), R(5, mateTotal)));

    // ---- 판정 ----

    [Fact]
    public void FasterThanTeammateInRaces_SaysRaise_KeepsQualifyingThatIsEven()
    {
        // 예선: 팀메이트와 ±0.1% 안 → 적정. 레이스: 랩당 0.9초(1%) 빠름 → 올리기, 1% 이상이라 3단계 이상.
        var rows = Enumerable.Range(1, 4).SelectMany(n =>
            RaceWeekend(n, 103, myQuali: 90_000 + (n % 2 == 0 ? 50 : -50), mateQuali: 90_000, myTotal: 891_000, mateTotal: 900_000));

        var result = Calculate(Enumerable.Range(1, 4).Select(n => Weekend(n)), rows);

        Assert.Equal(103, result.CurrentAiDifficulty);
        Assert.Equal(AiDifficultyCalculator.VerdictKeep, result.Qualifying.Verdict);
        Assert.Equal(4, result.Qualifying.Samples);
        Assert.Equal(AiDifficultyCalculator.VerdictRaise, result.Race.Verdict);
        Assert.Equal(AiDifficultyCalculator.StepsLarge, result.Race.Steps);
        Assert.Equal(-900, result.Race.MedianGapMs);
        Assert.Equal(-1.0, result.Race.MedianGapPercent);
        Assert.Equal(4, result.Race.AheadOfTeammate);
    }

    [Fact]
    public void SlowerThanTeammateInQualifying_SaysLower_SmallStep()
    {
        // 예선 0.5% 느림(0.3~1% 사이) → 낮추기 1~2단계.
        var rows = Enumerable.Range(1, 3).SelectMany(n =>
            RaceWeekend(n, 103, myQuali: 90_450, mateQuali: 90_000, myTotal: 900_000, mateTotal: 900_000));

        var result = Calculate(Enumerable.Range(1, 3).Select(n => Weekend(n)), rows);

        Assert.Equal(AiDifficultyCalculator.VerdictLower, result.Qualifying.Verdict);
        Assert.Equal(AiDifficultyCalculator.StepsSmall, result.Qualifying.Steps);
        Assert.Equal(0.5, result.Qualifying.MedianGapPercent);
        Assert.Equal(0, result.Qualifying.AheadOfTeammate);
    }

    [Fact]
    public void FewerThanMinSamples_IsNotEnoughData_ButShowsTheGap()
    {
        var rows = RaceWeekend(1, 103, 89_000, 90_000, 891_000, 900_000);

        var result = Calculate([Weekend(1)], rows);

        Assert.Equal(AiDifficultyCalculator.VerdictNotEnoughData, result.Race.Verdict);
        Assert.Null(result.Race.Steps);
        Assert.Equal(1, result.Race.Samples);
        Assert.Equal(-900, result.Race.MedianGapMs);
    }

    [Fact]
    public void Verdict_UsesOnlySessionsAtTheCurrentAiLevel()
    {
        // 주말 1~3은 AI 95(많이 빠름), 주말 4는 AI 105(가장 최근) — 판정은 AI 105 한 판뿐이라 데이터 부족.
        var rows = Enumerable.Range(1, 3)
            .SelectMany(n => RaceWeekend(n, 95, 88_000, 90_000, 880_000, 900_000))
            .Concat(RaceWeekend(4, 105, 90_000, 90_000, 900_000, 900_000));

        var result = Calculate(Enumerable.Range(1, 4).Select(n => Weekend(n)), rows);

        Assert.Equal(105, result.CurrentAiDifficulty);
        Assert.Equal(1, result.Race.Samples);
        Assert.Equal(AiDifficultyCalculator.VerdictNotEnoughData, result.Race.Verdict);
    }

    // ---- 팀메이트 · 비교 조건 ----

    [Fact]
    public void Teammate_IsFoundAcrossRenumberedTeamIds()
    {
        // 게임이 팀 ID를 222(v1.26 그리드)에서 478(2026 시즌팩)로 바꿔 보내도 같은 Red Bull 팀메이트다.
        var rows = Session(1, 10, SessionType.Qualifying, SessionKind.Qualifying3, 103, Q(1, 89_000), Q(2, 90_000), mateTeam: 478);

        var weekend = Assert.Single(Calculate([Weekend(1)], rows).Weekends);

        Assert.Equal("MATE", weekend.TeammateName);
        Assert.Equal(-1000, weekend.QualiGapMs);
        Assert.Equal(2, weekend.TeammateQualiPosition);
    }

    [Fact]
    public void QualifyingGap_UsesTheLastPartBothSetATimeIn_PositionsFromTheLastPartEachRan()
    {
        // Q2: 둘 다 기록, Q3: 나만 기록(팀메이트 탈락 — Q3 행이 없음).
        var q2 = Session(1, 10, SessionType.Qualifying, SessionKind.Qualifying2, 103, Q(4, 90_300), Q(12, 90_000));
        var q3 = Session(1, 11, SessionType.Qualifying, SessionKind.Qualifying3, 103, Q(3, 89_900), Q(0, 0))
            .Where(r => r.DriverKey != "mate");

        var weekend = Assert.Single(Calculate([Weekend(1)], q2.Concat(q3)).Weekends);

        Assert.Equal(300, weekend.QualiGapMs);
        Assert.Equal(0.33, weekend.QualiGapPercent);
        Assert.Equal(3, weekend.MyQualiPosition);
        Assert.Equal(12, weekend.TeammateQualiPosition);
    }

    [Fact]
    public void RacePace_NeedsBothFinishedOnTheSameLap()
    {
        var rows = Session(1, 10, SessionType.Race, SessionKind.Race, 103, R(1, 900_000), R(9, 950_000, laps: 9))   // 팀메이트 한 바퀴 뒤짐
            .Concat(Session(2, 20, SessionType.Race, SessionKind.Race, 103, R(20, 0, status: ResultStatus.DidNotFinish), R(5, 900_000)));

        var result = Calculate([Weekend(1), Weekend(2)], rows);

        Assert.All(result.Weekends.SelectMany(w => w.Races), r => Assert.Null(r.PaceGapPerLapMs));
        Assert.Equal("DidNotFinish", result.Weekends[1].Races[0].MyResultStatus);
        Assert.Equal(0, result.Race.Samples);
    }

    [Fact]
    public void SprintWeekend_MarksTheFirstRaceAsSprint_AndCarLevelUsesTheMainRace()
    {
        var rows = Session(1, 10, SessionType.Race, SessionKind.Race, 103, R(2, 300_000, 3), R(8, 303_000, 3))
            .Concat(Session(1, 11, SessionType.Race, SessionKind.Race2, 103, R(1, 900_000), R(6, 905_000)));

        var result = Calculate([Weekend(1)], rows);

        var races = Assert.Single(result.Weekends).Races;
        Assert.Equal([true, false], races.Select(r => r.IsSprint));
        Assert.Equal(6.0, result.Car.TeammateRacePosition);
        Assert.Equal(1.0, result.Car.MyRacePosition);
    }

    // ---- 타임트라이얼 ----

    [Fact]
    public void TimeTrial_ComparesDryQualifyingOnly_AgainstMyDryTimeTrialBest()
    {
        var rows = Session(1, 10, SessionType.Qualifying, SessionKind.Qualifying3, 103, Q(2, 90_500), Q(3, 90_800), otherBest: 90_000)
            .Concat(Session(2, 20, SessionType.Qualifying, SessionKind.Qualifying3, 103, Q(2, 99_000), Q(3, 99_500), otherBest: 98_000));
        var weather = new[]
        {
            new SessionLapWeatherRow("s10", Weather.LightCloud),
            new SessionLapWeatherRow("s10", Weather.Overcast),
            new SessionLapWeatherRow("s20", Weather.LightRain),   // 주말 2 예선은 젖은 노면 — 비교하지 않는다
        };
        var timeTrial = new[]
        {
            new TimeTrialLapRow(Id(2001), 89_100, Weather.Clear),
            new TimeTrialLapRow(Id(2001), 88_000, Weather.HeavyRain),   // 젖은 TT 랩은 쓰지 않는다
            new TimeTrialLapRow(Id(2001), 89_500, null),
            new TimeTrialLapRow(Id(2002), 95_000, Weather.Clear),
        };

        var result = Calculate([Weekend(1), Weekend(2)], rows, weather, timeTrial);

        var row = Assert.Single(result.TimeTrial);
        Assert.Equal(Id(1001), row.WeekendId);
        Assert.Equal(89_100, row.TimeTrialBestMs);
        Assert.Equal(90_000, row.AiFastestQualiMs);
        Assert.Equal(103, row.AiDifficulty);
        Assert.Equal(-1.0, row.GapPercent);
        Assert.Equal("Overcast", result.Weekends[0].Weather);
        Assert.Equal("LightRain", result.Weekends[1].Weather);
    }

    [Fact]
    public void WeekendWithoutRecordedSessions_IsLeftOut()
    {
        var rows = RaceWeekend(2, 103, 90_000, 90_000, 900_000, 900_000);

        var result = Calculate([Weekend(1), Weekend(2)], rows);

        Assert.Equal([Id(1002)], result.Weekends.Select(w => w.WeekendId));
    }
}
