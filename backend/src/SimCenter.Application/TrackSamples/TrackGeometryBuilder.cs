namespace SimCenter.Application.TrackSamples;

/// <summary>
/// 표본으로 만든 트랙 형상(랩 거리 <see cref="ResolutionM"/>마다 한 칸, 칸 i = 랩 거리 i × 간격 둘레 ±간격/2).
/// 선(X·Z)은 차들이 달린 위치의 중앙값 = 레이싱 라인이고 도로 한가운데가 아니다. 띠는 그 선에서 왼쪽·오른쪽으로 차들이 달린 끝,
/// 연석은 그 쪽 바퀴가 연석을 밟은 적이 있는지(도로 가장자리 단서).
/// 가장자리·연석 바깥·도달 폭도 레이싱 라인에서 그 쪽으로 잰 거리(m)이고, 그런 표본이 없는 칸은 0이다.
/// </summary>
/// <param name="Y">높이(m). 높이 열이 있는 표본이 없으면 null.</param>
/// <param name="BandLeftM">레이싱 라인에서 왼쪽(진행 방향 기준 법선 (−sin, cos))으로 차들이 달린 끝(m, 0 이상).</param>
/// <param name="BandRightM">오른쪽 끝(m, 0 이상).</param>
/// <param name="EdgeLeftM">
/// 네 바퀴가 모두 아스팔트(연석이 아닌 포장 노면)에 있던 차의 바깥 바퀴가 닿은 먼 자리 = 아스팔트 왼쪽 가장자리.
/// 표본이 많은 칸은 가장 먼 1%를 뺀다(포장 런오프·탈출로로 한두 번 나간 차가 도로를 부풀리지 않게).
/// </param>
/// <param name="KerbOuterLeftM">연석을 밟은 차(네 바퀴 모두 포장 노면)의 바깥 바퀴가 닿은 먼 자리(같은 규칙) = 왼쪽 연석 바깥 끝.</param>
/// <param name="ReachLeftM">차 몸체가 닿은 가장 먼 자리: 잔디·그래블로 나간 차, 느리거나 멈춘 차까지 모두. 방호벽은 이보다 바깥에 있다.</param>
/// <param name="PitX">피트 레인 선(피트 입구 → 출구 순, 피트 레인 표본의 칸별 중앙값). 피트 레인 표본이 모자라면 null.</param>
public sealed record TrackGeometry(
    double ResolutionM,
    int SampleCount,
    double[] X,
    double[] Z,
    double[]? Y,
    double[] BandLeftM,
    double[] BandRightM,
    bool[] KerbLeft,
    bool[] KerbRight,
    double[] EdgeLeftM,
    double[] EdgeRightM,
    double[] KerbOuterLeftM,
    double[] KerbOuterRightM,
    double[] ReachLeftM,
    double[] ReachRightM,
    double[]? PitX = null,
    double[]? PitZ = null,
    double[]? PitY = null);

/// <summary>
/// 모든 차 표본 → 트랙 형상(순수 계산). 서킷은 닫혀 있다고 본다(마지막 칸 다음 = 첫 칸).
/// 피트 레인에 있는 표본(상태 비트의 pitStatus ≠ 0)은 도로에서 빼고 피트 레인 선으로 따로 모은다.
/// </summary>
public static class TrackGeometryBuilder
{
    public const double ResolutionM = 5;

    /// <summary>이보다 느린 표본(피트 출구·멈춤)은 선·띠·가장자리에서 뺀다(속도 열이 없으면 모두 쓴다). 도달 폭에는 넣는다 — 멈춘 차도 방호벽 안에 있어야 한다.</summary>
    private const int MinSpeedKph = 30;

    /// <summary>띠 끝: 왼쪽은 오프셋 상위 2%, 오른쪽은 하위 2%(튀는 표본 무시).</summary>
    private const double BandPercentile = 0.98;

    /// <summary>
    /// 연석 쪽을 정할 때 이보다 레이싱 라인에 가까운 표본은 어느 쪽인지 모호하다(m). 그 칸이 이보다 급하게(1/m) 굽으면
    /// 굽은 안쪽 연석(에이펙스 — 레이싱 라인이 연석을 밟고 지난다)으로 보고, 아니면 뺀다.
    /// </summary>
    private const double KerbSideMinOffsetM = 0.5;
    private const double ApexKerbMinCurvature = 0.008;

    /// <summary>곡률을 재는 앞뒤 칸 수(진행 방향 차이 / 거리).</summary>
    private const int CurvatureBins = 2;

    /// <summary>
    /// 피트 레인에 있던 순간에서 이 시간(ms) 안의 같은 차 표본은 피트 입구·출구 길(도로 옆에 붙어 있다 — 모나코 1번 코너 안쪽 피트 출구)로
    /// 보고 선·띠·가장자리·연석에서 뺀다. 방호벽 자리(도달 폭)에는 넣는다.
    /// </summary>
    private const int PitMarginMs = 8_000;

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

    /// <summary>상태 비트의 pitStatus(bit3~4).</summary>
    private const int PitStatusShift = 3;
    private const int PitStatusMask = 0x3;

    /// <summary>피트 레인 선: 이보다 느린 표본(박스에 선 차)은 빼고, 표본이 이만큼 있는 칸만 쓰고, 칸이 이만큼 안 되면 만들지 않는다.</summary>
    private const int MinPitSpeedKph = 10;
    private const int MinPitBinSamples = 3;
    private const int MinPitBins = 10;

    /// <summary>
    /// 가장자리·연석 바깥 끝: 칸 표본의 바퀴 자리 가운데 이 비율 위치(가장 먼 1%는 런오프·탈출로로 잠깐 나간 차로 보고 뺀다).
    /// 표본이 100개 이하인 칸은 가장 먼 자리 그대로다.
    /// </summary>
    private const double EdgePercentile = 0.99;

    /// <summary>바퀴: 차 가운데에서 바깥 바퀴 바깥 면까지 옆 거리(m)·앞뒤 바퀴 축까지 거리(m).</summary>
    private const double WheelOuterHalfWidthM = 1.0;
    private const double WheelHalfBaseM = 1.8;

    /// <summary>차 몸체 반폭·반길이(m, 앱 리플레이가 그리는 차와 같다). 방향을 모르는 표본(멈춘 차)은 어느 쪽으로든 대각선 반길이만큼 닿는다고 본다.</summary>
    private const double BodyHalfWidthM = 1.0;
    private const double BodyHalfLengthM = 2.8;
    private static readonly double BodyHalfDiagonalM = Math.Sqrt(BodyHalfWidthM * BodyHalfWidthM + BodyHalfLengthM * BodyHalfLengthM);

    /// <summary>
    /// 진행 방향은 같은 차의 바로 앞·뒤 표본(이 시간 ms 안)으로 잰다. 이보다 덜 움직였으면(m) 멈춘 차로,
    /// 이보다 빠르면(m/s) 끊긴 표본(플래시백·되돌리기)으로 보고 방향을 모른다고 둔다.
    /// </summary>
    private const int MaxHeadingGapMs = 600;
    private const double MinHeadingStepM = 0.3;
    private const double MaxSpeedMps = 120;
    private const double MsPerSecond = 1000;

    /// <summary>레이싱 라인에서 이보다 먼(m) 표본은 그 칸 자리가 아니라고 보고(랩 거리와 위치가 어긋난 표본) 가장자리·도달 폭에서 뺀다.</summary>
    private const double MaxLateralM = 100;

    /// <param name="Fast">[MinSpeedKph] 이상(선·띠·가장자리에 쓴다).</param>
    /// <param name="NearPit">피트 레인을 드나드는 길 위([PitMarginMs] 안) — 도로 모양에는 쓰지 않는다.</param>
    /// <param name="Heading">진행 방향(단위 벡터, X·Z). 모르면 null.</param>
    private readonly record struct Point(
        double X, double Z, double? Y, bool Paved, bool Rumble, bool Fast, bool NearPit, (double X, double Z)? Heading)
    {
        /// <summary>도로 모양(선·띠·가장자리·연석)에 쓰는 표본.</summary>
        public bool Shapes => Fast && !NearPit;
    }

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
        var pitBins = Enumerable.Range(0, n).Select(_ => new List<Point>()).ToArray();
        var sampleCount = 0;
        var timelines = Timelines(chunks);
        var pitTimes = PitTimes(chunks, timelines);
        for (var c = 0; c < chunks.Count; c++)
        {
            var chunk = chunks[c];
            var headings = Headings(chunk);
            for (var i = 0; i < chunk.Count; i++)
            {
                var bin = (int)Math.Round(chunk.LapDistanceM[i] / ResolutionM) % n;
                if (InPit(chunk, i))
                {
                    if (chunk.SpeedKph is not { } pitSpeed || pitSpeed[i] >= MinPitSpeedKph)
                    {
                        pitBins[bin].Add(new Point(chunk.X[i], chunk.Z[i], chunk.Y?[i], true, false, true, false, null));
                    }

                    continue;
                }

                var fast = chunk.SpeedKph is not { } speed || speed[i] >= MinSpeedKph;
                var (paved, rumble) = Wheels(chunk.Surface[i]);
                var nearPit = pitTimes.TryGetValue((timelines[c], chunk.CarIndex[i]), out var times) && Near(times, chunk.TimeMs[i]);
                bins[bin].Add(new Point(chunk.X[i], chunk.Z[i], chunk.Y?[i], paved, rumble, fast, nearPit, headings[i]));
                if (fast)
                {
                    sampleCount++;
                }
            }
        }

        if (bins.Count(b => b.Any(p => p.Fast)) < n * MinCoverage)
        {
            return null;
        }

        var x = new double?[n];
        var z = new double?[n];
        var y = new double?[n];
        for (var k = 0; k < n; k++)
        {
            // 피트를 드나드는 차만 지난 칸이면 그 차들로라도 선을 잡는다.
            var moving = bins[k].Where(p => p.Shapes).ToList();
            if (moving.Count == 0)
            {
                moving = bins[k].Where(p => p.Fast).ToList();
            }

            if (moving.Count == 0)
            {
                continue;
            }

            // 선은 도로 위 표본으로 잡는다(잔디·그래블로 나간 차가 선을 끌지 않게). 도로 위 표본이 없는 칸만 모두 쓴다.
            var onRoad = moving.Where(p => p.Paved).ToList();
            var points = onRoad.Count > 0 ? onRoad : moving;
            x[k] = Median(points.Select(p => p.X));
            z[k] = Median(points.Select(p => p.Z));
            var heights = moving.Where(p => p.Y.HasValue).Select(p => p.Y!.Value).ToList();
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
        var edgeLeft = new double[n];
        var edgeRight = new double[n];
        var kerbOuterLeft = new double[n];
        var kerbOuterRight = new double[n];
        var tarmacWheels = (Left: new List<double>(), Right: new List<double>());
        var kerbWheels = (Left: new List<double>(), Right: new List<double>());
        var reachLeft = new double[n];
        var reachRight = new double[n];
        var curvatures = Curvatures(lineX, lineZ);
        for (var k = 0; k < n; k++)
        {
            var tx = lineX[(k + 1) % n] - lineX[(k - 1 + n) % n];
            var tz = lineZ[(k + 1) % n] - lineZ[(k - 1 + n) % n];
            var length = Math.Sqrt(tx * tx + tz * tz);
            if (length == 0)
            {
                continue;
            }

            var ux = tx / length;
            var uz = tz / length;

            // 왼쪽 법선(앱의 서킷 그림과 같은 규칙).
            var nx = -uz;
            var nz = ux;
            var offsets = new List<double>();
            tarmacWheels.Left.Clear();
            tarmacWheels.Right.Clear();
            kerbWheels.Left.Clear();
            kerbWheels.Right.Clear();
            foreach (var p in bins[k])
            {
                var offset = (p.X - lineX[k]) * nx + (p.Z - lineZ[k]) * nz;
                var inStretch = Math.Abs(offset) <= MaxLateralM;
                if (inStretch)
                {
                    var body = Extent(p.Heading, ux, uz, BodyHalfWidthM, BodyHalfLengthM) ?? BodyHalfDiagonalM;
                    reachLeft[k] = Math.Max(reachLeft[k], offset + body);
                    reachRight[k] = Math.Max(reachRight[k], -offset + body);
                }

                if (!p.Shapes)
                {
                    continue;
                }

                if (p.Paved)
                {
                    offsets.Add(offset);
                }

                var kerbSide = !p.Rumble ? 0
                    : offset > KerbSideMinOffsetM ? 1
                    : offset < -KerbSideMinOffsetM ? -1
                    : Math.Abs(curvatures[k]) >= ApexKerbMinCurvature ? Math.Sign(curvatures[k])
                    : 0;
                if (kerbSide > 0)
                {
                    kerbLeft[k] = true;
                }
                else if (kerbSide < 0)
                {
                    kerbRight[k] = true;
                }

                // 네 바퀴가 모두 포장 노면이면 바깥 바퀴가 닿은 자리까지가 도로다. 연석을 밟은 표본은 연석 바깥 끝으로 따로 모은다.
                if (p.Paved && inStretch)
                {
                    var wheel = Extent(p.Heading, ux, uz, WheelOuterHalfWidthM, WheelHalfBaseM) ?? WheelOuterHalfWidthM;
                    var wheels = p.Rumble ? kerbWheels : tarmacWheels;
                    wheels.Left.Add(offset + wheel);
                    wheels.Right.Add(-offset + wheel);
                }
            }

            edgeLeft[k] = FarEnd(tarmacWheels.Left);
            edgeRight[k] = FarEnd(tarmacWheels.Right);
            kerbOuterLeft[k] = FarEnd(kerbWheels.Left);
            kerbOuterRight[k] = FarEnd(kerbWheels.Right);

            if (offsets.Count == 0)
            {
                continue;
            }

            offsets.Sort();
            bandLeft[k] = Math.Max(0, offsets[Math.Min(offsets.Count - 1, (int)(offsets.Count * BandPercentile))]);
            bandRight[k] = Math.Max(0, -offsets[(int)(offsets.Count * (1 - BandPercentile))]);
        }

        var pit = PitLane(pitBins);
        return new TrackGeometry(
            ResolutionM, sampleCount, lineX, lineZ, heightsOut, bandLeft, bandRight, kerbLeft, kerbRight,
            edgeLeft, edgeRight, kerbOuterLeft, kerbOuterRight, reachLeft, reachRight, pit?.X, pit?.Z, pit?.Y);
    }

    /// <summary>칸마다 선의 곡률(1/m, + = 왼쪽으로 굽는다): 앞뒤 [CurvatureBins]칸 진행 방향 차이 / 거리.</summary>
    private static double[] Curvatures(double[] lineX, double[] lineZ)
    {
        var n = lineX.Length;
        double Heading(int k) => Math.Atan2(lineZ[(k + 1) % n] - lineZ[(k - 1 + n) % n], lineX[(k + 1) % n] - lineX[(k - 1 + n) % n]);
        var curvatures = new double[n];
        for (var k = 0; k < n; k++)
        {
            var turn = Heading((k + CurvatureBins) % n) - Heading((k - CurvatureBins + n) % n);
            turn = Math.IEEERemainder(turn, 2 * Math.PI);
            curvatures[k] = turn / (2 * CurvatureBins * ResolutionM);
        }

        return curvatures;
    }

    private static bool InPit(DecodedTrackSamples chunk, int i) => ((chunk.Status[i] >> PitStatusShift) & PitStatusMask) != 0;

    /// <summary>조각마다 세션 시간 줄기 번호: 앞 조각보다 시간이 뒤로 가면(다른 세션·되돌리기) 새 줄기로 본다.</summary>
    private static int[] Timelines(IReadOnlyList<DecodedTrackSamples> chunks)
    {
        var timelines = new int[chunks.Count];
        var timeline = 0;
        int? last = null;
        for (var c = 0; c < chunks.Count; c++)
        {
            var times = chunks[c].TimeMs;
            if (times.Length > 0)
            {
                if (last is { } previous && times[0] < previous)
                {
                    timeline++;
                }

                last = times[^1];
            }

            timelines[c] = timeline;
        }

        return timelines;
    }

    /// <summary>줄기·차마다 피트 레인에 있던 시각(정렬). 조각 경계를 넘어 드나든 차도 같은 줄기면 이어서 본다.</summary>
    private static Dictionary<(int Timeline, byte Car), List<int>> PitTimes(IReadOnlyList<DecodedTrackSamples> chunks, int[] timelines)
    {
        var pitTimes = new Dictionary<(int Timeline, byte Car), List<int>>();
        for (var c = 0; c < chunks.Count; c++)
        {
            var chunk = chunks[c];
            for (var i = 0; i < chunk.Count; i++)
            {
                if (!InPit(chunk, i))
                {
                    continue;
                }

                var key = (timelines[c], chunk.CarIndex[i]);
                if (!pitTimes.TryGetValue(key, out var times))
                {
                    times = [];
                    pitTimes[key] = times;
                }

                times.Add(chunk.TimeMs[i]);
            }
        }

        foreach (var times in pitTimes.Values)
        {
            times.Sort();
        }

        return pitTimes;
    }

    /// <summary>정렬된 피트 레인 시각 가운데 <paramref name="time"/> ± <see cref="PitMarginMs"/> 안에 있는 것이 있는지.</summary>
    private static bool Near(List<int> pitTimes, int time)
    {
        var i = pitTimes.BinarySearch(time - PitMarginMs);
        if (i < 0)
        {
            i = ~i;
        }

        return i < pitTimes.Count && pitTimes[i] <= time + PitMarginMs;
    }

    /// <summary>바퀴 자리 가운데 <see cref="EdgePercentile"/> 위치(0 이상). 없으면 0.</summary>
    private static double FarEnd(List<double> reaches)
    {
        if (reaches.Count == 0)
        {
            return 0;
        }

        reaches.Sort();
        return Math.Max(0, reaches[Math.Min(reaches.Count - 1, (int)(reaches.Count * EdgePercentile))]);
    }

    /// <summary>
    /// 차 가운데에서 트랙 옆 방향(왼쪽·오른쪽 같다)으로 닿는 거리: 반폭 × |cos θ| + 반길이 × |sin θ|
    /// (θ = 진행 방향과 트랙 방향 (<paramref name="ux"/>, <paramref name="uz"/>) 사이 각). 방향을 모르면 null.
    /// </summary>
    private static double? Extent((double X, double Z)? heading, double ux, double uz, double halfWidth, double halfLength)
        => heading is { } h
            ? halfWidth * Math.Abs(h.X * ux + h.Z * uz) + halfLength * Math.Abs(h.Z * ux - h.X * uz)
            : null;

    /// <summary>표본마다 진행 방향(단위 벡터, X·Z): 같은 조각 안 같은 차의 바로 앞·뒤 표본을 잇는다. 잴 수 없으면 null.</summary>
    private static (double X, double Z)?[] Headings(DecodedTrackSamples chunk)
    {
        var headings = new (double X, double Z)?[chunk.Count];
        var byCar = new Dictionary<byte, List<int>>();
        for (var i = 0; i < chunk.Count; i++)
        {
            if (!byCar.TryGetValue(chunk.CarIndex[i], out var samples))
            {
                samples = [];
                byCar[chunk.CarIndex[i]] = samples;
            }

            samples.Add(i);
        }

        foreach (var samples in byCar.Values)
        {
            for (var j = 0; j < samples.Count; j++)
            {
                var from = j > 0 && Follows(chunk, samples[j - 1], samples[j]) ? samples[j - 1] : samples[j];
                var to = j + 1 < samples.Count && Follows(chunk, samples[j], samples[j + 1]) ? samples[j + 1] : samples[j];
                if (from == to)
                {
                    continue;
                }

                var dx = (double)chunk.X[to] - chunk.X[from];
                var dz = (double)chunk.Z[to] - chunk.Z[from];
                var step = Math.Sqrt(dx * dx + dz * dz);
                var seconds = (chunk.TimeMs[to] - chunk.TimeMs[from]) / MsPerSecond;
                if (step >= MinHeadingStepM && step <= MaxSpeedMps * seconds)
                {
                    headings[samples[j]] = (dx / step, dz / step);
                }
            }
        }

        return headings;
    }

    /// <summary><paramref name="next"/>가 같은 차 <paramref name="previous"/> 바로 뒤에 이어진 표본인지(시간이 앞으로 가고 <see cref="MaxHeadingGapMs"/> 안).</summary>
    private static bool Follows(DecodedTrackSamples chunk, int previous, int next)
    {
        var gap = chunk.TimeMs[next] - chunk.TimeMs[previous];
        return gap > 0 && gap <= MaxHeadingGapMs;
    }

    /// <summary>
    /// 피트 레인 표본 칸 → 피트 입구에서 출구로 가는 선. 칸은 랩 거리 순이고 피트 레인이 출발선을 넘을 수 있어(모나코),
    /// 표본 칸 사이 가장 긴 빈 구간 바로 뒤를 피트 입구로 본다.
    /// </summary>
    private static (double[] X, double[] Z, double[]? Y)? PitLane(List<Point>[] bins)
    {
        var n = bins.Length;
        var used = Enumerable.Range(0, n).Where(k => bins[k].Count >= MinPitBinSamples).ToList();
        if (used.Count < MinPitBins)
        {
            return null;
        }

        var start = 0;
        var longestGap = -1;
        for (var j = 0; j < used.Count; j++)
        {
            var next = used[(j + 1) % used.Count];
            var gap = (next - used[j] + n) % n;
            if (gap > longestGap)
            {
                longestGap = gap;
                start = (j + 1) % used.Count;
            }
        }

        var ordered = Enumerable.Range(0, used.Count).Select(j => bins[used[(start + j) % used.Count]]).ToList();
        var x = Smooth(ordered.Select(b => Median(b.Select(p => p.X))).ToArray(), closed: false);
        var z = Smooth(ordered.Select(b => Median(b.Select(p => p.Z))).ToArray(), closed: false);
        var hasHeights = ordered.All(b => b.Any(p => p.Y.HasValue));
        var y = hasHeights
            ? Smooth(ordered.Select(b => Median(b.Where(p => p.Y.HasValue).Select(p => p.Y!.Value))).ToArray(), closed: false)
            : null;
        return (x, z, y);
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

    /// <summary>이동 평균. 닫힌 선은 끝과 처음이 이어지고, 열린 선(피트 레인)은 끝에 가까울수록 반폭을 줄여 양 끝 점은 그대로 둔다.</summary>
    private static double[] Smooth(double[] values, bool closed = true)
    {
        var n = values.Length;
        var smoothed = new double[n];
        for (var k = 0; k < n; k++)
        {
            var half = closed ? LineSmoothBins : Math.Min(LineSmoothBins, Math.Min(k, n - 1 - k));
            var sum = 0.0;
            for (var j = -half; j <= half; j++)
            {
                sum += values[(k + j + n) % n];
            }

            smoothed[k] = sum / (half * 2 + 1);
        }

        return smoothed;
    }
}
