namespace SimCenter.Application.TrackSamples;

/// <summary>하이라이트 장면 종류.</summary>
public enum HighlightKind
{
    Start,
    Overtake,
    Collision,
    Crash,
    Retirement,
    SafetyCar,
    VirtualSafetyCar,
    RedFlag,
    Finish,
}

/// <summary>차 한 대의 이름표 재료(순위표).</summary>
public sealed record HighlightCarDto(int CarIndex, string Name, string TeamColor, bool IsPlayer, int Position);

/// <summary>깃발 구간(세션 시간 ms).</summary>
public sealed record HighlightFlagDto(string Kind, int FromMs, int ToMs);

/// <summary>
/// 클립 안 차 한 대의 움직임(같은 칸 = 같은 순간, 시간은 세션 ms). <c>Pit</c>은 피트 인(1, 박스에 서기 전)·피트 아웃(2, 박스를 떠난 뒤)·아님(0).
/// 표본 사이가 몇 초씩 비면 그 사이 차는 피트 레인에 있었다(옛 에이전트는 피트 레인 표본을 남기지 않았다).
/// </summary>
public sealed record HighlightCarTrackDto(
    int CarIndex,
    IReadOnlyList<int> TimeMs,
    IReadOnlyList<double> X,
    IReadOnlyList<double> Y,
    IReadOnlyList<double> Z,
    IReadOnlyList<int> SpeedKph,
    IReadOnlyList<int> Gear,
    IReadOnlyList<int> Throttle,
    IReadOnlyList<int> Brake,
    IReadOnlyList<int> Lap,
    IReadOnlyList<int> Pit);

/// <summary>
/// 하이라이트 클립 하나: 장면 종류·구간(세션 ms)·장면 순간·중심 차(카메라가 따라감)·상대 차·중심 차의 랩, 그 둘레 차들의 움직임,
/// 그리고 <see cref="RaceStandings.StepMs"/>마다의 순위표(중계 화면 왼쪽).
/// </summary>
public sealed record HighlightClipDto(
    string Kind,
    int StartMs,
    int EndMs,
    int EventMs,
    int FocusCar,
    int? OtherCar,
    int Lap,
    IReadOnlyList<HighlightCarTrackDto> Cars,
    IReadOnlyList<HighlightStandingDto> Standings);

/// <summary>
/// 레이스 하이라이트(<c>GET /api/v1/me/sessions/{id}/highlights</c>): 트랙(형상을 불러올 때), 차 이름표, 깃발 구간,
/// 내 하이라이트·레이스 하이라이트 두 묶음(시간 순).
/// </summary>
public sealed record HighlightsResponse(
    Guid SessionId,
    Guid TrackId,
    string GameCode,
    int TotalLaps,
    IReadOnlyList<HighlightCarDto> Cars,
    IReadOnlyList<HighlightFlagDto> Flags,
    IReadOnlyList<HighlightClipDto> Mine,
    IReadOnlyList<HighlightClipDto> Race);

/// <summary>
/// 레이스 타임라인 → 하이라이트 두 묶음(순수 계산). 장면: 출발, 추월(피트 레인·출발 직후·깃발 구간 제외), 차 대 차 충돌, 혼자 부딪힘(손상이 늘었을 때),
/// 리타이어, 세이프티카·버추얼·적기, 결승. 장면마다 점수를 매겨 묶음마다 상위 몇 개를 시간 순으로 고른다.
/// 내 하이라이트 = 내 차가 낀 장면 + 출발 + 내 결승.
/// </summary>
public static class HighlightsBuilder
{
    /// <summary>묶음마다 클립 수 한도.</summary>
    private const int MineClipLimit = 14;
    private const int RaceClipLimit = 18;

    /// <summary>출발 장면 길이(이 안의 추월은 출발 장면에 맡긴다).</summary>
    private const int StartWindowMs = 18_000;

    /// <summary>피트: 박스에 선 것으로 볼 속도, 표본이 이만큼(ms) 비면 그 사이 피트 레인(옛 에이전트), 그 앞뒤 이만큼(ms)을 피트 인·아웃으로 표시.</summary>
    private const int StoppedKph = 5;
    private const int PitGapMs = 8_000;
    private const int PitMarkMs = 5_000;
    private const int PitNone = 0;
    private const int PitIn = 1;
    private const int PitOut = 2;

    /// <summary>두 차 가운데 하나라도 피트 인·아웃 표시가 이 앞뒤(ms) 안에 있으면 그 추월은 피트 출입으로 순위만 바뀐 것으로 본다(합류·진입 직전 추월 포함).</summary>
    private const int PitOvertakeMarginMs = 8_000;

    /// <summary>추월한 차·당한 차 표시를 짝지을 시간 차·같은 두 차의 장면을 하나로 볼 간격.</summary>
    private const int PairMs = 400;
    private const int SamePairMergeMs = 12_000;

    /// <summary>같은 차의 충격·충돌을 하나로 볼 간격, 혼자 부딪힘으로 볼 손상 증가(%).</summary>
    private const int SameCarMergeMs = 8_000;
    private const int CrashMinDamageRise = 5;
    private const int DamageLookMs = 1_500;

    /// <summary>추월 순간 두 차가 이만큼(m) 안에 있어야 진짜 추월로 본다(피트 출입·되감기로 순위만 바뀐 것을 거른다).</summary>
    private const double OvertakeMaxGapM = 40;

    /// <summary>클립 둘레에 같이 그릴 차의 거리(m, 장면 순간 중심 차 기준)·클립에 담는 표본 간격(ms, 앱이 사이를 보간한다).</summary>
    private const double NearbyM = 250;
    private const int ClipSampleStepMs = 200;

    /// <summary>점수: 종류별 기본, 상위권(최종 5위 안)·선두를 넘으면 더한다(내 차라고 더하지 않는다 — 레이스 하이라이트는 모두의 장면). 출발·결승은 늘 든다.</summary>
    private const double StartScore = 100;
    private const double FinishScore = 100;
    private const double CollisionScore = 6;
    private const double CrashScore = 3;
    private const double BigCrashBonus = 2;
    private const int BigCrashDamage = 30;
    private const double RetirementScore = 5;
    private const double FlagScore = 5;
    private const double OvertakeScore = 2;
    private const double TopFiveBonus = 1.5;
    private const int TopFive = 5;
    private const double LeadBonus = 2;

    /// <summary>클립 길이(장면 순간 앞·뒤 ms).</summary>
    private const int OvertakeBeforeMs = 7_000;
    private const int OvertakeAfterMs = 3_000;
    private const int ContactBeforeMs = 6_000;
    private const int ContactAfterMs = 5_000;
    private const int RetirementBeforeMs = 8_000;
    private const int RetirementAfterMs = 2_000;
    private const int FlagBeforeMs = 3_000;
    private const int FlagAfterMs = 7_000;
    private const int FinishBeforeMs = 9_000;
    private const int FinishAfterMs = 4_000;

    /// <summary>선두 판정에서 결승선 통과 한 번의 무게(랩 거리보다 늘 크게).</summary>
    private const double CrossingWeightM = 100_000;

    private sealed record Scene(HighlightKind Kind, int TimeMs, int Focus, int? Other, double Score, int BeforeMs, int AfterMs);

    public static HighlightsResponse Build(
        Guid sessionId,
        Guid trackId,
        string gameCode,
        int totalLaps,
        RaceTimeline timeline,
        double trackLengthM,
        IReadOnlyList<HighlightCarDto> cars,
        IReadOnlyList<RaceFlagPeriod> flags,
        IReadOnlyList<RaceRetirement> retirements,
        int? lightsOutMs = null)
    {
        var flagDtos = flags.Select(f => new HighlightFlagDto(f.Kind.ToString(), f.FromMs, f.ToMs)).ToList();
        if (timeline.Cars.Count == 0)
        {
            return new HighlightsResponse(sessionId, trackId, gameCode, totalLaps, cars, flagDtos, [], []);
        }

        var player = cars.FirstOrDefault(c => c.IsPlayer)?.CarIndex;
        var position = cars.ToDictionary(c => c.CarIndex, c => c.Position);
        var crossings = timeline.Cars.Keys.ToDictionary(car => car, car => timeline.CrossingsOf(car, trackLengthM));
        double Rank(int car) => position.TryGetValue(car, out var p) && p is > 0 and <= TopFive ? TopFiveBonus : 0;

        var scenes = new List<Scene>();

        // 출발: 레이스 첫 표본부터. 중심 = 출발 몇 초 뒤 가장 앞선 차(내 하이라이트는 내 차).
        // 소등 시각을 알면 그 몇 초 전(그리드에 선 모습)부터.
        var start = lightsOutMs ?? timeline.StartMs;
        var leaderAtStart = LeaderAt(timeline, start + StartWindowMs / 2, crossings) ?? timeline.Cars.Keys.First();
        var startScene = new Scene(
            HighlightKind.Start, start, leaderAtStart, null, StartScore, lightsOutMs is null ? 0 : RaceGrid.HoldMs, StartWindowMs);
        scenes.Add(startScene);

        // 차마다 표본별 피트 인·아웃(추월 거르기·클립에 싣기). 추월은 그 순간 앞뒤로 피트 표시가 있으면 뺀다.
        var pitPhases = timeline.Cars.ToDictionary(kv => kv.Key, kv => PitPhases(kv.Value));
        bool Pitting(int car, int timeMs)
        {
            var samples = timeline.Cars[car];
            var phases = pitPhases[car];
            for (var i = IndexAt(samples, timeMs - PitOvertakeMarginMs); i < samples.Count && samples[i].TimeMs <= timeMs + PitOvertakeMarginMs; i++)
            {
                if (phases[i] != PitNone)
                {
                    return true;
                }
            }

            return false;
        }

        scenes.AddRange(Overtakes(timeline, flags, start, position, Rank, Pitting));
        scenes.AddRange(Contacts(timeline, player, Rank));

        foreach (var retirement in retirements)
        {
            scenes.Add(new Scene(HighlightKind.Retirement, retirement.TimeMs, retirement.CarIndex, null,
                RetirementScore + Rank(retirement.CarIndex),
                RetirementBeforeMs, RetirementAfterMs));
        }

        foreach (var flag in flags)
        {
            var kind = flag.Kind switch
            {
                RaceFlagKind.SafetyCar => HighlightKind.SafetyCar,
                RaceFlagKind.VirtualSafetyCar => HighlightKind.VirtualSafetyCar,
                _ => HighlightKind.RedFlag,
            };
            var focus = LeaderAt(timeline, flag.FromMs, crossings) ?? leaderAtStart;
            scenes.Add(new Scene(kind, flag.FromMs, focus, null, FlagScore, FlagBeforeMs, FlagAfterMs));
        }

        // 결승: 우승 차(순위 1위)의 마지막 결승선 통과.
        var winner = cars.Where(c => c.Position == 1).Select(c => (int?)c.CarIndex).FirstOrDefault() ?? leaderAtStart;
        if (crossings.TryGetValue(winner, out var winnerCrossings) && winnerCrossings.Count > 0)
        {
            scenes.Add(new Scene(HighlightKind.Finish, winnerCrossings[^1], winner, null, FinishScore, FinishBeforeMs, FinishAfterMs));
        }

        var standings = new RaceStandings(timeline, trackLengthM, totalLaps, winner, crossings, retirements, pitPhases);
        var raceScenes = Pick(scenes, RaceClipLimit);
        var mineScenes = new List<Scene>();
        if (player is { } me)
        {
            mineScenes.Add(startScene with { Focus = me });
            mineScenes.AddRange(scenes.Where(s => s.Kind is not (HighlightKind.Start or HighlightKind.Finish)
                                                  && (s.Focus == me || s.Other == me)));
            if (crossings.TryGetValue(me, out var mine) && mine.Count > 0)
            {
                mineScenes.Add(new Scene(HighlightKind.Finish, mine[^1], me, null, FinishScore, FinishBeforeMs, FinishAfterMs));
            }

            mineScenes = Pick(mineScenes, MineClipLimit);
        }

        return new HighlightsResponse(
            sessionId,
            trackId,
            gameCode,
            totalLaps,
            cars,
            flagDtos,
            mineScenes.Select(s => Clip(timeline, s, crossings, pitPhases, standings)).ToList(),
            raceScenes.Select(s => Clip(timeline, s, crossings, pitPhases, standings)).ToList());
    }

    /// <summary>추월: 추월함 표시와 같은 순간의 추월당함 표시를 짝짓는다. 피트 인·아웃 중·출발 장면 안·깃발 구간 안은 뺀다. 같은 두 차는 몇 초 안에 한 번.</summary>
    private static IEnumerable<Scene> Overtakes(
        RaceTimeline timeline, IReadOnlyList<RaceFlagPeriod> flags, int start, IReadOnlyDictionary<int, int> position,
        Func<int, double> rank, Func<int, int, bool> pitting)
    {
        var overtook = Marks(timeline, s => (s.Flags2 & RaceSample.OvertookFlag) != 0);
        var overtaken = Marks(timeline, s => (s.Flags2 & RaceSample.OvertakenFlag) != 0);
        var last = new Dictionary<(int, int), int>();
        foreach (var (time, car, sample) in overtook)
        {
            if (time < start + StartWindowMs || sample.InPit || pitting(car, time) || flags.Any(f => time >= f.FromMs && time <= f.ToMs))
            {
                continue;
            }

            // 추월당한 차가 피트에 드나드는 중이었으면(짝 후보 중 가장 가까운 차 기준) 진짜 추월이 아니다.
            if (overtaken.Any(o => o.Car != car && Math.Abs(o.Time - time) <= PairMs && Distance(o.Sample, sample) <= OvertakeMaxGapM
                                   && (o.Sample.InPit || pitting(o.Car, o.Time))))
            {
                continue;
            }

            var victim = overtaken
                .Where(o => o.Car != car && Math.Abs(o.Time - time) <= PairMs && !o.Sample.InPit && !pitting(o.Car, o.Time)
                            && Distance(o.Sample, sample) <= OvertakeMaxGapM)
                .OrderBy(o => Math.Abs(o.Sample.LapDistanceM - sample.LapDistanceM))
                .Select(o => (int?)o.Car)
                .FirstOrDefault();
            if (victim is not { } other)
            {
                continue;
            }

            var pair = (Math.Min(car, other), Math.Max(car, other));
            if (last.TryGetValue(pair, out var previous) && time - previous < SamePairMergeMs)
            {
                continue;
            }

            last[pair] = time;
            var lead = position.TryGetValue(other, out var p) && p == 1 ? LeadBonus : 0;
            yield return new Scene(HighlightKind.Overtake, time, car, other,
                OvertakeScore + rank(car) + lead, OvertakeBeforeMs, OvertakeAfterMs);
        }
    }

    /// <summary>
    /// 차 대 차 충돌(같은 순간 충돌 표시가 선 두 차)과 혼자 부딪힘(충격 표시 + 손상 증가, 충돌과 겹치지 않을 때). 같은 차는 몇 초 안에 한 번.
    /// </summary>
    private static IEnumerable<Scene> Contacts(RaceTimeline timeline, int? player, Func<int, double> rank)
    {
        var collisions = Marks(timeline, s => (s.Status & RaceSample.CollisionFlag) != 0 && !s.InPit);
        var impacts = Marks(timeline, s => (s.Status & RaceSample.ImpactFlag) != 0 && !s.InPit);
        var lastByCar = new Dictionary<int, int>();
        bool Recent(int car, int time) => lastByCar.TryGetValue(car, out var t) && time - t < SameCarMergeMs;

        foreach (var (time, car, _) in collisions)
        {
            if (Recent(car, time))
            {
                continue;
            }

            var other = collisions
                .Where(c => c.Car != car && Math.Abs(c.Time - time) <= PairMs)
                .Select(c => (int?)c.Car)
                .FirstOrDefault();
            lastByCar[car] = time;
            if (other is { } o)
            {
                lastByCar[o] = time;
            }

            // 내 차가 끼면 내 차를 중심으로.
            var focus = player is { } me && other == me ? me : car;
            var partner = focus == car ? other : car;
            yield return new Scene(HighlightKind.Collision, time, focus, partner,
                CollisionScore + rank(focus), ContactBeforeMs, ContactAfterMs);
        }

        foreach (var (time, car, _) in impacts)
        {
            if (Recent(car, time))
            {
                continue;
            }

            var before = timeline.SampleAt(car, time - DamageLookMs)?.Damage ?? 0;
            var after = timeline.SampleAt(car, time + DamageLookMs)?.Damage ?? 0;
            if (after - before < CrashMinDamageRise)
            {
                continue;
            }

            lastByCar[car] = time;
            var big = after >= BigCrashDamage ? BigCrashBonus : 0;
            yield return new Scene(HighlightKind.Crash, time, car, null,
                CrashScore + big + rank(car), ContactBeforeMs, ContactAfterMs);
        }
    }

    private static List<(int Time, int Car, RaceSample Sample)> Marks(RaceTimeline timeline, Func<RaceSample, bool> predicate)
        => timeline.Cars
            .SelectMany(kv => kv.Value.Where(predicate).Select(s => (s.TimeMs, kv.Key, s)))
            .OrderBy(m => m.TimeMs)
            .ToList();

    /// <summary>[timeMs]에 가장 많이 달린(결승선 통과 수 + 랩 거리) 차.</summary>
    private static int? LeaderAt(RaceTimeline timeline, int timeMs, IReadOnlyDictionary<int, IReadOnlyList<int>> crossings)
        => timeline.Cars.Keys
            .Select(car => (car, sample: timeline.SampleAt(car, timeMs)))
            .Where(x => x.sample is { } s && Math.Abs(s.TimeMs - timeMs) < SameCarMergeMs)
            .OrderByDescending(x => crossings[x.car].Count(t => t <= timeMs) * CrossingWeightM + x.sample!.Value.LapDistanceM)
            .Select(x => (int?)x.car)
            .FirstOrDefault();

    /// <summary>점수 높은 것부터 [limit]개를 시간 순으로. 이미 고른 클립 구간 안에 드는 장면은 그 클립이 보여 주므로 뺀다.</summary>
    private static List<Scene> Pick(IEnumerable<Scene> scenes, int limit)
    {
        var picked = new List<Scene>();
        foreach (var scene in scenes.OrderByDescending(s => s.Score).ThenBy(s => s.TimeMs))
        {
            if (picked.Count == limit)
            {
                break;
            }

            if (picked.All(p => scene.TimeMs < p.TimeMs - p.BeforeMs || scene.TimeMs > p.TimeMs + p.AfterMs))
            {
                picked.Add(scene);
            }
        }

        return picked.OrderBy(s => s.TimeMs).ToList();
    }

    private static double Distance(RaceSample a, RaceSample b)
        => Math.Sqrt(Math.Pow(a.X - b.X, 2) + Math.Pow(a.Z - b.Z, 2));

    /// <summary>
    /// 표본마다 피트 인·아웃. 피트 상태가 실린 표본(새 에이전트)은 박스에 서기 전 = 인, 선 뒤 = 아웃(서지 않고 지나가면 절반씩).
    /// 표본이 [PitGapMs] 넘게 빈 곳(옛 에이전트: 피트 레인 표본 없음)은 빈 구간 앞 [PitMarkMs] = 인, 뒤 = 아웃.
    /// </summary>
    private static int[] PitPhases(IReadOnlyList<RaceSample> samples)
    {
        var phases = new int[samples.Count];
        for (var i = 0; i < samples.Count;)
        {
            if (!samples[i].InPit)
            {
                i++;
                continue;
            }

            var end = i;
            while (end < samples.Count && samples[end].InPit)
            {
                end++;
            }

            var stop = -1;
            for (var k = i; k < end && stop < 0; k++)
            {
                if (samples[k].SpeedKph < StoppedKph)
                {
                    stop = k;
                }
            }

            var turn = stop >= 0 ? stop : (i + end) / 2;
            for (var k = i; k < end; k++)
            {
                phases[k] = k < turn ? PitIn : PitOut;
            }

            i = end;
        }

        for (var k = 0; k + 1 < samples.Count; k++)
        {
            var before = samples[k].TimeMs;
            var after = samples[k + 1].TimeMs;
            if (after - before < PitGapMs)
            {
                continue;
            }

            for (var j = k; j >= 0 && samples[j].TimeMs >= before - PitMarkMs; j--)
            {
                phases[j] = phases[j] == PitNone ? PitIn : phases[j];
            }

            for (var j = k + 1; j < samples.Count && samples[j].TimeMs <= after + PitMarkMs; j++)
            {
                phases[j] = phases[j] == PitNone ? PitOut : phases[j];
            }
        }

        return phases;
    }

    /// <summary>[samples]에서 [timeMs] 이상인 첫 표본(없으면 마지막).</summary>
    private static int IndexAt(IReadOnlyList<RaceSample> samples, int timeMs)
    {
        var low = 0;
        var high = samples.Count - 1;
        while (low < high)
        {
            var mid = (low + high) / 2;
            if (samples[mid].TimeMs < timeMs)
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

    private static HighlightClipDto Clip(
        RaceTimeline timeline,
        Scene scene,
        IReadOnlyDictionary<int, IReadOnlyList<int>> crossings,
        IReadOnlyDictionary<int, int[]> pitPhases,
        RaceStandings standings)
    {
        var from = Math.Max(timeline.StartMs, scene.TimeMs - scene.BeforeMs);
        var to = Math.Min(timeline.EndMs, scene.TimeMs + scene.AfterMs);
        var center = timeline.SampleAt(scene.Focus, scene.TimeMs);
        var tracks = new List<HighlightCarTrackDto>();
        foreach (var (car, samples) in timeline.Cars)
        {
            var near = car == scene.Focus || car == scene.Other || scene.Kind == HighlightKind.Start
                       || (center is { } c && timeline.SampleAt(car, scene.TimeMs) is { } s
                           && Math.Abs(s.TimeMs - scene.TimeMs) < SameCarMergeMs
                           && Distance(s, c) <= NearbyM);
            if (!near)
            {
                continue;
            }

            var phases = pitPhases[car];
            var window = new List<RaceSample>();
            var pit = new List<int>();
            for (var i = 0; i < samples.Count; i++)
            {
                var sample = samples[i];
                if (sample.TimeMs >= from && sample.TimeMs <= to
                    && (window.Count == 0 || sample.TimeMs - window[^1].TimeMs >= ClipSampleStepMs))
                {
                    window.Add(sample);
                    pit.Add(phases[i]);
                }
            }

            if (window.Count == 0)
            {
                continue;
            }

            var carCrossings = crossings[car];
            tracks.Add(new HighlightCarTrackDto(
                car,
                window.Select(s => s.TimeMs).ToList(),
                window.Select(s => Math.Round((double)s.X, 1)).ToList(),
                window.Select(s => Math.Round((double)s.Y, 1)).ToList(),
                window.Select(s => Math.Round((double)s.Z, 1)).ToList(),
                window.Select(s => (int)s.SpeedKph).ToList(),
                window.Select(s => (int)s.Gear).ToList(),
                window.Select(s => (int)s.Throttle).ToList(),
                window.Select(s => (int)s.Brake).ToList(),
                window.Select(s => 1 + carCrossings.Count(t => t <= s.TimeMs)).ToList(),
                pit));
        }

        var lap = 1 + crossings.GetValueOrDefault(scene.Focus, []).Count(t => t <= scene.TimeMs);
        return new HighlightClipDto(
            scene.Kind.ToString(), from, to, scene.TimeMs, scene.Focus, scene.Other, lap, tracks, standings.Frames(from, to));
    }
}
