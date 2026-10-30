using SimCenter.Application.TrackSamples;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 다른 차들이 랩 구간마다 배터리를 채우고 쓴 양(순수 계산, 모든 차 표본 format 5의 ERS 잔량 kJ). 같은 차의 이웃 표본(시간 간격
/// ≤ <see cref="MaxGapMs"/>, 랩 거리가 앞으로 <see cref="MaxStepM"/> 안, 둘 다 피트 레인 밖)의 잔량 차이를 두 표본 가운데 거리의 구간에 더한다 —
/// 늘면 채움, 줄면 씀. 차마다 결승선 통과 수로 나눠 랩당 값으로 만들고, 구간마다 차들의 중앙값을 낸다.
/// </summary>
internal static class FieldErsProfile
{
    private const int MaxGapMs = 2000;
    private const double MaxStepM = 100;
    private const int ValueDecimals = 1;

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

        var byCar = new Dictionary<int, List<(int TimeMs, float DistanceM, ushort ErsKj, bool InPit)>>();
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

                samples.Add((chunk.TimeMs[i], chunk.LapDistanceM[i], chunk.ErsStoreKj![i], RaceSample.IsInPit(chunk.Status[i])));
            }
        }

        var perCar = new List<(double[] Harvest, double[] Deploy)>();
        foreach (var samples in byCar.Values)
        {
            samples.Sort((a, b) => a.TimeMs.CompareTo(b.TimeMs));
            var harvest = new double[segments.Count];
            var deploy = new double[segments.Count];
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

                var change = b.ErsKj - a.ErsKj;
                if (change > 0)
                {
                    harvest[segment] += change;
                }
                else
                {
                    deploy[segment] -= change;
                }
            }

            if (laps > 0)
            {
                perCar.Add((harvest.Select(h => h / laps).ToArray(), deploy.Select(d => d / laps).ToArray()));
            }
        }

        if (perCar.Count == 0)
        {
            return [];
        }

        return segments
            .Select(s => new FieldSegmentErsDto(
                s.Index,
                Math.Round(RaceReviewBuilder.Median(perCar.Select(c => c.Harvest[s.Index])), ValueDecimals),
                Math.Round(RaceReviewBuilder.Median(perCar.Select(c => c.Deploy[s.Index])), ValueDecimals),
                perCar.Count))
            .ToList();
    }
}
