using SimCenter.Application.Laps;
using SimCenter.Application.Seasons.Queries.Detail;

namespace SimCenter.Application.TrackOverviews;

/// <summary>이론상 최고 랩 재료가 되는 내 랩 하나(트레이스는 기본 채널 + 횡 G·ERS 잔량·바퀴 노면만 풀어 둔다).</summary>
public sealed record TheoreticalLap(Guid LapId, int LapTimeMs, bool IsValid, DateTime SetAt, int ResolutionM, LapTraceChannels Channels);

/// <summary>
/// 한 랩에 쓸 수 있는 배터리 한도 — 게임 규정을 추측하지 않고 이 트랙에서 실제로 달린 랩들에서 잰다(J).
/// <see cref="StartJ"/> = 랩 시작 잔량 최대(아웃 랩에서 채워 들어온 상태), <see cref="CapacityJ"/> = 잔량 최대,
/// <see cref="DeployJ"/>·<see cref="HarvestJ"/> = 한 랩에서 잔량이 줄어든·늘어난 양 합의 최대.
/// </summary>
public sealed record ErsBudget(double StartJ, double CapacityJ, double DeployJ, double HarvestJ);

/// <summary>이론상 최고 랩의 구간 하나: 랩 거리 [<see cref="StartM"/>, <see cref="EndM"/>), 그 구간을 가장 잘 달린 랩과 기록, 최고 랩의 같은 구간 값.</summary>
public sealed record TheoreticalSegment(
    int Index,
    int StartM,
    int EndM,
    Guid LapId,
    DateTime LapSetAt,
    int TimeMs,
    int BestLapTimeMs,
    double? DeployJ,
    double? HarvestJ,
    double? BestLapDeployJ,
    double? BestLapHarvestJ);

/// <summary>
/// 이론상 최고 랩. <see cref="TheoreticalMs"/> = 배터리 한도를 지킨 구간 조합, <see cref="UnlimitedMs"/> = 구간마다 가장 빠른 기록의 단순 합(배터리 무시).
/// <see cref="LapCount"/> = 재료로 쓴 랩 수.
/// </summary>
public sealed record TheoreticalBestResult(
    int LapCount,
    int LapLengthM,
    Guid BestLapId,
    int BestLapMs,
    int TheoreticalMs,
    int UnlimitedMs,
    bool HasBattery,
    IReadOnlyList<TheoreticalSegment> Segments);

/// <summary>
/// 이론상 최고 랩 계산(순수). 같은 조건(세션 종류·컴파운드)의 내 랩들을 구간으로 잘라 구간마다 한 랩의 기록을 골라 잇는다.
/// <list type="bullet">
/// <item>구간: 최고 랩의 코너(<see cref="RaceSegments"/>) 시작 <see cref="BoundaryLeadM"/>m 앞 = 브레이킹 직전에서 끊는다 — 코너와 그 뒤 직선이 한 구간이라
/// 코너 탈출 속도가 직선 기록에 주는 영향이 다른 랩의 직선과 섞이지 않는다.</item>
/// <item>무효 랩: 네 바퀴가 모두 아스팔트·연석 밖에 <see cref="OffTrackRunSamples"/>칸 넘게 있던 구간만 뺀다. 그런 곳을 못 찾으면(노면 채널이 없거나
/// 판정을 못 함) 어디서 무효가 됐는지 몰라 랩을 통째로 뺀다. 유효 랩은 게임 판정을 믿고 모든 구간을 쓴다.</item>
/// <item>배터리: 구간마다 잔량이 줄어든 양(씀)·늘어난 양(채움)·구간 중 가장 깊이 내려간 양을 재고, 동적 계획법으로 랩 전체 씀 ≤ <see cref="ErsBudget.DeployJ"/>,
/// 채움 ≤ <see cref="ErsBudget.HarvestJ"/>, 잔량이 0 밑으로 내려가지 않는(출발 잔량 <see cref="ErsBudget.StartJ"/>, 가득 차면 더 채우지 못함) 조합 중 가장 빠른 것을 고른다.
/// 직선은 배터리를 다 쓴 랩에서, 코너는 아낀 랩에서 가져와 실제로는 낼 수 없는 랩이 되는 것을 막는다.</item>
/// </list>
/// 결과는 최고 랩보다 느리지 않다(최고 랩 자체가 늘 가능한 조합이다).
/// </summary>
public static class TheoreticalBestCalculator
{
    /// <summary>구간 경계를 코너 시작보다 이만큼(m) 앞에 둔다 — 모든 랩이 아직 최고 속도로 달리는 자리에서 잇는다.</summary>
    private const double BoundaryLeadM = 30;

    /// <summary>두 경계가 이보다(m) 가까우면 하나로 합친다.</summary>
    private const double MinSegmentM = 60;

    /// <summary>트레이스 길이가 기준 랩과 이 비율보다 다르면(중간에 끊긴 랩) 쓰지 않는다.</summary>
    private const double LengthTolerance = 0.03;

    /// <summary>네 바퀴가 모두 트랙 밖인 칸이 이만큼 이어지면 트랙 이탈로 본다(한 칸짜리 튐은 무시).</summary>
    private const int OffTrackRunSamples = 2;

    private const int TarmacSurface = 0;
    private const int RumbleSurface = 1;

    /// <summary>동적 계획법의 배터리 칸 크기(J). 구간 20여 개의 반올림 오차가 합쳐도 100kJ 안팎이다.</summary>
    private const double EnergyStepJ = 20_000;

    /// <summary>계산에 쓰는 추가 채널 — 이것만 풀면 된다.</summary>
    public static readonly IReadOnlySet<string> RequiredExtraChannels = new HashSet<string>(
        [TraceChannelNames.LateralG, TraceChannelNames.ErsStore, .. TraceChannelNames.Wheels.Select(w => TraceChannelNames.Surface + w)],
        StringComparer.Ordinal);

    /// <summary>한 구간을 한 랩이 달린 값. <see cref="MinRelJ"/> = 구간 시작 잔량 대비 가장 깊이 내려간 양(≤ 0).</summary>
    private sealed record Option(int Lap, int TimeMs, double DeployJ, double HarvestJ, double MinRelJ);

    /// <summary>ERS 잔량 채널이 있는 랩들에서 배터리 한도를 잰다. 그런 랩이 없으면 null(배터리를 따지지 않는다).</summary>
    public static ErsBudget? MeasureBudget(IEnumerable<TheoreticalLap> laps)
    {
        ArgumentNullException.ThrowIfNull(laps);
        ErsBudget? budget = null;
        foreach (var lap in laps)
        {
            if (Store(lap) is not { Length: > 1 } store)
            {
                continue;
            }

            var (deploy, harvest, _) = Flows(store, 0, store.Length - 1);
            budget = budget is null
                ? new ErsBudget(store[0], store.Max(), deploy, harvest)
                : new ErsBudget(
                    Math.Max(budget.StartJ, store[0]),
                    Math.Max(budget.CapacityJ, store.Max()),
                    Math.Max(budget.DeployJ, deploy),
                    Math.Max(budget.HarvestJ, harvest));
        }

        return budget;
    }

    /// <summary>
    /// 같은 조건의 랩들로 이론상 최고 랩을 낸다. 유효 랩이 없거나, 기준 랩에 횡 G 채널이 없어 구간을 못 나누면 null.
    /// <paramref name="budget"/>이 null이면 배터리를 따지지 않는다(구간마다 가장 빠른 기록).
    /// </summary>
    public static TheoreticalBestResult? Compute(IReadOnlyList<TheoreticalLap> laps, ErsBudget? budget)
    {
        ArgumentNullException.ThrowIfNull(laps);
        var usable = laps.Where(l => l.ResolutionM > 0 && l.Channels.TimeMs.Length > 1).ToList();
        var best = usable.Where(l => l.IsValid).OrderBy(l => l.LapTimeMs).ThenBy(l => l.SetAt).FirstOrDefault();
        var reference = usable
            .Where(l => l.IsValid && Extra(l, TraceChannelNames.LateralG) is not null)
            .OrderBy(l => l.LapTimeMs).ThenBy(l => l.SetAt)
            .FirstOrDefault();
        if (best is null || reference is null)
        {
            return null;
        }

        var lengthM = reference.Channels.TimeMs.Length * reference.ResolutionM;
        var bounds = Boundaries(reference, lengthM);
        if (bounds.Count < 2)
        {
            return null;
        }

        var segmentCount = bounds.Count - 1;
        var hasBattery = budget is not null;
        var options = Enumerable.Range(0, segmentCount).Select(_ => new List<Option>()).ToArray();
        var used = new List<TheoreticalLap>();
        Option[]? bestRow = null;
        foreach (var lap in usable)
        {
            var row = Measure(lap, bounds, lengthM, hasBattery);
            if (row is null)
            {
                continue;
            }

            var lapIndex = used.Count;
            used.Add(lap);
            var tagged = row.Select(o => o is null ? null : o with { Lap = lapIndex }).ToArray();
            if (ReferenceEquals(lap, best))
            {
                // 최고 랩은 유효 랩이라 모든 구간이 있다(시간이 뒤로 간 구간이 있으면 아래에서 비교 기준 없음으로 끝난다).
                bestRow = tagged.All(o => o is not null) ? tagged.Select(o => o!).ToArray() : null;
            }

            for (var s = 0; s < segmentCount; s++)
            {
                if (tagged[s] is { } option)
                {
                    options[s].Add(option);
                }
            }
        }

        // 최고 랩을 잴 수 없으면(길이가 크게 다름·ERS 채널 없음·시간이 뒤로 감) 비교 기준이 없다.
        if (bestRow is null)
        {
            return null;
        }

        // 잔량이 랩 내내 그대로인 조건(배터리를 쓰지 않는 Time Trial 등)은 배터리를 따질 것이 없다.
        if (hasBattery && options.All(list => list.All(o => o.DeployJ <= 0 && o.HarvestJ <= 0)))
        {
            hasBattery = false;
            budget = null;
        }

        var unlimited = options.Select(list => list.Min(o => o.TimeMs)).Sum();
        var chosen = budget is null
            ? options.Select(list => list.OrderBy(o => o.TimeMs).ThenBy(o => used[o.Lap].SetAt).First()).ToArray()
            : Optimise(options, budget) ?? bestRow;
        if (chosen.Sum(o => o.TimeMs) > best.LapTimeMs)
        {
            chosen = bestRow;
        }

        var segments = chosen
            .Select((o, s) => new TheoreticalSegment(
                s,
                (int)Math.Round(bounds[s]),
                (int)Math.Round(bounds[s + 1]),
                used[o.Lap].LapId,
                used[o.Lap].SetAt,
                o.TimeMs,
                bestRow[s].TimeMs,
                hasBattery ? o.DeployJ : null,
                hasBattery ? o.HarvestJ : null,
                hasBattery ? bestRow[s].DeployJ : null,
                hasBattery ? bestRow[s].HarvestJ : null))
            .ToList();
        return new TheoreticalBestResult(
            used.Count, lengthM, best.LapId, best.LapTimeMs, chosen.Sum(o => o.TimeMs), Math.Min(unlimited, best.LapTimeMs), hasBattery, segments);
    }

    /// <summary>구간 경계(m): 0, 코너 시작 − <see cref="BoundaryLeadM"/>(가까운 것은 합침)…, 랩 길이.</summary>
    private static List<double> Boundaries(TheoreticalLap reference, int lengthM)
    {
        var ranges = RaceSegments.Detect(new RaceTraceLap(0, reference.ResolutionM, reference.Channels));
        var bounds = new List<double> { 0 };
        foreach (var start in ranges.Where(r => r.IsCorner).Select(r => (double)r.Start * reference.ResolutionM - BoundaryLeadM).Order())
        {
            if (start - bounds[^1] >= MinSegmentM && lengthM - start >= MinSegmentM)
            {
                bounds.Add(start);
            }
        }

        bounds.Add(lengthM);
        return bounds;
    }

    /// <summary>
    /// 한 랩을 구간마다 잰다. 쓸 수 없는 랩이면 null, 쓸 수 없는 구간(무효 랩의 트랙 이탈·시간이 뒤로 감)은 그 칸만 null.
    /// 구간 s의 시간 = 경계 표본 사이 시간(첫 구간은 결승선부터, 마지막 구간은 결승선까지) — 구간 합 = 랩타임.
    /// </summary>
    private static Option?[]? Measure(TheoreticalLap lap, List<double> bounds, int lengthM, bool hasBattery)
    {
        var time = lap.Channels.TimeMs;
        var count = time.Length;
        var resolution = lap.ResolutionM;
        if (Math.Abs(count * resolution - lengthM) > lengthM * LengthTolerance)
        {
            return null;
        }

        var store = Store(lap);
        if (hasBattery && store is null)
        {
            return null;
        }

        var offTrack = lap.IsValid ? null : OffTrackSamples(lap);
        if (!lap.IsValid && (offTrack is null || offTrack.Count == 0))
        {
            return null;
        }

        var segmentCount = bounds.Count - 1;
        var row = new Option?[segmentCount];
        for (var s = 0; s < segmentCount; s++)
        {
            var from = s == 0 ? 0 : Math.Clamp((int)Math.Round(bounds[s] / resolution), 0, count - 1);
            var to = s == segmentCount - 1 ? count - 1 : Math.Clamp((int)Math.Round(bounds[s + 1] / resolution), 0, count - 1);
            if (to <= from || offTrack?.Any(i => i >= from && i <= to) == true)
            {
                continue;
            }

            var ordered = true;
            for (var i = from + 1; i <= to && ordered; i++)
            {
                ordered = time[i] >= time[i - 1];
            }

            var startMs = s == 0 ? 0 : time[from];
            var endMs = s == segmentCount - 1 ? lap.LapTimeMs : time[to];
            if (!ordered || endMs <= startMs)
            {
                continue;
            }

            var (deploy, harvest, minRel) = store is null ? (0d, 0d, 0d) : Flows(store, from, to);
            row[s] = new Option(0, endMs - startMs, deploy, harvest, minRel);
        }

        return row;
    }

    /// <summary>잔량 [from, to] 사이 이웃 표본 변화: 줄어든 양 합·늘어난 양 합·시작 대비 가장 깊이 내려간 양(≤ 0).</summary>
    private static (double Deploy, double Harvest, double MinRel) Flows(double[] store, int from, int to)
    {
        double deploy = 0, harvest = 0, rel = 0, min = 0;
        for (var i = from + 1; i <= to; i++)
        {
            var change = store[i] - store[i - 1];
            deploy += Math.Max(0, -change);
            harvest += Math.Max(0, change);
            rel += change;
            min = Math.Min(min, rel);
        }

        return (deploy, harvest, min);
    }

    /// <summary>네 바퀴가 모두 아스팔트·연석 밖인 칸이 <see cref="OffTrackRunSamples"/>칸 넘게 이어진 표본들. 노면 채널이 없으면 null.</summary>
    private static List<int>? OffTrackSamples(TheoreticalLap lap)
    {
        var wheels = TraceChannelNames.Wheels.Select(w => Extra(lap, TraceChannelNames.Surface + w)).ToArray();
        if (wheels.Any(w => w is null))
        {
            return null;
        }

        bool Off(int i) => wheels.All(w => (int)w![i] is not (TarmacSurface or RumbleSurface));
        var result = new List<int>();
        var count = lap.Channels.TimeMs.Length;
        for (var i = 0; i < count; i++)
        {
            if (!Off(i))
            {
                continue;
            }

            var end = i;
            while (end + 1 < count && Off(end + 1))
            {
                end++;
            }

            if (end - i + 1 >= OffTrackRunSamples)
            {
                result.AddRange(Enumerable.Range(i, end - i + 1));
            }

            i = end;
        }

        return result;
    }

    /// <summary>
    /// 배터리 한도 안에서 가장 빠른 구간 조합(동적 계획법). 상태 = (지금까지 쓴 양, 실제로 채운 양) 칸 — 잔량은 출발 잔량 + 채움 − 씀으로 정해진다.
    /// 가득 찬 배터리는 더 채우지 못하므로 넘치는 채움은 버린다. 가능한 조합이 없으면 null.
    /// </summary>
    private static Option[]? Optimise(List<Option>[] options, ErsBudget budget)
    {
        var deployLevels = (int)Math.Ceiling(budget.DeployJ / EnergyStepJ) + 1;
        var harvestLevels = (int)Math.Ceiling(budget.HarvestJ / EnergyStepJ) + 1;
        var stateCount = deployLevels * harvestLevels;
        var segmentCount = options.Length;
        var cost = new int[stateCount];
        Array.Fill(cost, int.MaxValue);
        cost[0] = 0;
        var choice = new int[segmentCount][];
        var previous = new int[segmentCount][];

        for (var s = 0; s < segmentCount; s++)
        {
            var next = new int[stateCount];
            Array.Fill(next, int.MaxValue);
            choice[s] = new int[stateCount];
            previous[s] = new int[stateCount];
            var list = options[s];
            for (var state = 0; state < stateCount; state++)
            {
                if (cost[state] == int.MaxValue)
                {
                    continue;
                }

                var deployed = state / harvestLevels * EnergyStepJ;
                var harvested = state % harvestLevels * EnergyStepJ;
                var level = budget.StartJ + harvested - deployed;
                for (var k = 0; k < list.Count; k++)
                {
                    var o = list[k];
                    if (level + o.MinRelJ < -EnergyStepJ)
                    {
                        continue;
                    }

                    var deployAfter = deployed + o.DeployJ;
                    var overflow = Math.Max(0, level + o.HarvestJ - o.DeployJ - budget.CapacityJ);
                    var harvestAfter = harvested + Math.Max(0, o.HarvestJ - overflow);
                    if (deployAfter > budget.DeployJ + EnergyStepJ || harvestAfter > budget.HarvestJ + EnergyStepJ)
                    {
                        continue;
                    }

                    var d = Math.Min(deployLevels - 1, (int)Math.Round(deployAfter / EnergyStepJ));
                    var h = Math.Min(harvestLevels - 1, (int)Math.Round(harvestAfter / EnergyStepJ));
                    var target = d * harvestLevels + h;
                    var total = cost[state] + o.TimeMs;
                    if (total < next[target])
                    {
                        next[target] = total;
                        choice[s][target] = k;
                        previous[s][target] = state;
                    }
                }
            }

            cost = next;
        }

        var end = -1;
        for (var state = 0; state < stateCount; state++)
        {
            if (cost[state] != int.MaxValue && (end < 0 || cost[state] < cost[end]))
            {
                end = state;
            }
        }

        if (end < 0)
        {
            return null;
        }

        var chosen = new Option[segmentCount];
        for (var s = segmentCount - 1; s >= 0; s--)
        {
            chosen[s] = options[s][choice[s][end]];
            end = previous[s][end];
        }

        return chosen;
    }

    private static double[]? Store(TheoreticalLap lap) => Extra(lap, TraceChannelNames.ErsStore);

    private static double[]? Extra(TheoreticalLap lap, string name)
        => lap.Channels.Extra is { } extra && extra.TryGetValue(name, out var values) && values.Length == lap.Channels.TimeMs.Length ? values : null;
}
