using SimCenter.Application.TrackSamples;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 다른 차들이 랩 구간마다 배터리를 채우고 쓴 양(순수 계산, 모든 차 표본 format 5의 ERS 잔량 kJ). 같은 차의 이웃 표본(시간 간격
/// ≤ <see cref="MaxGapMs"/>, 랩 거리가 앞으로 <see cref="MaxStepM"/> 안, 둘 다 피트 레인 밖)의 잔량 차이를 두 표본 가운데 거리의 구간에 더한다 —
/// 늘면 채움, 줄면 씀. 같은 이웃 표본으로 구간 통과 시간과 스로틀을 완전히 뗀(뒤 표본 스로틀 &lt; <see cref="LiftThrottlePct"/>%) 거리도 더한다.
/// 차마다 결승선 통과 수로 나눠 랩당 값으로 만들고, 구간마다 차들의 중앙값을 낸다.
/// Agent는 초당 10번 고정 표본 사이에 노면 변화·충격·추월 표본을 끼워 넣는데, 그 표본의 잔량은 앞뒤와 수백 kJ씩 어긋나
/// 위아래로 튈 때마다 채움·씀이 둘 다 쌓인다(스파 레이스 실측: 내 차 표본으로 재면 랩당 4.0배, 내 트레이스로는 1.9배).
/// 그래서 고정 간격 표본만 쓰고(<see cref="RegularIntervalMs"/>), 그래도 앞뒤 중앙값과 <see cref="SpikeKj"/>보다 벌어진 표본은 중앙값으로 바꾼다.
/// </summary>
internal static class FieldErsProfile
{
    private const int MaxGapMs = 2000;
    private const double MaxStepM = 100;
    private const int ValueDecimals = 1;
    private const int LiftThrottlePct = 5;

    /// <summary>고정 표본(100ms)으로 보는 앞 표본과의 최소 간격 — Agent의 허용 오차 5ms를 뺀 값.</summary>
    private const int RegularIntervalMs = 95;

    /// <summary>앞뒤 셋의 중앙값과 이보다 벌어진 잔량(kJ)은 튄 값으로 본다. 100ms 동안 실제로 바뀌는 양(최대 약 35kJ)보다 크게 둔다.</summary>
    private const int SpikeKj = 50;

    private readonly record struct FieldSample(int TimeMs, float DistanceM, ushort ErsKj, bool InPit, int? Throttle);

    public static IReadOnlyList<FieldSegmentErsDto> Build(
        IReadOnlyList<DecodedTrackSamples> chunks,
        int playerCarIndex,
        IReadOnlyList<SegmentRange> segments,
        int resolutionM,
        int sampleCount,
        double trackLengthM)
    {
        ArgumentNullException.ThrowIfNull(chunks);
        ArgumentNullException.ThrowIfNull(segments);
        if (segments.Count == 0 || resolutionM <= 0 || sampleCount <= 0 || trackLengthM <= 0)
        {
            return [];
        }

        var segmentAt = Enumerable.Repeat(-1, sampleCount).ToArray();
        foreach (var segment in segments)
        {
            foreach (var (from, to) in segment.Runs(sampleCount))
            {
                for (var i = from; i <= to; i++)
                {
                    segmentAt[i] = segment.Index;
                }
            }
        }

        var byCar = new Dictionary<int, List<FieldSample>>();
        foreach (var chunk in chunks.Where(c => c.ErsStoreKj is not null))
        {
            for (var i = 0; i < chunk.Count; i++)
            {
                int car = chunk.CarIndex[i];
                if (car == playerCarIndex)
                {
                    continue;
                }

                if (!byCar.TryGetValue(car, out var samples))
                {
                    byCar[car] = samples = [];
                }

                samples.Add(new FieldSample(chunk.TimeMs[i], chunk.LapDistanceM[i], chunk.ErsStoreKj![i], RaceSample.IsInPit(chunk.Status[i]), chunk.Throttle?[i]));
            }
        }

        var hasThrottle = chunks.Any(c => c.ErsStoreKj is not null && c.Throttle is not null);
        var perCar = new List<(double[] Harvest, double[] Deploy, double[] Lift, double[] Time)>();
        foreach (var all in byCar.Values)
        {
            all.Sort((a, b) => a.TimeMs.CompareTo(b.TimeMs));
            var samples = RegularSamples(all);
            var store = WithoutSpikes(samples.Select(s => (int)s.ErsKj).ToList());
            var harvest = new double[segments.Count];
            var deploy = new double[segments.Count];
            var lift = new double[segments.Count];
            var time = new double[segments.Count];
            var laps = 0;
            for (var k = 1; k < samples.Count; k++)
            {
                var a = samples[k - 1];
                var b = samples[k];
                if (b.TimeMs - a.TimeMs > MaxGapMs)
                {
                    continue;
                }

                if (a.DistanceM - b.DistanceM > trackLengthM / 2)
                {
                    laps++;
                    continue;
                }

                var step = b.DistanceM - a.DistanceM;
                if (step <= 0 || step > MaxStepM || a.InPit || b.InPit)
                {
                    continue;
                }

                var index = Math.Clamp((int)((a.DistanceM + b.DistanceM) / 2 / resolutionM), 0, sampleCount - 1);
                var segment = segmentAt[index];
                if (segment < 0)
                {
                    continue;
                }

                var change = store[k] - store[k - 1];
                if (change > 0)
                {
                    harvest[segment] += change;
                }
                else
                {
                    deploy[segment] -= change;
                }

                time[segment] += b.TimeMs - a.TimeMs;
                if (b.Throttle < LiftThrottlePct)
                {
                    lift[segment] += step;
                }
            }

            if (laps > 0)
            {
                perCar.Add((
                    harvest.Select(h => h / laps).ToArray(),
                    deploy.Select(d => d / laps).ToArray(),
                    lift.Select(l => l / laps).ToArray(),
                    time.Select(t => t / laps).ToArray()));
            }
        }

        if (perCar.Count == 0)
        {
            return [];
        }

        double MedianOf(Func<(double[] Harvest, double[] Deploy, double[] Lift, double[] Time), double> of)
            => RaceReviewBuilder.Median(perCar.Select(of));

        return segments
            .Select(s => new FieldSegmentErsDto(
                s.Index,
                Math.Round(MedianOf(c => c.Harvest[s.Index]), ValueDecimals),
                Math.Round(MedianOf(c => c.Deploy[s.Index]), ValueDecimals),
                perCar.Count,
                hasThrottle ? Math.Round(MedianOf(c => c.Lift[s.Index]), ValueDecimals) : null,
                RaceReviewBuilder.Round(MedianOf(c => c.Time[s.Index]))))
            .ToList();
    }

    /// <summary>시간순 표본에서 앞에 남긴 표본보다 <see cref="RegularIntervalMs"/> 이상 뒤인 표본만(첫 표본은 남긴다).</summary>
    private static List<FieldSample> RegularSamples(List<FieldSample> samples)
    {
        var regular = new List<FieldSample>(samples.Count);
        int? lastMs = null;
        foreach (var sample in samples)
        {
            if (lastMs is { } last && sample.TimeMs - last < RegularIntervalMs)
            {
                continue;
            }

            regular.Add(sample);
            lastMs = sample.TimeMs;
        }

        return regular;
    }

    /// <summary>앞뒤 셋의 중앙값과 <see cref="SpikeKj"/>보다 벌어진 가운데 값을 그 중앙값으로 바꾼다(양 끝은 그대로).</summary>
    private static int[] WithoutSpikes(List<int> store)
    {
        var result = store.ToArray();
        for (var i = 1; i < store.Count - 1; i++)
        {
            var median = Math.Max(Math.Min(store[i - 1], store[i]), Math.Min(Math.Max(store[i - 1], store[i]), store[i + 1]));
            if (Math.Abs(store[i] - median) > SpikeKj)
            {
                result[i] = median;
            }
        }

        return result;
    }
}
