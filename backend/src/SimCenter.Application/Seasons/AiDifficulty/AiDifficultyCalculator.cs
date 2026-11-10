using SimCenter.Application.Common;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.AiDifficulty;

/// <summary>
/// 시즌 AI 난이도 가이드 계산(순수 함수 — 상태 없음).
/// 기준은 같은 차를 탄 AI 팀메이트다: 예선은 둘 다 기록한 마지막 단계의 최고 랩 차이, 레이스는 둘 다 완주한 판의 랩당 평균 차이.
/// 차 성능이 같으니 남는 차이가 곧 "나 대 이 난이도의 AI"다. 판정은 지금 난이도(가장 최근 레이스)로 달린 세션의 중앙값으로 한다:
/// ±<see cref="KeepBandPercent"/>% 안이면 적정, 내가 빠르면 올리기, 느리면 낮추기. 폭은 <see cref="LargeGapPercent"/>% 기준의 추정이다.
/// 타임트라이얼 비교는 마른 노면(내 랩 날씨가 모두 Overcast 이하) 예선의 가장 빠른 AI 랩과 내 TT 최고 랩(마른 노면·날씨 모름)이다.
/// </summary>
public static class AiDifficultyCalculator
{
    public const string VerdictRaise = "Raise";
    public const string VerdictKeep = "Keep";
    public const string VerdictLower = "Lower";
    public const string VerdictNotEnoughData = "NotEnoughData";
    public const string StepsSmall = "1-2";
    public const string StepsLarge = "3+";

    /// <summary>팀메이트와 차이가 이 안쪽(%)이면 지금 난이도가 맞다.</summary>
    public const double KeepBandPercent = 0.3;

    /// <summary>차이가 이 이상(%)이면 3단계 이상 바꿀 만하다(추정).</summary>
    public const double LargeGapPercent = 1.0;

    /// <summary>판정에 필요한 최소 세션 수.</summary>
    public const int MinSamples = 3;

    private const double PercentScale = 100.0;
    private const int PercentDigits = 2;
    private const int PositionDigits = 1;

    private static readonly HashSet<SessionKind> MainQualifyingKinds =
    [
        SessionKind.Qualifying1, SessionKind.Qualifying2, SessionKind.Qualifying3,
        SessionKind.ShortQualifying, SessionKind.OneShotQualifying,
    ];

    public static SeasonAiDifficultyDto Calculate(
        string gameCode,
        IReadOnlyList<WeekendRow> weekends,
        IReadOnlyDictionary<Guid, int> rounds,
        IReadOnlyList<AiPaceRow> rows,
        IReadOnlyList<SessionLapWeatherRow> weather,
        IReadOnlyList<TimeTrialLapRow> timeTrialLaps)
    {
        ArgumentNullException.ThrowIfNull(weekends);
        ArgumentNullException.ThrowIfNull(rounds);
        ArgumentNullException.ThrowIfNull(rows);
        ArgumentNullException.ThrowIfNull(weather);
        ArgumentNullException.ThrowIfNull(timeTrialLaps);

        var sessions = rows.GroupBy(r => r.SessionId).Select(g => SessionView.Of(g.ToList(), gameCode)).ToList();
        var byWeekend = sessions.ToLookup(s => s.WeekendId);
        var weatherByKey = weather.ToLookup(w => w.SessionKey, w => w.Weather);
        var timeTrialBest = BestDryTimeTrial(timeTrialLaps);

        var weekendViews = weekends
            .Where(w => byWeekend[w.WeekendId].Any())
            .OrderBy(w => rounds.GetValueOrDefault(w.WeekendId))
            .ThenBy(w => w.FirstSessionAt)
            .Select(w => WeekendView.Of(w, rounds.GetValueOrDefault(w.WeekendId), byWeekend[w.WeekendId], weatherByKey))
            .ToList();

        var currentAi = CurrentAiDifficulty(sessions);

        return new SeasonAiDifficultyDto(
            currentAi,
            QualifyingVerdict(weekendViews, currentAi),
            RaceVerdict(weekendViews, currentAi),
            CarLevel(weekendViews),
            weekendViews.Select(ToDto).ToList(),
            TimeTrialRows(weekendViews, timeTrialBest));
    }

    // ---- 판정 ----

    /// <summary>가장 최근 레이스(없으면 예선)의 AI 난이도. 모르면(0) null.</summary>
    private static int? CurrentAiDifficulty(IReadOnlyList<SessionView> sessions)
    {
        var latest = sessions.Where(s => s.Type == SessionType.Race && s.AiDifficulty > 0).MaxBy(s => s.ClassifiedAt)
            ?? sessions.Where(s => s.AiDifficulty > 0).MaxBy(s => s.ClassifiedAt);
        return latest?.AiDifficulty;
    }

    private static AiVerdictDto QualifyingVerdict(IReadOnlyList<WeekendView> weekends, int? currentAi)
    {
        var samples = weekends
            .Where(w => w.QualiGap is not null && w.QualiGapAi == currentAi)
            .Select(w => w.QualiGap!.Value)
            .ToList();
        return Verdict(samples, samples.Count(s => s.Ms < 0));
    }

    private static AiVerdictDto RaceVerdict(IReadOnlyList<WeekendView> weekends, int? currentAi)
    {
        var races = weekends
            .SelectMany(w => w.Races)
            .Where(r => r.PaceGap is not null && r.AiDifficulty == currentAi)
            .ToList();
        return Verdict(
            races.Select(r => r.PaceGap!.Value).ToList(),
            races.Count(r => r.MyPosition is { } mine && r.TeammatePosition is { } theirs && mine < theirs));
    }

    private static AiVerdictDto Verdict(IReadOnlyList<Gap> samples, int ahead)
    {
        if (samples.Count == 0)
        {
            return new AiVerdictDto(VerdictNotEnoughData, null, null, null, 0, 0);
        }

        var medianPercent = Math.Round(Median(samples.Select(s => s.Percent).ToList()), PercentDigits);
        var medianMs = (int)Math.Round(Median(samples.Select(s => (double)s.Ms).ToList()));
        if (samples.Count < MinSamples)
        {
            return new AiVerdictDto(VerdictNotEnoughData, null, medianPercent, medianMs, samples.Count, ahead);
        }

        var size = Math.Abs(medianPercent);
        if (size < KeepBandPercent)
        {
            return new AiVerdictDto(VerdictKeep, null, medianPercent, medianMs, samples.Count, ahead);
        }

        return new AiVerdictDto(
            medianPercent < 0 ? VerdictRaise : VerdictLower,
            size >= LargeGapPercent ? StepsLarge : StepsSmall,
            medianPercent,
            medianMs,
            samples.Count,
            ahead);
    }

    private static double Median(IReadOnlyList<double> values)
    {
        var sorted = values.Order().ToList();
        var middle = sorted.Count / 2;
        return sorted.Count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
    }

    // ---- 차 수준 ----

    private static AiCarLevelDto CarLevel(IReadOnlyList<WeekendView> weekends)
    {
        static double? Average(IEnumerable<int?> values)
        {
            var known = values.Where(v => v is > 0).Select(v => (double)v!.Value).ToList();
            return known.Count == 0 ? null : Math.Round(known.Average(), PositionDigits);
        }

        var mainRaces = weekends.Select(w => w.Races.LastOrDefault(r => !r.IsSprint)).Where(r => r is not null).ToList();
        return new AiCarLevelDto(
            Average(weekends.Select(w => w.TeammateQualiPosition)),
            Average(mainRaces.Select(r => r!.TeammatePosition)),
            Average(weekends.Select(w => w.MyQualiPosition)),
            Average(mainRaces.Select(r => r!.MyPosition)));
    }

    // ---- 타임트라이얼 ----

    /// <summary>트랙별 내 TT 최고 랩(마른 노면이거나 날씨를 모르는 랩만).</summary>
    private static Dictionary<Guid, int> BestDryTimeTrial(IReadOnlyList<TimeTrialLapRow> laps)
        => laps
            .Where(l => l.LapTimeMs > 0 && (l.Weather is null || IsDry(l.Weather.Value)))
            .GroupBy(l => l.TrackId)
            .ToDictionary(g => g.Key, g => g.Min(l => l.LapTimeMs));

    private static List<AiTimeTrialDto> TimeTrialRows(IReadOnlyList<WeekendView> weekends, Dictionary<Guid, int> timeTrialBest)
    {
        var result = new List<AiTimeTrialDto>();
        foreach (var w in weekends)
        {
            if (w.QualiWeather is not { } worst || !IsDry(worst) || w.AiFastestQualiMs is not { } aiFastest
                || w.QualiAiDifficulty is not { } ai || !timeTrialBest.TryGetValue(w.Row.TrackId, out var tt))
            {
                continue;
            }

            result.Add(new AiTimeTrialDto(
                w.Row.WeekendId,
                w.Row.TrackName,
                w.Row.CountryCode,
                tt,
                aiFastest,
                ai,
                Math.Round((tt - aiFastest) * PercentScale / aiFastest, PercentDigits)));
        }

        return result;
    }

    private static bool IsDry(Weather weather) => weather < Weather.LightRain;

    // ---- 매핑 ----

    private static AiWeekendDto ToDto(WeekendView w) => new(
        w.Row.WeekendId,
        w.Round,
        w.Row.TrackName,
        w.Row.CountryCode,
        w.AiDifficulty,
        w.QualiWeather?.ToString(),
        w.TeammateName,
        w.MyQualiPosition,
        w.TeammateQualiPosition,
        w.QualiGap?.Ms,
        w.QualiGap?.Percent,
        w.Races.Select(r => new AiRaceDto(
            r.SessionId,
            r.Kind.ToString(),
            r.IsSprint,
            r.MyGrid,
            r.MyPosition,
            r.TeammatePosition,
            r.PaceGap?.Ms,
            r.PaceGap?.Percent,
            r.MyResultStatus?.ToString())).ToList());

    private static Gap? GapOf(int mine, int theirs)
        => mine > 0 && theirs > 0
            ? new Gap(mine - theirs, Math.Round((mine - theirs) * PercentScale / theirs, PercentDigits))
            : null;

    private static int? Known(int? position) => position is > 0 ? position : null;

    // ---- 보기 ----

    /// <summary>팀메이트 대비 차이(ms, %). 음수 = 내가 빠름.</summary>
    private readonly record struct Gap(int Ms, double Percent);

    /// <summary>세션 하나: 내 행과 팀메이트 행(같은 팀 대표 ID의 다른 차, 팀을 모르면 없음).</summary>
    private sealed record SessionView(
        Guid WeekendId,
        Guid SessionId,
        string SessionKey,
        SessionType Type,
        SessionKind Kind,
        DateTime ClassifiedAt,
        int AiDifficulty,
        IReadOnlyList<AiPaceRow> Rows,
        AiPaceRow? Me,
        AiPaceRow? Teammate)
    {
        public static SessionView Of(List<AiPaceRow> rows, string gameCode)
        {
            var head = rows[0];
            var me = rows.Where(r => r.IsPlayer).OrderBy(r => r.CarIndex).FirstOrDefault();
            AiPaceRow? teammate = null;
            if (me?.TeamId is { } myTeam)
            {
                var team = TeamCatalog.CanonicalTeamId(gameCode, myTeam);
                teammate = rows
                    .Where(r => !r.IsPlayer && r.TeamId is { } t && TeamCatalog.CanonicalTeamId(gameCode, t) == team)
                    .OrderBy(r => r.CarIndex)
                    .FirstOrDefault();
            }

            return new SessionView(
                head.WeekendId, head.SessionId, head.SessionKey, head.SessionType, head.SessionKind, head.ClassifiedAt,
                head.AiDifficulty, rows, me, teammate);
        }
    }

    private sealed record RaceView(
        Guid SessionId,
        SessionKind Kind,
        bool IsSprint,
        int? AiDifficulty,
        int? MyGrid,
        int? MyPosition,
        int? TeammatePosition,
        Gap? PaceGap,
        ResultStatus? MyResultStatus);

    private sealed record WeekendView(
        WeekendRow Row,
        int Round,
        int? AiDifficulty,
        string? TeammateName,
        int? MyQualiPosition,
        int? TeammateQualiPosition,
        Gap? QualiGap,
        int? QualiGapAi,
        int? QualiAiDifficulty,
        Weather? QualiWeather,
        int? AiFastestQualiMs,
        IReadOnlyList<RaceView> Races)
    {
        public static WeekendView Of(
            WeekendRow row, int round, IEnumerable<SessionView> weekendSessions, ILookup<string, Weather> weatherByKey)
        {
            var ordered = weekendSessions.OrderBy(s => s.ClassifiedAt).ToList();
            var qualifying = ordered.Where(s => s.Type == SessionType.Qualifying).ToList();
            var mainQualifying = qualifying.Where(s => MainQualifyingKinds.Contains(s.Kind)).ToList();
            var chosen = mainQualifying.Count > 0 ? mainQualifying : qualifying;

            var gapSession = chosen.LastOrDefault(s => s.Me is { BestLapTimeMs: > 0 } && s.Teammate is { BestLapTimeMs: > 0 });
            var weatherValues = chosen.SelectMany(s => weatherByKey[s.SessionKey]).ToList();
            var aiTimes = chosen
                .SelectMany(s => s.Rows)
                .Where(r => r.IsAiControlled && !r.IsPlayer && r.BestLapTimeMs > 0)
                .Select(r => r.BestLapTimeMs)
                .ToList();

            var raceSessions = ordered.Where(s => s.Type == SessionType.Race).ToList();
            var sprintWeekend = raceSessions.Any(s => s.Kind == SessionKind.Race2);
            var races = raceSessions.Select(s => new RaceView(
                s.SessionId,
                s.Kind,
                sprintWeekend && s.Kind == SessionKind.Race,
                s.AiDifficulty > 0 ? s.AiDifficulty : null,
                Known(s.Me?.GridPosition),
                Known(s.Me?.Position),
                Known(s.Teammate?.Position),
                PaceGapOf(s.Me, s.Teammate),
                s.Me?.ResultStatus)).ToList();

            var mainRace = races.LastOrDefault(r => !r.IsSprint);
            var qualiAi = chosen.LastOrDefault(s => s.AiDifficulty > 0)?.AiDifficulty;

            return new WeekendView(
                row,
                round,
                mainRace?.AiDifficulty ?? qualiAi,
                ordered.Select(s => s.Teammate?.DriverName).LastOrDefault(n => n is not null),
                Known(chosen.LastOrDefault(s => s.Me is { Position: > 0 })?.Me!.Position),
                Known(chosen.LastOrDefault(s => s.Teammate is { Position: > 0 })?.Teammate!.Position),
                gapSession is null ? null : GapOf(gapSession.Me!.BestLapTimeMs, gapSession.Teammate!.BestLapTimeMs),
                gapSession is { AiDifficulty: > 0 } ? gapSession.AiDifficulty : null,
                qualiAi,
                weatherValues.Count == 0 ? null : weatherValues.Max(),
                aiTimes.Count == 0 ? null : aiTimes.Min(),
                races);
        }

        /// <summary>둘 다 완주하고 랩 수가 같으면 (내 총 시간 − 팀메이트 총 시간) ÷ 랩 수.</summary>
        private static Gap? PaceGapOf(AiPaceRow? me, AiPaceRow? teammate)
        {
            if (me is not { ResultStatus: ResultStatus.Finished, NumLaps: > 0, TotalRaceTimeMs: > 0 }
                || teammate is not { ResultStatus: ResultStatus.Finished, TotalRaceTimeMs: > 0 }
                || teammate.NumLaps != me.NumLaps)
            {
                return null;
            }

            var myLap = (double)me.TotalRaceTimeMs / me.NumLaps;
            var theirLap = (double)teammate.TotalRaceTimeMs / teammate.NumLaps;
            return new Gap((int)Math.Round(myLap - theirLap), Math.Round((myLap - theirLap) * PercentScale / theirLap, PercentDigits));
        }
    }
}
