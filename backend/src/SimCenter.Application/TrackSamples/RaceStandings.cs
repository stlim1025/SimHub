namespace SimCenter.Application.TrackSamples;

/// <summary>순위표 한 칸의 차 상태: 달리는 중·피트·피니시(체커기)·리타이어.</summary>
public enum StandingState
{
    Running,
    Pit,
    Finished,
    Out,
}

/// <summary>
/// 클립 안 한 순간의 순위표(중계 화면 왼쪽 순위표). 칸 순서 = 순위. 간격은 리더가 그 차의 지금 자리를 지난 시각과의 차(ms),
/// 리더면 0, 알 수 없으면(출발 전 등) null. 랩 뒤처짐이 1 이상이면 간격 대신 <c>+N LAP</c>을 보인다. 상태는 <see cref="StandingState"/> 값.
/// </summary>
public sealed record HighlightStandingDto(
    int TimeMs,
    int Lap,
    IReadOnlyList<int> Cars,
    IReadOnlyList<int?> GapMs,
    IReadOnlyList<int> LapsDown,
    IReadOnlyList<int> State);

/// <summary>
/// 레이스 진행(랩 수 × 트랙 길이 + 랩 거리)으로 매 순간 순위표를 만든다(순수 계산).
/// 순서: 피니시한 차(먼저 들어온 순) → 달리는 차(많이 달린 순) → 리타이어한 차. 피니시 = 우승 차가 마지막 랩을 마친 뒤 처음 지난 결승선.
/// 간격은 리더의 진행-시간 기록에서 그 차의 지금 진행에 닿은 시각을 찾아 잰다(피니시한 차는 들어온 시각 차).
/// </summary>
public sealed class RaceStandings
{
    /// <summary>순위표 프레임 간격(ms).</summary>
    public const int StepMs = 500;

    /// <summary>표본이 이만큼(ms) 비면 그 사이 피트 레인(옛 에이전트).</summary>
    private const int PitGapMs = 8_000;

    private readonly RaceTimeline _timeline;
    private readonly double _trackLengthM;
    private readonly int _totalLaps;
    private readonly IReadOnlyDictionary<int, double[]> _progress;
    private readonly IReadOnlyDictionary<int, int> _finishMs;
    private readonly IReadOnlyDictionary<int, int> _retiredMs;
    private readonly IReadOnlyDictionary<int, int[]> _pitPhases;

    public RaceStandings(
        RaceTimeline timeline,
        double trackLengthM,
        int totalLaps,
        int? winner,
        IReadOnlyDictionary<int, IReadOnlyList<int>> crossings,
        IReadOnlyList<RaceRetirement> retirements,
        IReadOnlyDictionary<int, int[]> pitPhases)
    {
        _timeline = timeline;
        _trackLengthM = trackLengthM;
        _totalLaps = totalLaps;
        _pitPhases = pitPhases;
        _progress = timeline.Cars.ToDictionary(kv => kv.Key, kv => Progress(kv.Value, trackLengthM));
        _retiredMs = retirements.GroupBy(r => r.CarIndex).ToDictionary(g => g.Key, g => g.Min(r => r.TimeMs));

        var finish = new Dictionary<int, int>();
        if (winner is { } w && crossings.TryGetValue(w, out var winnerCrossings) && winnerCrossings.Count > 0)
        {
            var raceEnd = totalLaps > 0 && winnerCrossings.Count >= totalLaps ? winnerCrossings[totalLaps - 1] : winnerCrossings[^1];
            foreach (var (car, carCrossings) in crossings)
            {
                if (carCrossings.Where(t => t >= raceEnd).Select(t => (int?)t).FirstOrDefault() is { } at)
                {
                    finish[car] = at;
                }
            }
        }

        _finishMs = finish;
    }

    /// <summary>[fromMs]~[toMs]의 순위표 프레임([StepMs]마다).</summary>
    public IReadOnlyList<HighlightStandingDto> Frames(int fromMs, int toMs)
    {
        var frames = new List<HighlightStandingDto>();
        for (var t = fromMs; t <= toMs; t += StepMs)
        {
            frames.Add(At(t));
        }

        return frames;
    }

    private HighlightStandingDto At(int timeMs)
    {
        var rows = _timeline.Cars.Keys
            .Where(car => _timeline.Cars[car].Count > 0)
            .Select(car =>
            {
                var finished = _finishMs.TryGetValue(car, out var f) && f <= timeMs;
                var retired = !finished && _retiredMs.TryGetValue(car, out var r) && r <= timeMs;
                var state = finished ? StandingState.Finished
                    : retired ? StandingState.Out
                    : InPit(car, timeMs) ? StandingState.Pit
                    : StandingState.Running;
                return (Car: car, Progress: ProgressAt(car, finished ? f : timeMs), State: state, FinishMs: finished ? f : int.MaxValue);
            })
            .OrderBy(r => r.State switch { StandingState.Finished => 0, StandingState.Out => 2, _ => 1 })
            .ThenBy(r => r.FinishMs)
            .ThenByDescending(r => r.Progress)
            .ToList();

        var leader = rows[0];
        var leaderNow = ProgressAt(leader.Car, timeMs);
        var gaps = new List<int?>();
        var lapsDown = new List<int>();
        foreach (var row in rows)
        {
            if (row.Car == leader.Car)
            {
                gaps.Add(0);
                lapsDown.Add(0);
                continue;
            }

            var reference = row.State == StandingState.Finished ? row.FinishMs : timeMs;
            gaps.Add(TimeAtProgress(leader.Car, row.Progress) is { } at ? Math.Max(0, reference - at) : null);
            lapsDown.Add(row.State == StandingState.Finished
                ? Math.Max(0, (int)Math.Round((leader.Progress - row.Progress) / _trackLengthM))
                : Math.Max(0, (int)Math.Floor((leaderNow - row.Progress) / _trackLengthM)));
        }

        var lap = Math.Clamp((int)Math.Floor(leaderNow / _trackLengthM) + 1, 1, Math.Max(1, _totalLaps));
        return new HighlightStandingDto(
            timeMs,
            lap,
            rows.Select(r => r.Car).ToList(),
            gaps,
            lapsDown,
            rows.Select(r => (int)r.State).ToList());
    }

    /// <summary>
    /// 표본마다 진행(m) = 지난 랩 수 × 트랙 길이 + 랩 거리. 첫 표본이 랩 뒤쪽 절반(그리드)이면 랩 수 −1에서 시작한다
    /// (<see cref="RaceTimeline.CrossingsOf"/>와 같은 규칙).
    /// </summary>
    private static double[] Progress(IReadOnlyList<RaceSample> samples, double trackLengthM)
    {
        var progress = new double[samples.Count];
        if (samples.Count == 0)
        {
            return progress;
        }

        var half = trackLengthM / 2;
        var lap = samples[0].LapDistanceM < half ? 0 : -1;
        progress[0] = lap * trackLengthM + samples[0].LapDistanceM;
        for (var k = 1; k < samples.Count; k++)
        {
            if (samples[k - 1].LapDistanceM - samples[k].LapDistanceM > half)
            {
                lap++;
            }

            progress[k] = lap * trackLengthM + samples[k].LapDistanceM;
        }

        return progress;
    }

    private double ProgressAt(int car, int timeMs)
    {
        var samples = _timeline.Cars[car];
        var progress = _progress[car];
        var i = Upper(samples, timeMs);
        if (i == 0)
        {
            return progress[0];
        }

        if (i >= samples.Count)
        {
            return progress[^1];
        }

        var span = samples[i].TimeMs - samples[i - 1].TimeMs;
        var t = span <= 0 ? 0 : (timeMs - samples[i - 1].TimeMs) / (double)span;
        return progress[i - 1] + (progress[i] - progress[i - 1]) * t;
    }

    /// <summary>[car]의 진행이 처음 [target]에 닿은 시각. 그보다 앞서 시작했으면(출발 전 등) null.</summary>
    private int? TimeAtProgress(int car, double target)
    {
        var samples = _timeline.Cars[car];
        var progress = _progress[car];
        if (target < progress[0])
        {
            return null;
        }

        var low = 0;
        var high = progress.Length - 1;
        if (target >= progress[high])
        {
            return samples[high].TimeMs;
        }

        while (high - low > 1)
        {
            var mid = (low + high) / 2;
            if (progress[mid] < target)
            {
                low = mid;
            }
            else
            {
                high = mid;
            }
        }

        var span = progress[high] - progress[low];
        var t = span <= 0 ? 0 : (target - progress[low]) / span;
        return (int)Math.Round(samples[low].TimeMs + (samples[high].TimeMs - samples[low].TimeMs) * t);
    }

    /// <summary>피트 인·아웃 표시 중이거나 표본이 끊긴 사이(피트 레인 — 옛 에이전트)면 피트.</summary>
    private bool InPit(int car, int timeMs)
    {
        var samples = _timeline.Cars[car];
        var i = Upper(samples, timeMs);
        if (i > 0 && i < samples.Count && samples[i].TimeMs - samples[i - 1].TimeMs >= PitGapMs)
        {
            return true;
        }

        var nearest = Math.Clamp(i - 1, 0, samples.Count - 1);
        return samples[nearest].InPit || (_pitPhases.TryGetValue(car, out var phases) && phases[nearest] != 0);
    }

    /// <summary>[timeMs]보다 늦은 첫 표본 번호(없으면 표본 수).</summary>
    private static int Upper(IReadOnlyList<RaceSample> samples, int timeMs)
    {
        var low = 0;
        var high = samples.Count;
        while (low < high)
        {
            var mid = (low + high) / 2;
            if (samples[mid].TimeMs <= timeMs)
            {
                low = mid + 1;
            }
            else
            {
                high = mid;
            }
        }

        return low;
    }
}
