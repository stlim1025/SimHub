using SimCenter.Application.Seasons.AiDifficulty;
using SimCenter.Application.Trends;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Trends;

public class TrendsCalculatorTests
{
    private const string GameCode = "F1_26";
    private const int MyTeam = 222;
    private static readonly DateTime Start = new(2026, 10, 5, 12, 0, 0, DateTimeKind.Utc); // 월요일
    private static readonly Guid Track = Id(500);
    private static readonly Dictionary<Guid, TrendTrackLabel> Tracks = new() { [Track] = new TrendTrackLabel("Monza", "IT") };

    private static Guid Id(int n) => new($"00000000-0000-0000-0000-{n:D12}");

    /// <summary>세션 하나의 결과 행: 나, 팀메이트(같은 팀), AI 한 명(다른 팀).</summary>
    private static IEnumerable<TrendResultRow> Session(
        int weekend, int session, SessionType type, SessionKind kind, int days,
        (int Position, int Grid, int Best, int Total, int Laps) me,
        (int Position, int Best, int Total, int Laps) mate,
        int otherBest = 90_000, bool includeMe = true)
    {
        var at = Start.AddDays(days).AddHours(session % 10);
        TrendResultRow Row(string key, int car, int team, bool player, int position, int grid, int best, int total, int laps)
            => new(
                new AiPaceRow(Id(weekend), Id(session), $"s{session}", type, kind, at, 103, key, key.ToUpperInvariant(), car, team,
                    player, !player, position, grid, ResultStatus.Finished, best, total, laps),
                GameCode, GameMode.DriverCareer, Track, false, weekend != 0);

        if (includeMe)
        {
            yield return Row("me", 0, MyTeam, true, me.Position, me.Grid, me.Best, me.Total, me.Laps);
        }

        yield return Row("mate", 1, MyTeam, false, mate.Position, 0, mate.Best, mate.Total, mate.Laps);
        yield return Row("other", 2, 221, false, 3, 0, otherBest, 0, 0);
    }

    private static TrendLapRow Lap(int session, int number, int ms, bool valid = true, int days = 0, SessionType type = SessionType.Race)
        => new(Track, $"s{session}", type, number, ms, valid, Start.AddDays(days).AddMinutes(number));

    [Fact]
    public void Race_HasPositionsTeammatePaceFieldPaceAndConsistency()
    {
        var rows = Session(1, 10, SessionType.Race, SessionKind.Race, 0, (1, 3, 89_000, 900_000, 10), (6, 90_000, 910_000, 10), otherBest: 91_000);
        // 1랩(스탠딩 스타트)과 피트 랩(107% 초과)은 빼고 8랩: 90.0~90.7초 → 표준편차 약 0.229초.
        var laps = new[] { Lap(10, 1, 95_000), Lap(10, 5, 110_000) }
            .Concat(Enumerable.Range(0, 8).Select(i => Lap(10, i + 2 + (i >= 3 ? 1 : 0), 90_000 + i * 100)));

        var race = Assert.Single(TrendsCalculator.Calculate(rows.ToList(), laps.ToList(), Tracks).Races);

        Assert.Equal("Monza", race.TrackName);
        Assert.Equal((3, 1), (race.Grid, race.Position));
        Assert.Equal(-1000, race.TeammatePaceGapPerLapMs);
        Assert.Equal(-1.66, race.FieldPaceGapPercent);   // 89.0 vs AI 중앙값 90.5 → -1.6575%
        Assert.Equal(8, race.CleanLaps);
        Assert.Equal(229, race.ConsistencyMs);
        Assert.False(race.IsSprint);
        Assert.Equal("DriverCareer", race.GameMode);
    }

    [Fact]
    public void SprintWeekend_FlagsTheSprint_AndSessionsWithoutMeAreLeftOut()
    {
        var rows = Session(1, 10, SessionType.Race, SessionKind.Race, 0, (2, 1, 0, 300_000, 3), (8, 0, 303_000, 3))
            .Concat(Session(1, 11, SessionType.Race, SessionKind.Race2, 1, (1, 2, 0, 900_000, 10), (6, 0, 905_000, 10)))
            .Concat(Session(2, 20, SessionType.Race, SessionKind.Race, 7, default, (1, 0, 0, 0), includeMe: false));

        var races = TrendsCalculator.Calculate(rows.ToList(), [], Tracks).Races;

        Assert.Equal([true, false], races.Select(r => r.IsSprint));
        Assert.All(races, r => Assert.Null(r.ConsistencyMs));
    }

    [Fact]
    public void Qualifying_IsOnePointPerWeekend_FromTheLastPart()
    {
        var rows = Session(1, 10, SessionType.Qualifying, SessionKind.Qualifying2, 0, (5, 0, 90_300, 0, 0), (9, 90_000, 0, 0))
            .Concat(Session(1, 11, SessionType.Qualifying, SessionKind.Qualifying3, 0, (2, 0, 89_800, 0, 0), (4, 90_100, 0, 0)));

        var quali = Assert.Single(TrendsCalculator.Calculate(rows.ToList(), [], Tracks).Qualifying);

        Assert.Equal(2, quali.Position);
        Assert.Equal(-300, quali.TeammateGapMs);
        Assert.Equal(103, quali.AiDifficulty);
    }

    [Fact]
    public void WeeklyLaps_StartOnMonday_AndFillEmptyWeeksWithZero()
    {
        var laps = new[] { Lap(1, 1, 90_000, days: 0), Lap(1, 2, 90_000, days: 6), Lap(2, 1, 90_000, days: 15) };

        var weeks = TrendsCalculator.Calculate([], laps, Tracks).WeeklyLaps;

        Assert.Equal(
            [(new DateOnly(2026, 10, 5), 2), (new DateOnly(2026, 10, 12), 0), (new DateOnly(2026, 10, 19), 1)],
            weeks.Select(w => (w.WeekStart, w.Laps)));
    }

    [Fact]
    public void TrackProgression_IsSessionBestAndRunningBest_FromValidLapsOnly()
    {
        var laps = new[]
        {
            Lap(1, 1, 91_000, days: 0, type: SessionType.Practice),
            Lap(1, 2, 90_500, days: 0, type: SessionType.Practice),
            Lap(2, 1, 89_000, valid: false, days: 1, type: SessionType.TimeTrial),   // 무효 — 최고 랩에 넣지 않는다
            Lap(2, 2, 90_800, days: 1, type: SessionType.TimeTrial),
            Lap(3, 1, 90_100, days: 2, type: SessionType.Qualifying),
        };

        var track = Assert.Single(TrendsCalculator.Calculate([], laps, Tracks).Tracks);

        Assert.Equal(5, track.LapCount);
        Assert.Equal(
            [(90_500, 90_500, "Practice"), (90_800, 90_500, "TimeTrial"), (90_100, 90_100, "Qualifying")],
            track.Points.Select(p => (p.SessionBestMs, p.BestSoFarMs, p.SessionType)));
    }
}
