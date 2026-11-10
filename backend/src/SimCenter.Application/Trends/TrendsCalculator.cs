using SimCenter.Application.Seasons.AiDifficulty;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Trends;

/// <summary>
/// 내 성과 추세 계산(순수 함수 — 상태 없음). 세션마다 나 대 AI 팀메이트 비교는 <see cref="SessionComparison"/>를 쓴다.
/// 꾸준함 = 레이스에서 첫 랩을 뺀 내 랩 중 중앙값의 <see cref="CleanLapLimit"/>배 이내(피트·세이프티카 랩 제외)의 표준편차.
/// </summary>
public static class TrendsCalculator
{
    /// <summary>깨끗한 랩 기준: 그 레이스 내 랩 중앙값의 이 배수 이내.</summary>
    public const double CleanLapLimit = 1.07;

    /// <summary>꾸준함을 낼 최소 깨끗한 랩 수.</summary>
    public const int MinCleanLaps = 5;

    private const int FirstRacingLap = 2;
    private const double PercentScale = 100.0;
    private const int PercentDigits = 2;
    private const int DaysPerWeek = 7;
    private const string UnknownTrack = "Unknown";

    public static TrendsDto Calculate(
        IReadOnlyList<TrendResultRow> rows,
        IReadOnlyList<TrendLapRow> laps,
        IReadOnlyDictionary<Guid, TrendTrackLabel> tracks)
    {
        ArgumentNullException.ThrowIfNull(rows);
        ArgumentNullException.ThrowIfNull(laps);
        ArgumentNullException.ThrowIfNull(tracks);

        var sessions = rows
            .GroupBy(r => r.Result.SessionId)
            .Select(g =>
            {
                var meta = g.First();
                return new SessionView(meta, SessionComparison.Of(g.Select(r => r.Result).ToList(), meta.GameCode));
            })
            .Where(s => s.Comparison.Me is not null)
            .OrderBy(s => s.Comparison.ClassifiedAt)
            .ToList();
        var weekends = sessions.Where(s => s.Meta.HasWeekend).ToLookup(s => s.Comparison.WeekendId);
        var lapsBySession = laps.Where(l => l.SessionKey is not null).ToLookup(l => l.SessionKey!);

        TrendTrackLabel Label(Guid trackId) => tracks.GetValueOrDefault(trackId) ?? new TrendTrackLabel(UnknownTrack, null);

        return new TrendsDto(
            Races(sessions, weekends, lapsBySession, Label),
            Qualifying(weekends, Label),
            WeeklyLaps(laps),
            TrackProgressions(laps, Label));
    }

    // ---- 레이스 ----

    private static List<RaceTrendDto> Races(
        IReadOnlyList<SessionView> sessions,
        ILookup<Guid, SessionView> weekends,
        ILookup<string, TrendLapRow> lapsBySession,
        Func<Guid, TrendTrackLabel> label)
    {
        var result = new List<RaceTrendDto>();
        foreach (var session in sessions.Where(s => s.Comparison.Type == SessionType.Race))
        {
            var c = session.Comparison;
            var weekendRaces = session.Meta.HasWeekend
                ? weekends[c.WeekendId].Where(s => s.Comparison.Type == SessionType.Race).ToList()
                : [session];
            var isSprint = c.Kind == SessionKind.Race && weekendRaces.Any(s => s.Comparison.Kind == SessionKind.Race2);
            var track = label(session.Meta.TrackId);
            var consistency = Consistency(lapsBySession[c.SessionKey]);

            result.Add(new RaceTrendDto(
                c.SessionId,
                c.ClassifiedAt,
                track.Name,
                track.CountryCode,
                c.Kind.ToString(),
                isSprint,
                session.Meta.GameMode.ToString(),
                c.AiDifficulty > 0 ? c.AiDifficulty : null,
                SessionComparison.Known(c.Me!.GridPosition),
                SessionComparison.Known(c.Me.Position),
                c.Me.ResultStatus.ToString(),
                c.PaceGap?.Ms,
                FieldPaceGap(c),
                consistency?.StdDevMs,
                consistency?.CleanLaps));
        }

        return result;
    }

    /// <summary>내 최고 랩 대 AI 최고 랩 중앙값(%). 둘 중 하나라도 없으면 null.</summary>
    private static double? FieldPaceGap(SessionComparison c)
    {
        var aiBests = c.Rows.Where(r => r.IsAiControlled && !r.IsPlayer && r.BestLapTimeMs > 0).Select(r => (double)r.BestLapTimeMs).ToList();
        if (c.Me is not { BestLapTimeMs: > 0 } me || aiBests.Count == 0)
        {
            return null;
        }

        var median = Median(aiBests);
        return Math.Round((me.BestLapTimeMs - median) * PercentScale / median, PercentDigits);
    }

    /// <summary>첫 랩을 뺀 랩 중 중앙값의 <see cref="CleanLapLimit"/>배 이내의 (모)표준편차. 깨끗한 랩이 모자라면 null.</summary>
    private static (int StdDevMs, int CleanLaps)? Consistency(IEnumerable<TrendLapRow> sessionLaps)
    {
        var times = sessionLaps
            .Where(l => l.LapNumber >= FirstRacingLap && l.LapTimeMs > 0)
            .GroupBy(l => l.LapNumber)
            .Select(g => (double)g.First().LapTimeMs)
            .ToList();
        if (times.Count < MinCleanLaps)
        {
            return null;
        }

        var limit = Median(times) * CleanLapLimit;
        var clean = times.Where(t => t <= limit).ToList();
        if (clean.Count < MinCleanLaps)
        {
            return null;
        }

        var mean = clean.Average();
        var variance = clean.Sum(t => (t - mean) * (t - mean)) / clean.Count;
        return ((int)Math.Round(Math.Sqrt(variance)), clean.Count);
    }

    // ---- 예선 ----

    private static List<QualifyingTrendDto> Qualifying(ILookup<Guid, SessionView> weekends, Func<Guid, TrendTrackLabel> label)
    {
        var result = new List<QualifyingTrendDto>();
        foreach (var weekend in weekends)
        {
            var summary = SessionComparison.Qualifying(weekend.Select(s => s.Comparison));
            if (summary.Parts.Count == 0 || summary.MyPosition is null && summary.Gap is null)
            {
                continue;
            }

            var track = label(weekend.First().Meta.TrackId);
            result.Add(new QualifyingTrendDto(
                weekend.Key,
                summary.Parts[^1].ClassifiedAt,
                track.Name,
                track.CountryCode,
                summary.AiDifficulty,
                summary.MyPosition,
                summary.Gap?.Ms,
                summary.Gap?.Percent));
        }

        return result.OrderBy(q => q.At).ToList();
    }

    // ---- 주행량 ----

    /// <summary>주(월요일 시작, UTC 날짜)마다 랩 수. 첫 주부터 마지막 주까지 빈 주는 0으로 채운다.</summary>
    private static List<WeeklyLapsDto> WeeklyLaps(IReadOnlyList<TrendLapRow> laps)
    {
        if (laps.Count == 0)
        {
            return [];
        }

        var counts = laps.GroupBy(l => WeekStart(l.SetAt)).ToDictionary(g => g.Key, g => g.Count());
        var first = counts.Keys.Min();
        var last = counts.Keys.Max();
        var result = new List<WeeklyLapsDto>();
        for (var week = first; week <= last; week = week.AddDays(DaysPerWeek))
        {
            result.Add(new WeeklyLapsDto(week, counts.GetValueOrDefault(week)));
        }

        return result;
    }

    private static DateOnly WeekStart(DateTime at)
    {
        var day = DateOnly.FromDateTime(at);
        var sinceMonday = ((int)day.DayOfWeek + DaysPerWeek - (int)DayOfWeek.Monday) % DaysPerWeek;
        return day.AddDays(-sinceMonday);
    }

    // ---- 트랙별 최고 랩 변화 ----

    private static List<TrackProgressionDto> TrackProgressions(IReadOnlyList<TrendLapRow> laps, Func<Guid, TrendTrackLabel> label)
    {
        var lapCounts = laps.GroupBy(l => l.TrackId).ToDictionary(g => g.Key, g => g.Count());
        return laps
            .Where(l => l.IsValid && l.LapTimeMs > 0)
            .GroupBy(l => l.TrackId)
            .Select(track =>
            {
                var points = new List<TrackProgressionPointDto>();
                var bestSoFar = int.MaxValue;
                foreach (var session in track
                    .GroupBy(l => l.SessionKey ?? $"day:{DateOnly.FromDateTime(l.SetAt):O}")
                    .OrderBy(g => g.Min(l => l.SetAt)))
                {
                    var best = session.MinBy(l => l.LapTimeMs)!;
                    bestSoFar = Math.Min(bestSoFar, best.LapTimeMs);
                    points.Add(new TrackProgressionPointDto(
                        session.Min(l => l.SetAt), best.SessionType.ToString(), best.LapTimeMs, bestSoFar));
                }

                var name = label(track.Key);
                return new TrackProgressionDto(track.Key, name.Name, name.CountryCode, lapCounts[track.Key], points);
            })
            .OrderByDescending(t => t.LapCount)
            .ThenBy(t => t.TrackName, StringComparer.Ordinal)
            .ToList();
    }

    // ---- 공통 ----

    private static double Median(IReadOnlyList<double> values)
    {
        var sorted = values.Order().ToList();
        var middle = sorted.Count / 2;
        return sorted.Count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
    }

    private sealed record SessionView(TrendResultRow Meta, SessionComparison Comparison);
}
