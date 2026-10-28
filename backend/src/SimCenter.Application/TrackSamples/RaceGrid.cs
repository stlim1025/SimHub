namespace SimCenter.Application.TrackSamples;

/// <summary>
/// 출발 그리드 다시 만들기(순수 계산). 옛 에이전트는 출발선을 처음 넘기 전(그리드) 표본을 남기지 않아, 차들이 이미 달리는 모습부터 시작한다.
/// 소등 시각을 알면 차마다 첫 표본(출발선 직후의 속도)으로 그리드 거리를 거꾸로 구해(정지 → 등가속, 거리 = 속도 × 시간 ÷ 2)
/// 소등 몇 초 전부터 그리드에 정렬해 서 있다가 출발하는 표본을 앞에 붙인다. 그리드 칸은 출발 순서대로 왼쪽·오른쪽을 번갈아 선다.
/// 위치는 모든 차가 랩 끝(출발선 앞) 직선을 달린 자리의 중앙값 선을 따른다. 소등 전부터 표본이 있는 차(새 에이전트)는 그대로 둔다.
/// </summary>
public static class RaceGrid
{
    /// <summary>소등 전 그리드에 서 있는 시간(ms)·만든 표본 간격(ms).</summary>
    public const int HoldMs = 4_000;
    private const int StepMs = 100;

    /// <summary>첫 표본이 출발선에서 이보다 멀면(피트 출발 등) 그리드를 만들지 않는다(m).</summary>
    private const double MaxFirstDistanceM = 40;

    /// <summary>그리드 거리 범위(m, 출발선 뒤)·출발선 앞 직선 선을 모으는 칸 간격(m).</summary>
    private const double MinGridM = 2;
    private const double MaxGridM = 300;
    private const double LineBinM = 5;

    /// <summary>그리드 칸의 옆 간격(m, 직선 선에서 한쪽으로).</summary>
    private const double SideOffsetM = 2.2;

    /// <summary>직선 선을 모을 때 이보다 느린 표본(그리드·피트)은 뺀다.</summary>
    private const int MinLineSpeedKph = 80;

    private const double KphPerMps = 3.6;
    private const double MsPerSecond = 1000;

    /// <summary>그리드 표본을 붙인 타임라인. 만들 수 없으면(선 재료 없음 등) [timeline] 그대로.</summary>
    public static RaceTimeline Fill(RaceTimeline timeline, int lightsOutMs, double trackLengthM)
    {
        var line = ApproachLine(timeline, trackLengthM);
        if (line.Count < 2)
        {
            return timeline;
        }

        // 출발 순서(첫 표본이 이른 차 = 앞 그리드).
        var order = timeline.Cars
            .Where(kv => kv.Value.Count > 0 && kv.Value[0].TimeMs > lightsOutMs && kv.Value[0].LapDistanceM <= MaxFirstDistanceM)
            .OrderBy(kv => kv.Value[0].TimeMs)
            .Select(kv => kv.Key)
            .ToList();
        if (order.Count == 0)
        {
            return timeline;
        }

        var cars = timeline.Cars.ToDictionary(kv => kv.Key, kv => kv.Value);
        for (var rank = 0; rank < order.Count; rank++)
        {
            var car = order[rank];
            var samples = timeline.Cars[car];
            var first = samples[0];
            var seconds = (first.TimeMs - lightsOutMs) / MsPerSecond;
            var behind = Math.Clamp(first.SpeedKph / KphPerMps * seconds / 2 - first.LapDistanceM, MinGridM, MaxGridM);

            // 옆 위치: 그리드 칸(번갈아) → 첫 표본의 실제 위치로 서서히.
            var anchor = Point(line, 0);
            var endSide = (first.X - anchor.X) * anchor.Nx + (first.Z - anchor.Z) * anchor.Nz;
            var gridSide = rank % 2 == 0 ? SideOffsetM : -SideOffsetM;

            var grid = new List<RaceSample>();
            for (var t = lightsOutMs - HoldMs; t < first.TimeMs; t += StepMs)
            {
                var tau = Math.Clamp((t - lightsOutMs) / (double)(first.TimeMs - lightsOutMs), 0, 1);
                var b = behind * (1 - tau * tau);
                var p = Point(line, b);
                var side = endSide + (gridSide - endSide) * (b / behind);
                var mps = 2 * behind * tau / seconds;
                grid.Add(new RaceSample(
                    t,
                    (float)Math.Max(0, trackLengthM - b),
                    (float)(p.X + p.Nx * side),
                    (float)p.Y,
                    (float)(p.Z + p.Nz * side),
                    (ushort)Math.Round(mps * KphPerMps),
                    first.Gear,
                    t < lightsOutMs ? (byte)0 : first.Throttle,
                    0,
                    0,
                    0,
                    first.Damage,
                    0,
                    0,
                    first.TyreVisualRaw));
            }

            cars[car] = grid.Concat(samples).ToList();
        }

        return RaceTimeline.FromCars(cars);
    }

    private readonly record struct LinePoint(double X, double Y, double Z, double Nx, double Nz);

    /// <summary>
    /// 출발선 앞 직선 선: 출발선 뒤 [MaxGridM]까지 [LineBinM] 칸마다 모든 차가 달린 자리의 중앙값(출발선 뒤 거리 순). 빈 칸은 건너뛴다.
    /// </summary>
    private static List<(double Behind, double X, double Y, double Z)> ApproachLine(RaceTimeline timeline, double trackLengthM)
    {
        var binCount = (int)(MaxGridM / LineBinM) + 1;
        var bins = Enumerable.Range(0, binCount).Select(_ => new List<RaceSample>()).ToArray();
        foreach (var sample in timeline.Cars.Values.SelectMany(s => s))
        {
            var behind = trackLengthM - sample.LapDistanceM;
            if (behind < 0 || behind > MaxGridM || sample.InPit || sample.SpeedKph < MinLineSpeedKph)
            {
                continue;
            }

            bins[(int)Math.Round(behind / LineBinM)].Add(sample);
        }

        return bins
            .Select((bin, k) => (bin, k))
            .Where(b => b.bin.Count > 0)
            .Select(b => (
                Behind: b.bin.Average(s => trackLengthM - s.LapDistanceM),
                X: Median(b.bin.Select(s => (double)s.X)),
                Y: Median(b.bin.Select(s => (double)s.Y)),
                Z: Median(b.bin.Select(s => (double)s.Z))))
            .ToList();
    }

    /// <summary>출발선 뒤 [behindM] 자리와 그 자리의 왼쪽 법선(진행 방향 = 출발선 쪽). 선 양 끝 밖은 끝 구간을 늘인다.</summary>
    private static LinePoint Point(List<(double Behind, double X, double Y, double Z)> line, double behindM)
    {
        var i = 0;
        while (i < line.Count - 2 && line[i + 1].Behind < behindM)
        {
            i++;
        }

        var a = line[i];
        var b = line[i + 1];
        var span = b.Behind - a.Behind;
        var t = span <= 0 ? 0 : (behindM - a.Behind) / span;

        // 진행 방향 = 뒤 점(b) → 앞 점(a).
        var dx = a.X - b.X;
        var dz = a.Z - b.Z;
        var length = Math.Sqrt(dx * dx + dz * dz);
        var (nx, nz) = length == 0 ? (0.0, 0.0) : (-dz / length, dx / length);
        return new LinePoint(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * Math.Clamp(t, 0, 1), a.Z + (b.Z - a.Z) * t, nx, nz);
    }

    private static double Median(IEnumerable<double> values)
    {
        var sorted = values.OrderBy(v => v).ToList();
        return sorted[sorted.Count / 2];
    }
}
