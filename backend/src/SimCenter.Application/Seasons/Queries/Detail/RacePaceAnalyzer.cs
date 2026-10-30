namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 내 랩마다 페이스 기준 세 가지를 붙인다(순수 계산): 같은 랩(연료·노면이 같다) 다른 차들 깨끗한 랩 중앙값, 같은 컴파운드·타이어 나이
/// (± <see cref="SameTyreAgeWindow"/>랩)로 레이스 랩도 가까운(± <see cref="SameTyreLapWindow"/>랩 — 연료 차이를 줄인다) 다른 차들 깨끗한 랩 중앙값
/// (타이어 조건을 맞춘 실력 비교, 그런 랩이 <see cref="MinSameTyreLaps"/>개보다 적으면 null). 타이어 나이 = 랩 − 스틴트 첫 랩.
/// </summary>
internal static class RacePaceAnalyzer
{
    private const int SameTyreAgeWindow = 1;
    private const int SameTyreLapWindow = 5;
    private const int MinSameTyreLaps = 3;

    public static IReadOnlyList<RaceLapPaceDto> Build(RaceReviewBuilder.CarRace mine, IReadOnlyList<RaceReviewBuilder.CarRace> cars)
    {
        ArgumentNullException.ThrowIfNull(mine);
        ArgumentNullException.ThrowIfNull(cars);

        var others = cars.Where(c => !ReferenceEquals(c, mine)).ToList();
        var sameLap = others
            .SelectMany(c => c.Clean)
            .GroupBy(l => l.LapNumber)
            .ToDictionary(g => g.Key, g => RaceReviewBuilder.Round(RaceReviewBuilder.Median(g.Select(l => (double)l.LapTimeMs))));
        var tyreLaps = others
            .SelectMany(c => c.Clean.Select(l => (Tyre: TyreAt(c, l.LapNumber), l.LapNumber, l.LapTimeMs)))
            .Where(x => x.Tyre is not null)
            .Select(x => (x.Tyre!.Value.Compound, x.Tyre.Value.Age, x.LapNumber, x.LapTimeMs))
            .ToList();
        var clean = mine.Clean.Select(l => l.LapNumber).ToHashSet();

        return mine.Laps
            .Select(lap =>
            {
                var tyre = TyreAt(mine, lap.LapNumber);
                var matched = tyre is { } t
                    ? tyreLaps
                        .Where(x => x.Compound == t.Compound
                                    && Math.Abs(x.Age - t.Age) <= SameTyreAgeWindow
                                    && Math.Abs(x.LapNumber - lap.LapNumber) <= SameTyreLapWindow)
                        .Select(x => (double)x.LapTimeMs)
                        .ToList()
                    : [];
                return new RaceLapPaceDto(
                    lap.LapNumber,
                    lap.LapTimeMs,
                    sameLap.TryGetValue(lap.LapNumber, out var field) ? field : null,
                    matched.Count < MinSameTyreLaps ? null : RaceReviewBuilder.Round(RaceReviewBuilder.Median(matched)),
                    tyre?.Compound,
                    tyre?.Age,
                    clean.Contains(lap.LapNumber));
            })
            .ToList();
    }

    /// <summary>그 랩의 컴파운드·타이어 나이(마지막 스틴트 끝을 넘은 랩은 마지막 스틴트). 스틴트가 없으면 null.</summary>
    private static (string Compound, int Age)? TyreAt(RaceReviewBuilder.CarRace car, int lapNumber)
    {
        if (car.Spans.Count == 0)
        {
            return null;
        }

        var span = car.Spans.FirstOrDefault(s => s.Contains(lapNumber)) ?? car.Spans[^1];
        return (span.VisualCompound, lapNumber - span.StartLap);
    }
}
