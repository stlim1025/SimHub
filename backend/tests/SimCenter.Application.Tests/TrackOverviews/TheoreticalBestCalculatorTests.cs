using SimCenter.Application.Laps;
using SimCenter.Application.TrackOverviews;

namespace SimCenter.Application.Tests.TrackOverviews;

/// <summary>
/// 이론상 최고 랩: 1km 트랙(10m 간격 100표본) — 코너 A 300~400m · 코너 B 700~780m(횡 G 1.6).
/// 구간 경계는 코너 시작 30m 앞(270m·670m) → 구간 0 [0, 270) · 구간 1 [270, 670) · 구간 2 [670, 1000).
/// </summary>
public class TheoreticalBestCalculatorTests
{
    private const int ResolutionM = 10;
    private const int SampleCount = 100;
    private const int FirstBoundary = 27;
    private const int SecondBoundary = 67;
    private const double FullStoreJ = 4_000_000;
    private const int GravelSurface = 4;

    private static readonly DateTime Day = new(2026, 11, 1, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Compute_WithoutBattery_TakesTheFastestRunOfEachSegment()
    {
        var a = Lap(1, [30_000, 40_000, 30_000]);
        var b = Lap(2, [29_500, 40_500, 30_200]);
        var c = Lap(3, [30_300, 40_200, 29_700]);

        var result = TheoreticalBestCalculator.Compute([b, a, c], budget: null)!;

        Assert.Equal((a.LapId, 100_000, 99_200, 99_200, 3), (result.BestLapId, result.BestLapMs, result.TheoreticalMs, result.UnlimitedMs, result.LapCount));
        Assert.False(result.HasBattery);
        Assert.Equal(1000, result.LapLengthM);
        Assert.Equal([(0, 270), (270, 670), (670, 1000)], result.Segments.Select(s => (s.StartM, s.EndM)));
        Assert.Equal([b.LapId, a.LapId, c.LapId], result.Segments.Select(s => s.LapId));
        Assert.Equal([30_000, 40_000, 30_000], result.Segments.Select(s => s.BestLapTimeMs));
        Assert.All(result.Segments, s => Assert.Null(s.DeployJ));
    }

    [Fact]
    public void Compute_KeepsTheLapWithinTheBatteryUsedOnAnyRealLap()
    {
        // 랩마다 배터리를 최대 3MJ 썼다. B는 구간 1에서 3MJ를 다 써 1초 빠르고, C는 구간 2에서 3MJ를 다 써 1초 빠르다 —
        // 둘을 이으면 6MJ라 실제로는 낼 수 없다. 3MJ 안에서는 B의 구간 1 + A의 구간 2가 가장 빠르다.
        var a = Lap(1, [30_000, 40_000, 30_000], deployJ: [0, 1_000_000, 0]);
        var b = Lap(2, [30_600, 39_000, 30_500], deployJ: [0, 3_000_000, 0]);
        var c = Lap(3, [30_100, 41_000, 29_000], deployJ: [0, 0, 3_000_000]);
        var laps = new[] { a, b, c };

        var budget = TheoreticalBestCalculator.MeasureBudget(laps)!;
        var result = TheoreticalBestCalculator.Compute(laps, budget)!;

        Assert.Equal(new ErsBudget(FullStoreJ, FullStoreJ, 3_000_000, 0), budget);
        Assert.True(result.HasBattery);
        Assert.Equal((99_000, 98_000), (result.TheoreticalMs, result.UnlimitedMs));
        Assert.Equal([a.LapId, b.LapId, a.LapId], result.Segments.Select(s => s.LapId));
        Assert.Equal((3_000_000d, 1_000_000d), (result.Segments[1].DeployJ!.Value, result.Segments[1].BestLapDeployJ!.Value));
    }

    [Fact]
    public void Compute_HarvestRefillsTheBatteryForALaterSegment()
    {
        // 출발 잔량 1MJ. D는 구간 0에서 2MJ를 채워 구간 2에서 3MJ를 쓴다 — 채움 없이 구간 2의 3MJ를 가져오면 잔량이 바닥 밑으로 내려간다.
        var a = Lap(1, [30_000, 40_000, 30_000], startJ: 1_000_000);
        var d = Lap(2, [30_200, 40_100, 29_000], deployJ: [0, 0, 3_000_000], harvestJ: [2_000_000, 0, 0], startJ: 1_000_000);
        var laps = new[] { a, d };

        var result = TheoreticalBestCalculator.Compute(laps, TheoreticalBestCalculator.MeasureBudget(laps))!;

        // A의 구간 0(채움 없음) + D의 구간 2는 잔량 1MJ로 3MJ를 써야 해 안 된다 → D의 구간 0·2를 함께 쓴다.
        Assert.Equal(99_200, result.TheoreticalMs);
        Assert.Equal([d.LapId, a.LapId, d.LapId], result.Segments.Select(s => s.LapId));
    }

    [Fact]
    public void Compute_BatteryThatNeverChanges_IsNotABatteryLap()
    {
        // 잔량 채널은 있지만 랩 내내 가득(배터리를 쓰지 않는 Time Trial) → 배터리 값을 내지 않는다.
        var a = Lap(1, [30_000, 40_000, 30_000], deployJ: [0, 0, 0]);
        var b = Lap(2, [29_500, 40_500, 30_200], deployJ: [0, 0, 0]);
        var laps = new[] { a, b };

        var result = TheoreticalBestCalculator.Compute(laps, TheoreticalBestCalculator.MeasureBudget(laps))!;

        Assert.False(result.HasBattery);
        Assert.Equal(99_500, result.TheoreticalMs);
        Assert.All(result.Segments, s => Assert.Null(s.DeployJ));
    }

    [Fact]
    public void Compute_InvalidLap_DropsOnlyTheSegmentWhereAllWheelsLeftTheTrack()
    {
        var a = Lap(1, [30_000, 40_000, 30_000]);
        // 무효: 구간 2(800~820m)에서 네 바퀴가 자갈 → 구간 2만 빼고 구간 1은 쓴다.
        var cut = Lap(2, [30_100, 39_500, 29_000], valid: false, offTrack: (80, 82));
        // 무효인데 트랙 이탈을 못 찾음 → 어디서 무효가 됐는지 몰라 통째로 뺀다.
        var unknown = Lap(3, [29_000, 39_000, 29_000], valid: false);

        var result = TheoreticalBestCalculator.Compute([a, cut, unknown], budget: null)!;

        Assert.Equal((99_500, 2), (result.TheoreticalMs, result.LapCount));
        Assert.Equal([a.LapId, cut.LapId, a.LapId], result.Segments.Select(s => s.LapId));
    }

    [Fact]
    public void Compute_SampleWhoseTimeGoesBackwards_IsFilledInsteadOfDroppingTheBestLap()
    {
        // 최고 랩의 구간 1 한가운데(표본 50) 시간이 앞 표본보다 줄어든 표본 — 게임이 다른 순간의 값을 섞어 보낸 것.
        // 예전에는 그 구간을 버려 최고 랩의 기준이 사라지고 결과 전체가 null이었다(Spa 예선 실측).
        var a = Lap(1, [30_000, 40_000, 30_000], brokenAt: 50);
        var b = Lap(2, [29_500, 40_500, 30_200]);

        var result = TheoreticalBestCalculator.Compute([a, b], budget: null)!;

        Assert.Equal((a.LapId, 99_500), (result.BestLapId, result.TheoreticalMs));
        Assert.Equal([b.LapId, a.LapId, a.LapId], result.Segments.Select(s => s.LapId));
        Assert.Equal(40_000, result.Segments[1].BestLapTimeMs);
    }

    [Fact]
    public void Compute_NoValidLap_IsNull()
    {
        Assert.Null(TheoreticalBestCalculator.Compute([Lap(1, [30_000, 40_000, 30_000], valid: false, offTrack: (80, 82))], budget: null));
        Assert.Null(TheoreticalBestCalculator.Compute([], budget: null));
    }

    /// <summary>
    /// 구간 시간 [segmentMs]로 달린 랩. 구간 안에서 시간은 고르게 흐르고, 배터리는 구간 앞쪽 절반에서 [deployJ]만큼 줄고 뒤쪽 절반에서 [harvestJ]만큼 는다.
    /// 둘 다 없고 출발 잔량이 가득이면 ERS 채널을 넣지 않는다. [offTrack] 표본 범위에서는 네 바퀴가 자갈 위다.
    /// </summary>
    private static TheoreticalLap Lap(
        int n,
        int[] segmentMs,
        double[]? deployJ = null,
        double[]? harvestJ = null,
        double startJ = FullStoreJ,
        bool valid = true,
        (int From, int To)? offTrack = null,
        int? brokenAt = null)
    {
        int[] edges = [0, FirstBoundary, SecondBoundary, SampleCount - 1];
        var time = new int[SampleCount];
        var store = new double[SampleCount];
        double elapsed = 0, level = startJ;
        store[0] = startJ;
        for (var s = 0; s < segmentMs.Length; s++)
        {
            var (from, to) = (edges[s], edges[s + 1]);
            // 마지막 구간은 결승선(표본 100 자리)까지 — 표본 99는 그 앞 한 칸.
            var span = s == segmentMs.Length - 1 ? to - from + 1 : to - from;
            var half = (to - from) / 2;
            for (var i = from + 1; i <= to; i++)
            {
                time[i] = (int)Math.Round(elapsed + segmentMs[s] * (double)(i - from) / span);
                level += i - from <= half ? -(deployJ?[s] ?? 0) / half : (harvestJ?[s] ?? 0) / (to - from - half);
                store[i] = level;
            }

            elapsed += segmentMs[s];
        }

        if (brokenAt is { } broken)
        {
            time[broken] = time[broken - 1] - 5_000;
        }

        var lateral = Enumerable.Range(0, SampleCount).Select(i => i is >= 30 and <= 40 or >= 70 and <= 78 ? 1.6 : 0).ToArray();
        var surface = Enumerable.Range(0, SampleCount).Select(i => offTrack is { } o && i >= o.From && i <= o.To ? (double)GravelSurface : 0).ToArray();
        var extra = new Dictionary<string, double[]>
        {
            ["gForceLateral"] = lateral,
            ["surfaceTypeFL"] = surface,
            ["surfaceTypeFR"] = surface,
            ["surfaceTypeRL"] = surface,
            ["surfaceTypeRR"] = surface,
        };
        if (deployJ is not null || harvestJ is not null || startJ != FullStoreJ)
        {
            extra["ersStoreEnergy"] = store;
        }

        var zeros = new int[SampleCount];
        var channels = new LapTraceChannels(time, Enumerable.Repeat(200, SampleCount).ToArray(), zeros, zeros, zeros, zeros, zeros, extra);
        return new TheoreticalLap(new Guid(n, 0, 0, new byte[8]), segmentMs.Sum(), valid, Day.AddMinutes(n), ResolutionM, channels);
    }
}
