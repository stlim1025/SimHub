using System.Text.Json;
using SimCenter.Application.TrackSamples;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>랩 끝 스냅샷의 타이어 세트 하나(<c>details.tyreSets.sets[]</c>): 보이는 컴파운드, 마모(%), 쓸 수 있는지, 게임이 본 남은 수명·쓸 수 있는 랩, 끼운 세트 대비 랩타임 차(ms).</summary>
internal sealed record TyreSetState(TyreCompound Compound, int? WearPct, bool Available, int? LifeSpanLaps, int? UsableLifeLaps, int? LapDeltaTimeMs);

/// <summary>랩 끝 스냅샷의 게임 타이어 상태: 피트 창(이상·최대 랩, 0이면 없음), 끼운 세트 번호, 세트 목록.</summary>
internal sealed record LapTyreState(int LapNumber, int? IdealLap, int? LatestLap, int? FittedIndex, IReadOnlyList<TyreSetState> Sets)
{
    public TyreSetState? Fitted => FittedIndex is { } i && i >= 0 && i < Sets.Count ? Sets[i] : null;

    /// <summary>스냅샷 <c>details</c>의 <c>session</c>·<c>tyreSets</c>를 읽는다. 둘 다 없으면 null.</summary>
    public static LapTyreState? From(MySessionLap lap)
    {
        ArgumentNullException.ThrowIfNull(lap);
        using var document = JsonReads.ParseObject(lap.Row.SnapshotDetails);
        if (document is null)
        {
            return null;
        }

        var session = JsonReads.Object(document.RootElement, "session");
        var tyreSets = JsonReads.Object(document.RootElement, "tyreSets");
        if (session is null && tyreSets is null)
        {
            return null;
        }

        var sets = new List<TyreSetState>();
        if (tyreSets is { } t && JsonReads.Array(t, "sets") is { } array)
        {
            foreach (var set in array.EnumerateArray().Where(s => s.ValueKind == JsonValueKind.Object))
            {
                sets.Add(new TyreSetState(
                    RaceSample.VisualCompoundOf(JsonReads.Int(set, "visualCompound") ?? 0),
                    JsonReads.Int(set, "wearPercent"),
                    JsonReads.Bool(set, "available") ?? false,
                    JsonReads.Int(set, "lifeSpanLaps"),
                    JsonReads.Int(set, "usableLifeLaps"),
                    JsonReads.Int(set, "lapDeltaTimeMs")));
            }
        }

        return new LapTyreState(
            lap.LapNumber,
            session is { } s1 && JsonReads.Int(s1, "pitStopWindowIdealLap") is > 0 and var ideal ? ideal : null,
            session is { } s2 && JsonReads.Int(s2, "pitStopWindowLatestLap") is > 0 and var latest ? latest : null,
            tyreSets is { } t2 ? JsonReads.Int(t2, "fittedIndex") : null,
            sets);
    }
}

/// <summary>
/// 타이어로 본 전략(순수 계산). 스톱마다 인 랩 스냅샷의 게임 피트 창·끼운 세트 마모·남은 수명과, 다음에 끼운 세트의 게임 타이어 델타(랩당 빨라지는 정도).
/// 컴파운드 모델은 게임 타이어 델타로 만든다: 출발 때 그 컴파운드의 가장 덜 닳은 세트 델타 = 새 타이어 랩타임 차,
/// 그 컴파운드로 달린 스틴트에서 바뀌지 않는 다른 세트 델타가 랩마다 줄어드는 기울기 = 랩당 느려지는 정도(내 주행으로 닳은 속도).
/// 대안 전략은 스톱 수(1~<see cref="MaxStops"/>)마다 총 시간 = Σ(랩 수 × 새 타이어 차 + 기울기 × 랩 수(랩 수 − 1)/2) + 스톱 × 내 스톱 손실이
/// 가장 작은 것 — 스틴트는 <see cref="MinStintLaps"/>랩 이상·게임이 본 쓸 수 있는 랩 이하, 세트 수 안, 드라이 컴파운드 두 가지 이상(규정),
/// 출발 타이어는 실제와 같다(그리드 규정·출발 전 선택이라 레이스 중 판단과 따로 본다). 연료·트래픽은 전략마다 같다고 본 추정이다.
/// </summary>
internal static class RaceStrategyAnalyzer
{
    private const int MaxStops = 3;
    private const int MinStintLaps = 3;
    private const int MinDegLaps = 3;
    private const int MinDistinctCompounds = 2;

    private static readonly TyreCompound[] DryCompounds = [TyreCompound.Soft, TyreCompound.Medium, TyreCompound.Hard];

    public static RaceStrategyAnalysisDto? Build(RaceReviewBuilder.CarRace mine, IReadOnlyList<MySessionLap> myLaps, int totalLaps)
    {
        ArgumentNullException.ThrowIfNull(mine);
        ArgumentNullException.ThrowIfNull(myLaps);

        var states = SessionLapsBuilder.LatestByLapNumber(myLaps).Values
            .Select(LapTyreState.From)
            .OfType<LapTyreState>()
            .OrderBy(s => s.LapNumber)
            .ToList();
        if (states.Count == 0 || mine.Spans.Count == 0)
        {
            return null;
        }

        var start = states[0];
        var losses = mine.Spans.Take(mine.Spans.Count - 1).Select(s => mine.PitLossMs(s.EndLap)).OfType<int>().Select(ms => (double)ms).ToList();
        int? pitLoss = losses.Count == 0 ? null : RaceReviewBuilder.Round(RaceReviewBuilder.Median(losses));
        var compounds = Compounds(mine, states, start);
        var raceLaps = totalLaps > 0 ? totalLaps : mine.Laps.Count == 0 ? 0 : mine.Laps[^1].LapNumber;

        return new RaceStrategyAnalysisDto(
            raceLaps,
            start.IdealLap,
            start.LatestLap,
            pitLoss,
            Stops(mine, states),
            compounds,
            pitLoss is { } loss && raceLaps > 0 ? Options(mine, compounds, raceLaps, loss) : []);
    }

    private static List<RaceStopContextDto> Stops(RaceReviewBuilder.CarRace mine, IReadOnlyList<LapTyreState> states)
    {
        var stops = new List<RaceStopContextDto>();
        for (var i = 0; i < mine.Spans.Count - 1; i++)
        {
            var inLap = mine.Spans[i].EndLap;
            var before = states.LastOrDefault(s => s.LapNumber <= inLap);
            var after = states.FirstOrDefault(s => s.LapNumber > inLap);
            var newSet = before is not null && after?.FittedIndex is { } next && next >= 0 && next < before.Sets.Count ? before.Sets[next] : null;
            stops.Add(new RaceStopContextDto(
                inLap,
                before?.IdealLap,
                before?.LatestLap,
                before?.Fitted?.WearPct,
                before?.Fitted?.LifeSpanLaps,
                mine.Spans[i].VisualCompound,
                mine.Spans[i + 1].VisualCompound,
                newSet?.LapDeltaTimeMs is { } delta ? -delta : null));
        }

        return stops;
    }

    private static List<RaceCompoundModelDto> Compounds(RaceReviewBuilder.CarRace mine, IReadOnlyList<LapTyreState> states, LapTyreState start)
    {
        var models = new List<RaceCompoundModelDto>();
        foreach (var compound in DryCompounds)
        {
            var sets = start.Sets.Where(s => s.Compound == compound && s.Available).ToList();
            if (sets.Count == 0)
            {
                continue;
            }

            var freshest = sets.OrderBy(s => s.WearPct ?? int.MaxValue).First();
            var degs = mine.Spans
                .Where(s => s.VisualCompound == compound.ToString())
                .Select(s => Degradation(states, s))
                .OfType<double>()
                .ToList();
            models.Add(new RaceCompoundModelDto(
                compound.ToString(),
                freshest.LapDeltaTimeMs,
                degs.Count == 0 ? null : RaceReviewBuilder.Round(degs.Average()),
                freshest.UsableLifeLaps,
                sets.Count));
        }

        return models;
    }

    /// <summary>
    /// 스틴트에서 끼운 세트가 랩당 느려진 정도(ms/랩): 스틴트 내내 마모가 그대로인(안 쓴) 다른 세트의 델타가 랩마다 줄어드는 기울기의 반대.
    /// 끼운 세트가 바뀌지 않은 랩이 <see cref="MinDegLaps"/>보다 적거나 기준 세트가 없으면 null.
    /// </summary>
    private static double? Degradation(IReadOnlyList<LapTyreState> states, StintSpan span)
    {
        var laps = states.Where(s => span.Contains(s.LapNumber) && s.FittedIndex is not null).ToList();
        if (laps.Count == 0)
        {
            return null;
        }

        // 스틴트 첫 랩의 끼운 세트를 끝까지 쓴 랩만(피트 랩에 새 세트로 바뀐 랩은 뺀다).
        var fitted = laps[0].FittedIndex;
        laps = laps.Where(s => s.FittedIndex == fitted).ToList();
        if (laps.Count < MinDegLaps)
        {
            return null;
        }

        var setCount = laps.Min(s => s.Sets.Count);
        var reference = Enumerable.Range(0, setCount)
            .Where(i => i != fitted
                        && laps.All(s => s.Sets[i].LapDeltaTimeMs.HasValue && s.Sets[i].WearPct == laps[0].Sets[i].WearPct))
            .Select(i => (int?)i)
            .FirstOrDefault();
        if (reference is not { } r)
        {
            return null;
        }

        var points = laps.Select(s => (Lap: (double)s.LapNumber, Value: -(double)s.Sets[r].LapDeltaTimeMs!.Value)).ToList();
        var meanLap = points.Average(p => p.Lap);
        var meanValue = points.Average(p => p.Value);
        var spread = points.Sum(p => (p.Lap - meanLap) * (p.Lap - meanLap));
        return spread == 0 ? null : points.Sum(p => (p.Lap - meanLap) * (p.Value - meanValue)) / spread;
    }

    private static List<RaceStrategyOptionDto> Options(
        RaceReviewBuilder.CarRace mine, IReadOnlyList<RaceCompoundModelDto> compounds, int raceLaps, int pitLossMs)
    {
        var usable = compounds.Where(c => c is { OffsetMs: not null, DegMsPerLap: not null }).ToDictionary(c => c.Compound);
        var actual = mine.Spans
            .Select((s, i) => (Compound: s.VisualCompound, Laps: (i == mine.Spans.Count - 1 ? raceLaps : Math.Min(s.EndLap, raceLaps)) - s.StartLap + 1))
            .Where(s => s.Laps > 0)
            .ToList();
        if (actual.Count == 0 || actual.Any(s => !usable.ContainsKey(s.Compound)))
        {
            return [];
        }

        double StintCost(string compound, int laps)
        {
            var model = usable[compound];
            return laps * model.OffsetMs!.Value + model.DegMsPerLap!.Value * laps * (laps - 1) / 2.0;
        }

        var actualCost = actual.Sum(s => StintCost(s.Compound, s.Laps)) + (actual.Count - 1) * pitLossMs;
        var options = new List<RaceStrategyOptionDto>
        {
            new(actual.Select(s => new RaceStrategyStintDto(s.Compound, s.Laps)).ToList(), 0, IsActual: true),
        };

        var names = usable.Keys.ToList();
        for (var stops = 1; stops <= MaxStops; stops++)
        {
            (double Cost, List<(string Compound, int Laps)> Plan)? best = null;
            foreach (var sequence in Sequences(names, stops + 1))
            {
                if (sequence[0] != actual[0].Compound
                    || sequence.Distinct().Count() < MinDistinctCompounds
                    || sequence.GroupBy(c => c).Any(g => g.Count() > usable[g.Key].Sets))
                {
                    continue;
                }

                var maxLaps = sequence.Select(c => usable[c].UsableLaps ?? raceLaps).ToArray();
                foreach (var lengths in Lengths(maxLaps, raceLaps))
                {
                    var cost = sequence.Select((c, i) => StintCost(c, lengths[i])).Sum() + stops * pitLossMs;
                    if (best is null || cost < best.Value.Cost)
                    {
                        best = (cost, sequence.Select((c, i) => (c, lengths[i])).ToList());
                    }
                }
            }

            if (best is { } found && !found.Plan.SequenceEqual(actual))
            {
                options.Add(new RaceStrategyOptionDto(
                    found.Plan.Select(p => new RaceStrategyStintDto(p.Compound, p.Laps)).ToList(),
                    RaceReviewBuilder.Round(found.Cost - actualCost),
                    IsActual: false));
            }
        }

        return options;
    }

    /// <summary>컴파운드 [count]개 순서(같은 컴파운드 반복 가능).</summary>
    private static IEnumerable<List<string>> Sequences(IReadOnlyList<string> names, int count)
    {
        if (count == 0)
        {
            yield return [];
            yield break;
        }

        foreach (var head in names)
        {
            foreach (var tail in Sequences(names, count - 1))
            {
                yield return [head, .. tail];
            }
        }
    }

    /// <summary>스틴트 랩 수 조합: 각 <see cref="MinStintLaps"/>~[maxLaps]랩, 합 = [total].</summary>
    private static IEnumerable<int[]> Lengths(int[] maxLaps, int total)
    {
        var lengths = new int[maxLaps.Length];

        IEnumerable<int[]> Fill(int index, int remaining)
        {
            if (index == maxLaps.Length - 1)
            {
                if (remaining >= MinStintLaps && remaining <= maxLaps[index])
                {
                    lengths[index] = remaining;
                    yield return (int[])lengths.Clone();
                }

                yield break;
            }

            var restMin = MinStintLaps * (maxLaps.Length - index - 1);
            for (var laps = MinStintLaps; laps <= Math.Min(maxLaps[index], remaining - restMin); laps++)
            {
                lengths[index] = laps;
                foreach (var filled in Fill(index + 1, remaining - laps))
                {
                    yield return filled;
                }
            }
        }

        return Fill(0, total);
    }
}
