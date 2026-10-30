using SimCenter.Application.Laps;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>레이스 분석에 쓰는 내 랩 트레이스 하나(풀어 둔 채널, 표본 간격 m). 추가 채널은 기본 채널과 길이가 같을 때만 쓴다.</summary>
public sealed record RaceTraceLap(int LapNumber, int ResolutionM, LapTraceChannels Channels)
{
    public int Count => Channels.TimeMs.Length;

    /// <summary>이름이 같은 추가 채널. 없거나 길이가 다르면 null.</summary>
    public double[]? Extra(string name)
        => Channels.Extra is { } extra && extra.TryGetValue(name, out var values) && values.Length == Count ? values : null;
}

/// <summary>
/// 랩 구간 하나(표본 번호 [<see cref="Start"/>, <see cref="End"/>]). <see cref="Start"/> &gt; <see cref="End"/>면 결승선을 넘는 직선이다 —
/// 랩 끝 쪽 [Start, 끝]과 앞 쪽 [0, End] 두 덩어리.
/// </summary>
internal sealed record SegmentRange(int Index, bool IsCorner, int Start, int End)
{
    public bool Wraps => Start > End;

    /// <summary>표본이 [count]개인 랩에서 이 구간의 연속 덩어리(랩 길이를 넘는 쪽은 자른다).</summary>
    public IEnumerable<(int From, int To)> Runs(int count)
    {
        var last = count - 1;
        if (last < 0)
        {
            yield break;
        }

        if (Wraps)
        {
            if (Start <= last)
            {
                yield return (Start, last);
            }

            yield return (0, Math.Min(End, last));
        }
        else if (Start <= last)
        {
            yield return (Start, Math.Min(End, last));
        }
    }
}

/// <summary>
/// 기준 랩으로 랩을 구간으로 나눈다(순수 계산). 횡 G가 <see cref="CornerLateralG"/> 이상이거나 브레이크를 <see cref="CornerBrakePct"/>% 넘게
/// 밟은 표본이 코너 — 코너 사이가 <see cref="MergeGapM"/>보다 짧으면 한 코너(복합 코너)로 묶고, <see cref="MinCornerM"/>보다 짧은 코너는 버린다.
/// 코너 사이가 <see cref="MinStraightM"/> 이상이면 직선(마지막 코너 → 결승선 → 첫 코너도 직선 하나, 맨 앞 번호), 그보다 짧으면 앞 코너의 탈출로 붙인다 —
/// 구간들이 랩 전체를 빈틈없이 덮는다. 횡 G 채널이 없거나 코너가 없으면 빈 목록.
/// </summary>
internal static class RaceSegments
{
    private const double CornerLateralG = 1.5;
    private const int CornerBrakePct = 5;
    private const int MergeGapM = 60;
    private const int MinCornerM = 30;
    private const int MinStraightM = 150;

    public static IReadOnlyList<SegmentRange> Detect(RaceTraceLap reference)
    {
        ArgumentNullException.ThrowIfNull(reference);
        var lateral = reference.Extra(TraceChannelNames.LateralG);
        var count = reference.Count;
        var resolution = reference.ResolutionM;
        if (lateral is null || count == 0 || resolution <= 0)
        {
            return [];
        }

        var brake = reference.Channels.Brake;
        bool Cornering(int i) => Math.Abs(lateral[i]) >= CornerLateralG || brake[i] > CornerBrakePct;

        var corners = new List<(int Start, int End)>();
        for (var i = 0; i < count; i++)
        {
            if (!Cornering(i))
            {
                continue;
            }

            var end = i;
            while (end + 1 < count && Cornering(end + 1))
            {
                end++;
            }

            if (corners.Count > 0 && (i - corners[^1].End) * resolution < MergeGapM)
            {
                corners[^1] = (corners[^1].Start, end);
            }
            else
            {
                corners.Add((i, end));
            }

            i = end;
        }

        corners.RemoveAll(c => (c.End - c.Start) * resolution < MinCornerM);
        if (corners.Count == 0)
        {
            return [];
        }

        // 직선이 되기에 짧은 코너 사이는 앞 코너의 탈출로 붙여 구간이 랩 전체를 빈틈없이 덮게 한다(구간 합 = 랩 합).
        for (var k = 0; k + 1 < corners.Count; k++)
        {
            if ((corners[k + 1].Start - corners[k].End - 1) * resolution < MinStraightM)
            {
                corners[k] = (corners[k].Start, corners[k + 1].Start - 1);
            }
        }

        var ranges = new List<(bool IsCorner, int Start, int End)>();
        var wrapSamples = count - 1 - corners[^1].End + corners[0].Start;
        if (wrapSamples * resolution >= MinStraightM)
        {
            var start = corners[^1].End + 1;
            var end = corners[0].Start - 1;
            ranges.Add(start > count - 1 ? (false, 0, end) : end < 0 ? (false, start, count - 1) : (false, start, end));
        }
        else
        {
            corners[^1] = (corners[^1].Start, count - 1);
            corners[0] = (0, corners[0].End);
        }

        for (var k = 0; k < corners.Count; k++)
        {
            if (k > 0 && corners[k].Start - corners[k - 1].End > 1)
            {
                ranges.Add((false, corners[k - 1].End + 1, corners[k].Start - 1));
            }

            ranges.Add((true, corners[k].Start, corners[k].End));
        }

        return ranges.Select((r, index) => new SegmentRange(index, r.IsCorner, r.Start, r.End)).ToList();
    }
}

/// <summary>레이스 분석이 읽는 트레이스 추가 채널 이름(f1_25_udp_spec §6). 바퀴 채널은 접미사 FL·FR·RL·RR.</summary>
internal static class TraceChannelNames
{
    public const string LateralG = "gForceLateral";
    public const string LateralForce = "wheelLatForce";
    public const string LongitudinalForce = "wheelLongForce";
    public const string SlipAngle = "wheelSlipAngleDeg";
    public const string SlipRatio = "wheelSlipRatioPct";
    public const string SurfaceTemp = "tyreSurfaceTemp";
    public const string InnerTemp = "tyreInnerTemp";
    public const string Surface = "surfaceType";
    public const string ErsStore = "ersStoreEnergy";
    public const string ErsDeployMode = "ersDeployMode";

    /// <summary>바퀴 순서(앞왼·앞오·뒤왼·뒤오) — 응답의 바퀴 배열도 이 순서.</summary>
    public static readonly string[] Wheels = ["FL", "FR", "RL", "RR"];

    /// <summary>바퀴 네 개 채널(<c>{prefix}FL</c> …). 하나라도 없으면 null.</summary>
    public static double[][]? WheelChannels(RaceTraceLap lap, string prefix)
    {
        var channels = new double[Wheels.Length][];
        for (var w = 0; w < Wheels.Length; w++)
        {
            if (lap.Extra(prefix + Wheels[w]) is not { } values)
            {
                return null;
            }

            channels[w] = values;
        }

        return channels;
    }
}
