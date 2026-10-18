namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// Tyre Stints 카드 2종(Tyre Life Remaining · Lap Times)의 스틴트별 점 목록(docs/15 §11.3·§11.4, D-53). 순수 계산.
/// x = 스틴트 안 랩(1부터), 랩타임 = Laps 카드 행, 남은 수명 = 내 랩 스냅샷의 <c>100 − 평균 마모</c>.
/// 스틴트 끝은 기록이 있는 마지막 랩으로 자르고(마지막 스틴트는 그 랩까지 늘린다), 랩타임·수명 둘 다 모르는 랩은 뺀다. 랩 기록이 없으면 빈 목록.
/// </summary>
public static class TyreStintSeriesBuilder
{
    public static IReadOnlyList<TyreStintSeriesDto> Build(
        IReadOnlyList<StintSpan> stints,
        IReadOnlyList<SessionLapDto> laps,
        IReadOnlyList<MySessionLap> myLaps)
    {
        ArgumentNullException.ThrowIfNull(stints);
        ArgumentNullException.ThrowIfNull(laps);
        ArgumentNullException.ThrowIfNull(myLaps);

        var lapTimes = laps.GroupBy(l => l.LapNumber).ToDictionary(g => g.Key, g => g.Last().LapTimeMs);
        var lifeByLap = SessionLapsBuilder.LatestByLapNumber(myLaps)
            .Where(pair => pair.Value.TyreLifeRemaining.HasValue)
            .ToDictionary(pair => pair.Key, pair => pair.Value.TyreLifeRemaining);

        var lastKnownLap = lapTimes.Keys.Concat(lifeByLap.Keys).DefaultIfEmpty(0).Max();
        if (lastKnownLap == 0)
        {
            return [];
        }

        var series = new List<TyreStintSeriesDto>();
        foreach (var stint in stints.Where(s => s.StartLap <= lastKnownLap))
        {
            // 마지막 스틴트는 Laps 카드의 타이어 칸(StintSpan.CompoundAt)과 같게 기록 끝까지 본다.
            var endLap = stint.IsLast ? lastKnownLap : Math.Min(stint.EndLap, lastKnownLap);
            var points = new List<TyreStintLapDto>();
            for (var lapNumber = stint.StartLap; lapNumber <= endLap; lapNumber++)
            {
                int? lapTime = lapTimes.TryGetValue(lapNumber, out var time) ? time : null;
                var life = lifeByLap.GetValueOrDefault(lapNumber);
                if (lapTime is null && life is null)
                {
                    continue;
                }

                points.Add(new TyreStintLapDto(lapNumber, lapNumber - stint.StartLap + 1, lapTime, life));
            }

            series.Add(new TyreStintSeriesDto(stint.VisualCompound, stint.StartLap, endLap, points));
        }

        return series;
    }
}
