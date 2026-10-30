using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 레이스 총평 재료(순수 계산). 세션 기록(<c>lapHistory</c>·<c>lapPositions</c>)·순위표·내 랩 스냅샷만으로 만든다.
/// <list type="bullet">
/// <item>페이스: 차마다 깨끗한 랩 중앙값 — 내 순위, 다른 차들 중앙값, 가장 빠른 차, 결과 바로 앞·뒤 차.</item>
/// <item>전략: 내 피트 스톱마다 앞 랩 순위 → 아웃 랩 다음 랩 순위, 스톱 손실(인·아웃 랩 − 깨끗한 랩 중앙값 2배)과 비슷한 때 들어간 차들 손실, 완주 차들이 가장 많이 한 스톱 수, 우승 차 전략, 스톱 수별 완주 순위, 나와 스톱 수가 달라 출발·결과 순서가 뒤바뀐 차.</item>
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

    /// <summary>
    /// 피트 손실을 견줄 다른 차 스톱: 내 인 랩 앞뒤 이 랩 수 안(타이어가 닳은 정도·연료가 비슷하다). 스톱 수가 같은 차를 먼저 본다 —
    /// 원스톱의 늦은 인 랩과 투스톱의 이른 인 랩은 타이어 상태가 달라 바로 견줄 수 없다.
    /// </summary>
    private const int PeerLapWindow = 3;

    /// <summary>F1 게임 ERS 배터리 용량(J)과 거의 바닥·가득으로 볼 비율.</summary>
    private const double ErsCapacityJ = 4_000_000;
    private const double LowStoreFraction = 0.1;
    private const double FullStoreFraction = 0.95;
    private const int WearDecimals = 2;

    /// <summary>랩 사이 남은 수명이 이보다 크게(%p) 올라가면 새 타이어로 본다.</summary>
    private const double NewSetLifeJumpPct = 2;

    /// <summary>섹터 수, 바퀴 수, 스틴트 끝 페이스를 볼 마지막 깨끗한 랩 수.</summary>
    private const int SectorCount = 3;
    private const int WheelCount = 4;
    private const int EndLaps = 3;

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
        var fieldSectors = others.Select(c => SectorMedians(c.Clean)).OfType<IReadOnlyList<int>>().ToList();
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
            behind?.MedianMs,
            SectorMedians(mine.Clean),
            fieldSectors.Count == 0
                ? null
                : Enumerable.Range(0, SectorCount).Select(i => Round(Median(fieldSectors.Select(s => (double)s[i])))).ToList(),
            ahead is null ? null : SectorMedians(ahead.Clean));
    }

    /// <summary>깨끗한 랩의 섹터 1·2·3 중앙값(ms). 세 섹터가 모두 있는 랩이 <see cref="MinPaceLaps"/>보다 적으면 null.</summary>
    private static IReadOnlyList<int>? SectorMedians(IReadOnlyList<HistoryLap> clean)
    {
        var laps = clean.Where(l => l.Sector1TimeMs > 0 && l.Sector2TimeMs > 0 && l.Sector3TimeMs > 0).ToList();
        return laps.Count < MinPaceLaps
            ? null
            :
            [
                Round(Median(laps.Select(l => (double)l.Sector1TimeMs))),
                Round(Median(laps.Select(l => (double)l.Sector2TimeMs))),
                Round(Median(laps.Select(l => (double)l.Sector3TimeMs))),
            ];
    }

    /// <summary>결과 순위로 [offset]만큼 앞(-)·뒤(+) 차. 내 순위를 모르면 null.</summary>
    private static CarRace? FinishNeighbour(CarRace mine, IReadOnlyList<CarRace> cars, int offset)
        => mine.Result.Position > 0 ? cars.FirstOrDefault(c => c.Result.Position == mine.Result.Position + offset) : null;

    private static RaceStrategyReviewDto Strategy(CarRace mine, IReadOnlyList<CarRace> cars, SessionHistory history)
    {
        var me = mine.Result;
        var myStops = Math.Max(mine.Spans.Count - 1, 0);
        var fieldStops = cars
            .Where(c => !ReferenceEquals(c, mine))
            .SelectMany(c => c.Spans.Take(c.Spans.Count - 1).Select(s => (Car: c, InLap: s.EndLap)))
            .ToList();
        var stops = new List<RacePitStopReviewDto>();
        for (var i = 0; i < mine.Spans.Count - 1; i++)
        {
            var inLap = mine.Spans[i].EndLap;
            var before = inLap - 1;
            var near = fieldStops.Where(s => Math.Abs(s.InLap - inLap) <= PeerLapWindow).ToList();
            var sameCount = near.Where(s => s.Car.Spans.Count - 1 == myStops).ToList();
            var peers = sameCount.Count > 0 ? sameCount : near;
            int? PeerMedian(Func<CarRace, int, int?> loss)
                => peers.Select(s => loss(s.Car, s.InLap)).OfType<int>().Select(ms => (double)ms).ToList() is { Count: > 0 } values
                    ? Round(Median(values))
                    : null;
            stops.Add(new RacePitStopReviewDto(
                inLap,
                before < 1 ? NullIfZero(me.GridPosition) : history.PositionOf(me.CarIndex, before),
                history.PositionOf(me.CarIndex, inLap + SettleLaps) ?? NullIfZero(me.Position),
                mine.PitLossMs(inLap),
                mine.Spans[i].VisualCompound,
                mine.Spans[i + 1].VisualCompound,
                mine.LapLossMs(inLap),
                mine.LapLossMs(inLap + 1),
                PeerMedian((c, lap) => c.PitLossMs(lap)),
                peers.Count(s => s.Car.PitLossMs(s.InLap) is not null),
                PeerMedian((c, lap) => c.LapLossMs(lap)),
                PeerMedian((c, lap) => c.LapLossMs(lap + 1))));
        }

        // 완주 차들이 가장 많이 한 스톱 수(같으면 적은 쪽).
        var common = cars
            .Where(c => c.Result.ResultStatus == ResultStatus.Finished && c.Spans.Count > 0)
            .GroupBy(c => c.Spans.Count - 1)
            .OrderByDescending(g => g.Count())
            .ThenBy(g => g.Key)
            .FirstOrDefault();
        var winner = cars.FirstOrDefault(c => c.Result.Position == 1);

        // 스톱 수마다 완주 순위, 그리고 나와 스톱 수가 다르면서 출발·결과 순서가 나와 뒤바뀐 차(전략이 순위를 바꾼 상대).
        var finishers = cars
            .Where(c => c.Result.ResultStatus == ResultStatus.Finished && c.Spans.Count > 0 && c.Result.Position > 0)
            .ToList();
        var stopGroups = finishers
            .GroupBy(c => c.Spans.Count - 1)
            .OrderBy(g => g.Key)
            .Select(g => new RaceStopGroupDto(g.Key, g.Select(c => c.Result.Position).Order().ToList()))
            .ToList();
        var rivals = me.GridPosition > 0 && me.Position > 0
            ? finishers
                .Where(c => !ReferenceEquals(c, mine) && c.Spans.Count - 1 != myStops && c.Result.GridPosition > 0)
                .Where(c => (c.Result.GridPosition > me.GridPosition && c.Result.Position < me.Position)
                    || (c.Result.GridPosition < me.GridPosition && c.Result.Position > me.Position))
                .OrderBy(c => c.Result.Position)
                .Select(c => new RaceStrategyRivalDto(c.Name, c.Spans.Count - 1, c.Result.GridPosition, c.Result.Position))
                .ToList()
            : [];
        List<double> FieldLosses(Func<CarRace, int, int?> loss)
            => fieldStops.Select(s => loss(s.Car, s.InLap)).OfType<int>().Select(ms => (double)ms).ToList();
        var fieldLosses = FieldLosses((c, lap) => c.PitLossMs(lap));
        var fieldInLosses = FieldLosses((c, lap) => c.LapLossMs(lap));
        var fieldOutLosses = FieldLosses((c, lap) => c.LapLossMs(lap + 1));

        return new RaceStrategyReviewDto(
            NullIfZero(me.GridPosition),
            NullIfZero(me.Position),
            myStops,
            stops,
            common?.Key,
            common?.Count() ?? 0,
            winner is null || winner.Spans.Count == 0 ? null : winner.Spans.Count - 1,
            winner?.Spans.Select(s => s.VisualCompound).ToList() ?? [],
            fieldLosses.Count == 0 ? null : Round(Median(fieldLosses)),
            mine.Laps
                .Select(l => history.PositionOf(me.CarIndex, l.LapNumber) is { } p ? new RaceLapPositionDto(l.LapNumber, p) : null)
                .OfType<RaceLapPositionDto>()
                .ToList(),
            fieldInLosses.Count == 0 ? null : Round(Median(fieldInLosses)),
            fieldOutLosses.Count == 0 ? null : Round(Median(fieldOutLosses)),
            stopGroups,
            rivals);
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
            // 같은 컴파운드로 다른 차들이 피트에 들어가기 전까지 탄 랩 수(마지막 스틴트는 체커까지라 뺀다) — 마모가 빠른지 견주는 기준.
            var fieldLengths = others
                .SelectMany(c => c.Spans.Where(s => !s.IsLast && s.VisualCompound == span.VisualCompound))
                .Select(s => (double)(s.EndLap - s.StartLap + 1))
                .ToList();
            var lives = OneSet(Enumerable.Range(span.StartLap, end - span.StartLap + 1)
                .Select(n => (Lap: n, Life: stored.TryGetValue(n, out var lap) ? lap.TyreLifeRemaining : null))
                .Where(x => x.Life.HasValue)
                .Select(x => (x.Lap, Life: x.Life!.Value))
                .ToList());
            double? wearPerLap = lives.Count >= 2
                ? Math.Round((lives[0].Life - lives[^1].Life) / (lives[^1].Lap - lives[0].Lap), WearDecimals)
                : null;
            var cleanTimes = clean.Select(l => (double)l.LapTimeMs).ToList();
            int? endSlower = cleanTimes.Count >= MinTrendLaps
                ? Round(Median(cleanTimes.TakeLast(EndLaps)) - Median(cleanTimes))
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
                lives.Count == 0 ? null : lives[^1].Life,
                lives.Count >= 2 ? WheelWearPerLap(stored, lives[0].Lap, lives[^1].Lap) : null,
                endSlower,
                fieldLengths.Count == 0 ? null : Round(Median(fieldLengths))));
        }

        return stints;
    }

    /// <summary>
    /// 랩별 남은 수명을 한 타이어 세트 것만 남긴다: 수명이 <see cref="NewSetLifeJumpPct"/>보다 크게 올라가면(새 타이어) 거기서 나누고
    /// 가장 긴 구간(같으면 앞)을 쓴다 — 스틴트 범위 끝에 피트 랩(새 타이어)이 걸려도 마모가 거꾸로 나오지 않게.
    /// </summary>
    private static List<(int Lap, double Life)> OneSet(List<(int Lap, double Life)> lives)
    {
        var best = new List<(int Lap, double Life)>();
        var current = new List<(int Lap, double Life)>();
        foreach (var life in lives)
        {
            if (current.Count > 0 && life.Life > current[^1].Life + NewSetLifeJumpPct)
            {
                if (current.Count > best.Count)
                {
                    best = current;
                }

                current = [];
            }

            current.Add(life);
        }

        return current.Count > best.Count ? current : best;
    }

    /// <summary>스틴트 [start]~[end]랩의 바퀴별 랩당 마모(%p, 앞왼·앞오·뒤왼·뒤오) — 네 바퀴 마모가 모두 있는 처음·마지막 랩으로. 두 랩이 안 되면 null.</summary>
    private static IReadOnlyList<double>? WheelWearPerLap(IReadOnlyDictionary<int, MySessionLap> stored, int start, int end)
    {
        static double[]? Wheels(MySessionLap lap)
            => lap.Row is { TyreWearEndFrontLeft: { } fl, TyreWearEndFrontRight: { } fr, TyreWearEndRearLeft: { } rl, TyreWearEndRearRight: { } rr }
                ? [fl, fr, rl, rr]
                : null;

        var laps = Enumerable.Range(start, end - start + 1)
            .Select(n => (Lap: n, Wear: stored.TryGetValue(n, out var lap) ? Wheels(lap) : null))
            .Where(x => x.Wear is not null)
            .ToList();
        if (laps.Count < 2)
        {
            return null;
        }

        var span = laps[^1].Lap - laps[0].Lap;
        return Enumerable.Range(0, WheelCount).Select(i => Math.Round((laps[^1].Wear![i] - laps[0].Wear![i]) / span, WearDecimals)).ToList();
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
    internal static double? Trend(IReadOnlyList<HistoryLap> laps)
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

    internal static double Median(IEnumerable<double> values)
    {
        var sorted = values.Order().ToList();
        var middle = sorted.Count / 2;
        return sorted.Count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
    }

    internal static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);

    private static int? NullIfZero(int value) => value > 0 ? value : null;

    /// <summary>차 한 대의 레이스: 스틴트 범위, 기록된 랩(진행 중 0 제외), 깨끗한 랩과 그 중앙값. 심층 분석(<see cref="RaceAnalysisBuilder"/>)도 같은 깨끗한 랩을 쓴다.</summary>
    internal sealed class CarRace
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

        /// <summary>[lap] 랩타임 − 깨끗한 랩 중앙값(ms, 인 랩·아웃 랩 손실). 모르면 null.</summary>
        public int? LapLossMs(int lap)
            => MedianMs is { } median && Laps.FirstOrDefault(l => l.LapNumber == lap) is { } found ? found.LapTimeMs - median : null;

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
