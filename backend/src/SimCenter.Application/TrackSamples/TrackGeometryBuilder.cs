namespace SimCenter.Application.TrackSamples;

/// <summary>
/// 표본으로 만든 트랙 형상(랩 거리 <see cref="ResolutionM"/>마다 한 칸, 칸 i = 랩 거리 i × 간격 둘레 ±간격/2).
/// 선(X·Z)은 차들이 달린 위치의 중앙값 = 레이싱 라인이고 도로 한가운데가 아니다. 띠는 그 선에서 왼쪽·오른쪽으로 차들이 달린 끝,
/// 연석은 그 쪽 바퀴가 연석을 밟은 적이 있는지(도로 가장자리 단서).
/// </summary>
/// <param name="Y">높이(m). 높이 열이 있는 표본이 없으면 null.</param>
/// <param name="BandLeftM">레이싱 라인에서 왼쪽(진행 방향 기준 법선 (−sin, cos))으로 차들이 달린 끝(m, 0 이상).</param>
/// <param name="BandRightM">오른쪽 끝(m, 0 이상).</param>
public sealed record TrackGeometry(
    double ResolutionM,
    int SampleCount,
    double[] X,
    double[] Z,
    double[]? Y,
    double[] BandLeftM,
    double[] BandRightM,
    bool[] KerbLeft,
    bool[] KerbRight);

/// <summary>모든 차 표본 → 트랙 형상(순수 계산). 서킷은 닫혀 있다고 본다(마지막 칸 다음 = 첫 칸).</summary>
public static class TrackGeometryBuilder
{
    public const double ResolutionM = 5;

    /// <summary>이보다 느린 표본(피트 출구·멈춤)은 뺀다(속도 열이 없으면 모두 쓴다).</summary>
    private const int MinSpeedKph = 30;

    /// <summary>띠 끝: 왼쪽은 오프셋 상위 2%, 오른쪽은 하위 2%(튀는 표본 무시).</summary>
    private const double BandPercentile = 0.98;

    /// <summary>연석 쪽을 정할 때 이보다 레이싱 라인에 가까운 표본은 어느 쪽인지 모호해 뺀다(m).</summary>
    private const double KerbSideMinOffsetM = 0.5;

    /// <summary>레이싱 라인을 고르는 이동 평균 반폭(칸).</summary>
    private const int LineSmoothBins = 2;

    /// <summary>표본이 있는 칸이 이 비율보다 적으면 형상을 만들지 않는다.</summary>
    private const double MinCoverage = 0.5;

    /// <summary>F1 노면 값 가운데 포장 노면(아스팔트 0·연석 1·콘크리트 2·자갈 포장 9·금속 10·홈 패인 노면 11). 잔디·그래블 위 표본은 띠에서 뺀다.</summary>
    private static readonly HashSet<int> PavedSurfaces = [0, 1, 2, 9, 10, 11];

    private const int RumbleSurface = 1;
    private const int WheelCount = 4;
    private const int SurfaceBits = 4;
    private const int SurfaceMask = 0xF;

    private readonly record struct Point(double X, double Z, double? Y, bool Paved, bool Rumble);

    /// <summary>표본이 모자라면(칸의 절반 미만) null.</summary>
    public static TrackGeometry? Build(IReadOnlyList<DecodedTrackSamples> chunks)
    {
        var maxDistance = chunks.SelectMany(c => c.LapDistanceM).DefaultIfEmpty(0).Max();
        if (maxDistance <= 0)
        {
            return null;
        }

        var n = (int)Math.Round(maxDistance / ResolutionM) + 1;
        var bins = Enumerable.Range(0, n).Select(_ => new List<Point>()).ToArray();
        var sampleCount = 0;
        foreach (var chunk in chunks)
        {
            for (var i = 0; i < chunk.Count; i++)
            {
                if (chunk.SpeedKph is { } speed && speed[i] < MinSpeedKph)
                {
                    continue;
                }

                var (paved, rumble) = Wheels(chunk.Surface[i]);
                bins[(int)Math.Round(chunk.LapDistanceM[i] / ResolutionM) % n]
                    .Add(new Point(chunk.X[i], chunk.Z[i], chunk.Y?[i], paved, rumble));
                sampleCount++;
            }
        }

        if (bins.Count(b => b.Count > 0) < n * MinCoverage)
        {
            return null;
        }

        var x = new double?[n];
        var z = new double?[n];
        var y = new double?[n];
        for (var k = 0; k < n; k++)
        {
            if (bins[k].Count == 0)
            {
                continue;
            }

            // 선은 도로 위 표본으로 잡는다(잔디·그래블로 나간 차가 선을 끌지 않게). 도로 위 표본이 없는 칸만 모두 쓴다.
            var onRoad = bins[k].Where(p => p.Paved).ToList();
            var points = onRoad.Count > 0 ? onRoad : bins[k];
            x[k] = Median(points.Select(p => p.X));
            z[k] = Median(points.Select(p => p.Z));
            var heights = bins[k].Where(p => p.Y.HasValue).Select(p => p.Y!.Value).ToList();
            y[k] = heights.Count == 0 ? null : Median(heights);
        }

        var lineX = Smooth(FillGaps(x));
        var lineZ = Smooth(FillGaps(z));
        var hasHeights = y.Any(v => v.HasValue);
        var heightsOut = hasHeights ? Smooth(FillGaps(y)) : null;

        var bandLeft = new double[n];
        var bandRight = new double[n];
        var kerbLeft = new bool[n];
        var kerbRight = new bool[n];
        for (var k = 0; k < n; k++)
        {
            var tx = lineX[(k + 1) % n] - lineX[(k - 1 + n) % n];
            var tz = lineZ[(k + 1) % n] - lineZ[(k - 1 + n) % n];
            var length = Math.Sqrt(tx * tx + tz * tz);
            if (length == 0)
            {
                continue;
            }

            // 왼쪽 법선(앱의 서킷 그림과 같은 규칙).
            var nx = -tz / length;
            var nz = tx / length;
            var offsets = new List<double>();
            foreach (var p in bins[k])
            {
                var offset = (p.X - lineX[k]) * nx + (p.Z - lineZ[k]) * nz;
                if (p.Paved)
                {
                    offsets.Add(offset);
                }

                if (p.Rumble && offset > KerbSideMinOffsetM)
                {
                    kerbLeft[k] = true;
                }
                else if (p.Rumble && offset < -KerbSideMinOffsetM)
                {
                    kerbRight[k] = true;
                }
            }

            if (offsets.Count == 0)
            {
                continue;
            }

            offsets.Sort();
            bandLeft[k] = Math.Max(0, offsets[Math.Min(offsets.Count - 1, (int)(offsets.Count * BandPercentile))]);
            bandRight[k] = Math.Max(0, -offsets[(int)(offsets.Count * (1 - BandPercentile))]);
        }

        return new TrackGeometry(ResolutionM, sampleCount, lineX, lineZ, heightsOut, bandLeft, bandRight, kerbLeft, kerbRight);
    }

    private static (bool Paved, bool Rumble) Wheels(ushort packed)
    {
        var paved = true;
        var rumble = false;
        for (var w = 0; w < WheelCount; w++)
        {
            var surface = (packed >> (w * SurfaceBits)) & SurfaceMask;
            paved &= PavedSurfaces.Contains(surface);
            rumble |= surface == RumbleSurface;
        }

        return (paved, rumble);
    }

    private static double Median(IEnumerable<double> values)
    {
        var sorted = values.OrderBy(v => v).ToList();
        return sorted[sorted.Count / 2];
    }

    /// <summary>빈 칸을 앞뒤로 가장 가까운 값 사이 직선으로 메운다(서킷이 닫혀 있어 끝과 처음이 이어진다).</summary>
    private static double[] FillGaps(double?[] values)
    {
        var n = values.Length;
        var known = Enumerable.Range(0, n).Where(k => values[k].HasValue).ToList();
        var filled = new double[n];
        for (var k = 0; k < n; k++)
        {
            if (values[k] is { } value)
            {
                filled[k] = value;
                continue;
            }

            var before = known.LastOrDefault(j => j < k, known[^1] - n);
            var after = known.FirstOrDefault(j => j > k, known[0] + n);
            var t = (double)(k - before) / (after - before);
            var from = values[(before + n) % n]!.Value;
            var to = values[after % n]!.Value;
            filled[k] = from + (to - from) * t;
        }

        return filled;
    }

    private static double[] Smooth(double[] values)
    {
        var n = values.Length;
        var smoothed = new double[n];
        for (var k = 0; k < n; k++)
        {
            var sum = 0.0;
            for (var j = -LineSmoothBins; j <= LineSmoothBins; j++)
            {
                sum += values[(k + j + n) % n];
            }

            smoothed[k] = sum / (LineSmoothBins * 2 + 1);
        }

        return smoothed;
    }
}
