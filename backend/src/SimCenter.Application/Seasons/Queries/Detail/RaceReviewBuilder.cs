using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 레이스 총평 재료(순수 계산). 세션 기록(<c>lapHistory</c>·<c>lapPositions</c>)·순위표·내 랩 스냅샷만으로 만든다.
/// <list type="bullet">
/// <item>페이스: 차마다 깨끗한 랩 중앙값 — 내 순위, 다른 차들 중앙값, 가장 빠른 차, 결과 바로 앞·뒤 차.</item>
/// <item>전략: 내 피트 스톱마다 앞 랩 순위 → 아웃 랩 다음 랩 순위, 스톱 손실(인·아웃 랩 − 깨끗한 랩 중앙값 2배), 완주 차들이 가장 많이 한 스톱 수, 우승 차 전략.</item>
/// <item>스틴트: 깨끗한 랩 중앙값·랩타임 추세(ms/랩, 최소제곱 기울기)를 같은 컴파운드로 달린 다른 차들과, 랩당 타이어 마모·끝 잔여 수명.</item>
/// <item>배터리: 랩 끝 잔량(처음·끝·최저)·랩당 배포·회수, 거의 바닥·가득 찬 랩 수.</item>
/// </list>
/// 깨끗한 랩 = <see cref="FirstRacingLap"/>랩부터, 피트 인·아웃 랩이 아니고, 그 차 후보 랩 중앙값의 <see cref="CleanLapLimit"/>배 안(세이프티카·사고 랩 제외).
/// 레이스가 아니거나 내 차·내 랩 기록을 모르면 null.
/// </summary>
public static class RaceReviewBuilder
{
    private const int FirstRacingLap = 2;
    private const double CleanLapLimit = 1.07;
    private const int MinPaceLaps = 3;
    private const int MinTrendLaps = 4;
    private const int PitLapsPerStop = 2;

    /// <summary>피트 뒤 순위를 볼 랩: 인 랩 + 이 값(아웃 랩 다음 랩 끝 — 다른 차들의 피트가 대개 정리된다).</summary>
    private const int SettleLaps = 2;

    /// <summary>F1 게임 ERS 배터리 용량(J)과 거의 바닥·가득으로 볼 비율.</summary>
    private const double ErsCapacityJ = 4_000_000;
    private const double LowStoreFraction = 0.1;
    private const double FullStoreFraction = 0.95;
    private const int WearDecimals = 2;

    public static RaceReviewDto? Build(
        GameSession session,
        IReadOnlyList<SessionResult> results,
        SessionHistory history,
        int? playerCarIndex,
        IReadOnlyList<MySessionLap> myLaps)
    {
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(results);
        ArgumentNullException.ThrowIfNull(history);
        ArgumentNullException.ThrowIfNull(myLaps);

        if (session.SessionType != SessionType.Race || playerCarIndex is not { } me)
        {
            return null;
        }

        var cars = results.Select(r => CarRace.Of(r, history)).ToList();
        var mine = cars.FirstOrDefault(c => c.Result.CarIndex == me);
        if (mine is null || mine.Laps.Count == 0)
        {
            return null;
        }

        return new RaceReviewDto(
            Pace(mine, cars),
            Strategy(mine, cars, history),
            Stints(mine, cars, myLaps),
            Battery(myLaps));
    }

    private static RacePaceReviewDto? Pace(CarRace mine, IReadOnlyList<CarRace> cars)
    {
        if (mine.MedianMs is not { } myMedian)
        {
            return null;
        }

        var ranked = cars.Where(c => c.MedianMs.HasValue).OrderBy(c => c.MedianMs).ThenBy(c => c.Result.CarIndex).ToList();
        var others = ranked.Where(c => !ReferenceEquals(c, mine)).ToList();
        if (others.Count == 0)
        {
            return null;
        }

        var fastest = others[0];
        var ahead = FinishNeighbour(mine, cars, -1);
        var behind = FinishNeighbour(mine, cars, 1);
        return new RacePaceReviewDto(
            myMedian,
            ranked.IndexOf(mine) + 1,
            ranked.Count,
            Round(Median(others.Select(c => (double)c.MedianMs!.Value))),
            fastest.Name,
            fastest.MedianMs!.Value,
            ahead?.Name,
            ahead?.MedianMs,
            behind?.Name,
            behind?.MedianMs);
    }

    /// <summary>결과 순위로 [offset]만큼 앞(-)·뒤(+) 차. 내 순위를 모르면 null.</summary>
    private static CarRace? FinishNeighbour(CarRace mine, IReadOnlyList<CarRace> cars, int offset)
        => mine.Result.Position > 0 ? cars.FirstOrDefault(c => c.Result.Position == mine.Result.Position + offset) : null;

    private static RaceStrategyReviewDto Strategy(CarRace mine, IReadOnlyList<CarRace> cars, SessionHistory history)
    {
        var me = mine.Result;
        var stops = new List<RacePitStopReviewDto>();
        for (var i = 0; i < mine.Spans.Count - 1; i++)
        {
            var inLap = mine.Spans[i].EndLap;
            var before = inLap - 1;
            stops.Add(new RacePitStopReviewDto(
                inLap,
                before < 1 ? NullIfZero(me.GridPosition) : history.PositionOf(me.CarIndex, before),
                history.PositionOf(me.CarIndex, inLap + SettleLaps) ?? NullIfZero(me.Position),
                mine.PitLossMs(inLap),
                mine.Spans[i].VisualCompound,
                mine.Spans[i + 1].VisualCompound));
        }

        // 완주 차들이 가장 많이 한 스톱 수(같으면 적은 쪽).
        var common = cars
            .Where(c => c.Result.ResultStatus == ResultStatus.Finished && c.Spans.Count > 0)
            .GroupBy(c => c.Spans.Count - 1)
            .OrderByDescending(g => g.Count())
            .ThenBy(g => g.Key)
            .FirstOrDefault();
        var winner = cars.FirstOrDefault(c => c.Result.Position == 1);
        var fieldLosses = cars
            .Where(c => !ReferenceEquals(c, mine))
            .SelectMany(c => c.Spans.Take(c.Spans.Count - 1).Select(s => c.PitLossMs(s.EndLap)))
            .OfType<int>()
            .Select(ms => (double)ms)
            .ToList();

        return new RaceStrategyReviewDto(
            NullIfZero(me.GridPosition),
            NullIfZero(me.Position),
            Math.Max(mine.Spans.Count - 1, 0),
            stops,
            common?.Key,
            common?.Count() ?? 0,
            winner is null || winner.Spans.Count == 0 ? null : winner.Spans.Count - 1,
            winner?.Spans.Select(s => s.VisualCompound).ToList() ?? [],
            fieldLosses.Count == 0 ? null : Round(Median(fieldLosses)));
    }

    private static List<RaceStintReviewDto> Stints(CarRace mine, IReadOnlyList<CarRace> cars, IReadOnlyList<MySessionLap> myLaps)
    {
        var lastLap = mine.Laps[^1].LapNumber;
        var stored = SessionLapsBuilder.LatestByLapNumber(myLaps);
        var others = cars.Where(c => !ReferenceEquals(c, mine)).ToList();
        var stints = new List<RaceStintReviewDto>();
        foreach (var span in mine.Spans)
        {
            var end = Math.Min(span.EndLap, lastLap);
            if (end < span.StartLap)
            {
                continue;
            }

            var clean = mine.CleanIn(span);
            var fieldStints = others
                .SelectMany(c => c.Spans.Where(s => s.VisualCompound == span.VisualCompound).Select(s => c.CleanIn(s)))
                .ToList();
            var fieldMedians = fieldStints.Where(l => l.Count >= MinPaceLaps).Select(l => Median(l.Select(x => (double)x.LapTimeMs))).ToList();
            var fieldTrends = fieldStints.Select(Trend).OfType<double>().ToList();
            var lives = Enumerable.Range(span.StartLap, end - span.StartLap + 1)
                .Select(n => (Lap: n, Life: stored.TryGetValue(n, out var lap) ? lap.TyreLifeRemaining : null))
                .Where(x => x.Life.HasValue)
                .ToList();
            double? wearPerLap = lives.Count >= 2
                ? Math.Round((lives[0].Life!.Value - lives[^1].Life!.Value) / (lives[^1].Lap - lives[0].Lap), WearDecimals)
                : null;

            stints.Add(new RaceStintReviewDto(
                span.VisualCompound,
                span.StartLap,
                end,
                clean.Count >= MinPaceLaps ? Round(Median(clean.Select(l => (double)l.LapTimeMs))) : null,
                fieldMedians.Count == 0 ? null : Round(Median(fieldMedians)),
                Trend(clean) is { } trend ? Round(trend) : null,
                fieldTrends.Count == 0 ? null : Round(Median(fieldTrends)),
                wearPerLap,
                lives.Count == 0 ? null : lives[^1].Life));
        }

        return stints;
    }

    private static RaceBatteryReviewDto? Battery(IReadOnlyList<MySessionLap> myLaps)
    {
        var laps = SessionLapsBuilder.LatestByLapNumber(myLaps).Values
            .Where(l => l.Row.ErsStoreEndJ.HasValue)
            .OrderBy(l => l.LapNumber)
            .ToList();
        if (laps.Count == 0)
        {
            return null;
        }

        var stores = laps.Select(l => l.Row.ErsStoreEndJ!.Value).ToList();
        var lowest = laps.MinBy(l => l.Row.ErsStoreEndJ!.Value)!;
        var deployed = laps.Select(l => l.Row.ErsDeployedJ).OfType<double>().ToList();
        var harvested = laps.Select(l => l.Row.ErsHarvestedJ).OfType<double>().ToList();
        return new RaceBatteryReviewDto(
            laps.Count,
            deployed.Count == 0 ? null : Math.Round(deployed.Average()),
            harvested.Count == 0 ? null : Math.Round(harvested.Average()),
            stores[0],
            stores[^1],
            lowest.Row.ErsStoreEndJ!.Value,
            lowest.LapNumber,
            stores.Count(s => s < ErsCapacityJ * LowStoreFraction),
            stores.Count(s => s >= ErsCapacityJ * FullStoreFraction),
            laps.Select(l => new RaceBatteryLapDto(l.LapNumber, l.Row.ErsStoreEndJ!.Value, l.Row.ErsDeployedJ, l.Row.ErsHarvestedJ)).ToList());
    }

    /// <summary>랩 번호에 대한 랩타임 최소제곱 기울기(ms/랩). 랩이 <see cref="MinTrendLaps"/>보다 적으면 null.</summary>
    private static double? Trend(IReadOnlyList<HistoryLap> laps)
    {
        if (laps.Count < MinTrendLaps)
        {
            return null;
        }

        var meanLap = laps.Average(l => (double)l.LapNumber);
        var meanTime = laps.Average(l => (double)l.LapTimeMs);
        var spread = laps.Sum(l => (l.LapNumber - meanLap) * (l.LapNumber - meanLap));
        return spread == 0 ? null : laps.Sum(l => (l.LapNumber - meanLap) * (l.LapTimeMs - meanTime)) / spread;
    }

    private static double Median(IEnumerable<double> values)
    {
        var sorted = values.Order().ToList();
        var middle = sorted.Count / 2;
        return sorted.Count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
    }

    private static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);

    private static int? NullIfZero(int value) => value > 0 ? value : null;

    /// <summary>차 한 대의 레이스: 스틴트 범위, 기록된 랩(진행 중 0 제외), 깨끗한 랩과 그 중앙값.</summary>
    private sealed class CarRace
    {
        private CarRace(SessionResult result, IReadOnlyList<StintSpan> spans, IReadOnlyList<HistoryLap> laps, IReadOnlyList<HistoryLap> clean)
        {
            Result = result;
            Spans = spans;
            Laps = laps;
            Clean = clean;
            MedianMs = clean.Count >= MinPaceLaps ? Round(Median(clean.Select(l => (double)l.LapTimeMs))) : null;
        }

        public SessionResult Result { get; }
        public IReadOnlyList<StintSpan> Spans { get; }
        public IReadOnlyList<HistoryLap> Laps { get; }
        public IReadOnlyList<HistoryLap> Clean { get; }
        public int? MedianMs { get; }
        public string Name => DriverLabels.Name(Result.DriverName, Result.CarIndex);

        public static CarRace Of(SessionResult result, SessionHistory history)
        {
            var spans = StintSpan.From(result);
            var laps = history.LapsOf(result.CarIndex).Where(l => l.LapTimeMs > 0).ToList();
            var pitLaps = spans.Where(s => !s.IsLast).SelectMany(s => Enumerable.Range(s.EndLap, PitLapsPerStop)).ToHashSet();
            var candidates = laps.Where(l => l.LapNumber >= FirstRacingLap && !pitLaps.Contains(l.LapNumber)).ToList();
            if (candidates.Count == 0)
            {
                return new CarRace(result, spans, laps, candidates);
            }

            var limit = Median(candidates.Select(l => (double)l.LapTimeMs)) * CleanLapLimit;
            return new CarRace(result, spans, laps, candidates.Where(l => l.LapTimeMs <= limit).ToList());
        }

        /// <summary>그 스틴트 안의 깨끗한 랩.</summary>
        public List<HistoryLap> CleanIn(StintSpan span) => Clean.Where(l => span.Contains(l.LapNumber)).ToList();

        /// <summary>[inLap]에 들어간 스톱의 손실(ms) = 인 랩 + 아웃 랩 − 깨끗한 랩 중앙값 2배. 하나라도 모르면 null.</summary>
        public int? PitLossMs(int inLap)
        {
            var median = MedianMs;
            var inTime = Laps.FirstOrDefault(l => l.LapNumber == inLap)?.LapTimeMs;
            var outTime = Laps.FirstOrDefault(l => l.LapNumber == inLap + 1)?.LapTimeMs;
            return median is null || inTime is null || outTime is null ? null : inTime.Value + outTime.Value - (PitLapsPerStop * median.Value);
        }
    }
}
