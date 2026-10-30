namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 스틴트마다 깨끗한 랩(트레이스가 있는 것)의 구간별 측정(<see cref="SegmentMeter"/>)을 랩 평균으로 묶는다(순수 계산).
/// 구간 시간은 랩 번호에 대한 기울기도 낸다(타이어가 닳으며 어느 구간에서 시간을 잃는지) — 실수 한 랩에 흔들리지 않게 두 랩씩 짝지은 기울기의
/// 중앙값(Theil–Sen)을 쓴다. 랩당 바퀴 마모는 앞 랩 끝 → 이 랩 끝
/// 스냅샷 마모 차이(새 타이어로 줄어든 랩은 뺀다), 마찰 일 대비 마모(%/MJ)는 그 랩들의 합으로 낸다.
/// </summary>
internal static class RaceDrivingAnalyzer
{
    private const int MinTrendLaps = 4;

    /// <summary>구간에서 배터리가 바닥났던 랩으로 셀 거리(m).</summary>
    private const double EmptyLapM = 20;

    private const int ValueDecimals = 1;
    private const int AngleDecimals = 2;
    private const int RatioDecimals = 2;
    private const double JoulesPerKilojoule = 1_000;
    private const double JoulesPerMegajoule = 1_000_000;

    public static (IReadOnlyList<RaceStintDrivingDto> Stints, double? WearPctPerMj) Build(
        RaceReviewBuilder.CarRace mine,
        IReadOnlyDictionary<int, RaceTraceLap> traces,
        IReadOnlyList<SegmentRange> segments,
        IReadOnlyDictionary<int, MySessionLap> stored)
    {
        ArgumentNullException.ThrowIfNull(mine);
        ArgumentNullException.ThrowIfNull(traces);
        ArgumentNullException.ThrowIfNull(segments);
        ArgumentNullException.ThrowIfNull(stored);

        var lastLap = mine.Laps.Count == 0 ? 0 : mine.Laps[^1].LapNumber;
        var stints = new List<RaceStintDrivingDto>();
        double wearSum = 0, workSum = 0;
        foreach (var span in mine.Spans)
        {
            var laps = mine.CleanIn(span).Select(l => l.LapNumber).Where(traces.ContainsKey).ToList();
            if (laps.Count == 0)
            {
                continue;
            }

            var loads = laps.Select(n => SegmentMeter.LapTyres(traces[n])).ToList();
            var wear = laps.Select(n => WheelWear(stored, n)).ToList();
            for (var k = 0; k < laps.Count; k++)
            {
                if (wear[k] is { } lapWear && loads[k].WheelWorkJ is { } lapWork)
                {
                    wearSum += lapWear.Sum();
                    workSum += lapWork.Sum();
                }
            }

            stints.Add(new RaceStintDrivingDto(
                span.VisualCompound,
                span.StartLap,
                Math.Min(span.EndLap, lastLap),
                laps,
                MeanWheels(loads.Select(l => l.WheelWorkJ), JoulesPerKilojoule),
                MeanWheels(loads.Select(l => l.PeakSurfaceTempC), 1),
                MeanWheels(loads.Select(l => l.InnerTempC), 1),
                MeanWheels(wear, 1, RatioDecimals),
                segments.Select(s => Aggregate(s.Index, laps.Select(n => (Lap: n, Measured: SegmentMeter.Measure(traces[n], s))).ToList())).ToList()));
        }

        return (stints, workSum > 0 ? Math.Round(wearSum / (workSum / JoulesPerMegajoule), RatioDecimals) : null);
    }

    private static RaceSegmentDrivingDto Aggregate(int index, IReadOnlyList<(int Lap, SegmentLap Measured)> laps)
    {
        var m = laps.Select(l => l.Measured).ToList();
        return new RaceSegmentDrivingDto(
            index,
            RaceReviewBuilder.Round(m.Average(x => x.TimeMs)),
            Trend(laps.Select(l => (l.Lap, (double)l.Measured.TimeMs)).ToList()) is { } trend ? RaceReviewBuilder.Round(trend) : null,
            MeanWheels(m.Select(x => x.WheelWorkJ), JoulesPerKilojoule),
            Math.Round(m.Average(x => x.SteerPct), ValueDecimals),
            Mean(m.Select(x => x.UndersteerDeg), AngleDecimals),
            Mean(m.Select(x => x.LockupM)),
            Mean(m.Select(x => x.WheelspinM)),
            Math.Round(m.Average(x => x.TrailBrakeM), ValueDecimals),
            Math.Round(m.Average(x => x.ThrottleSteerM), ValueDecimals),
            Math.Round(m.Average(x => x.BrakeM), ValueDecimals),
            Mean(m.Select(x => x.KerbM)),
            MeanWheels(m.Select(x => x.PeakSurfaceTempC), 1),
            RaceReviewBuilder.Round(m.Average(x => x.MinSpeedKph)),
            RaceReviewBuilder.Round(m.Average(x => x.EndSpeedKph)),
            Mean(m.Select(x => x.HarvestJ / JoulesPerKilojoule)),
            Mean(m.Select(x => x.DeployJ / JoulesPerKilojoule)),
            Mean(m.Select(x => x.OvertakeM)),
            Mean(m.Select(x => x.NoDeployM)),
            Mean(m.Select(x => x.StoreEndJ / JoulesPerKilojoule)),
            Mean(m.Select(x => x.EmptyM)),
            m.Any(x => x.EmptyM.HasValue) ? m.Count(x => x.EmptyM >= EmptyLapM) : null,
            Math.Round(m.Average(x => x.LiftM), ValueDecimals),
            Mean(m.Select(x => x.FastOvertakeM)));
    }

    /// <summary>[lap]랩 동안 바퀴별 마모(%p) = 이 랩 끝 − 앞 랩 끝. 둘 중 하나라도 모르거나 줄었으면(새 타이어) null.</summary>
    private static double[]? WheelWear(IReadOnlyDictionary<int, MySessionLap> stored, int lap)
    {
        static double[]? Wheels(MySessionLap l)
            => l.Row is { TyreWearEndFrontLeft: { } fl, TyreWearEndFrontRight: { } fr, TyreWearEndRearLeft: { } rl, TyreWearEndRearRight: { } rr }
                ? [fl, fr, rl, rr]
                : null;

        if (!stored.TryGetValue(lap, out var current) || !stored.TryGetValue(lap - 1, out var previous)
            || Wheels(current) is not { } end || Wheels(previous) is not { } start)
        {
            return null;
        }

        var wear = end.Zip(start, (e, s) => e - s).ToArray();
        return wear.Any(w => w < 0) ? null : wear;
    }

    /// <summary>값이 있는 것만의 평균(없으면 null).</summary>
    private static double? Mean(IEnumerable<double?> values, int decimals = ValueDecimals)
    {
        var known = values.OfType<double>().ToList();
        return known.Count == 0 ? null : Math.Round(known.Average(), decimals);
    }

    /// <summary>바퀴 네 개 값 평균을 [scale]로 나눈 값(값이 있는 랩만, 하나도 없으면 null).</summary>
    private static IReadOnlyList<double>? MeanWheels(IEnumerable<double[]?> values, double scale, int decimals = ValueDecimals)
    {
        var known = values.OfType<double[]>().ToList();
        return known.Count == 0
            ? null
            : Enumerable.Range(0, TraceChannelNames.Wheels.Length).Select(w => Math.Round(known.Average(v => v[w]) / scale, decimals)).ToList();
    }

    /// <summary>랩 번호에 대한 Theil–Sen 기울기(서로 다른 두 랩마다 기울기의 중앙값). 점이 <see cref="MinTrendLaps"/>보다 적으면 null.</summary>
    private static double? Trend(IReadOnlyList<(int Lap, double Value)> points)
    {
        if (points.Count < MinTrendLaps)
        {
            return null;
        }

        var slopes = new List<double>();
        for (var i = 0; i < points.Count; i++)
        {
            for (var j = i + 1; j < points.Count; j++)
            {
                if (points[j].Lap != points[i].Lap)
                {
                    slopes.Add((points[j].Value - points[i].Value) / (points[j].Lap - points[i].Lap));
                }
            }
        }

        return slopes.Count == 0 ? null : RaceReviewBuilder.Median(slopes);
    }
}
