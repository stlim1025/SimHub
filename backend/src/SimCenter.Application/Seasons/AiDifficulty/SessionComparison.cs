using SimCenter.Application.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.AiDifficulty;

/// <summary>팀메이트 대비 차이(ms, %). 음수 = 내가 빠름.</summary>
public readonly record struct TeammateGap(int Ms, double Percent);

/// <summary>
/// 주말 예선 요약: 본 예선(없으면 스프린트 슛아웃) 단계들 중 내가·팀메이트가 마지막으로 달린 단계의 순위,
/// 둘 다 기록한 마지막 단계의 최고 랩 차이와 그 단계의 AI 난이도(모르면 null).
/// </summary>
public sealed record QualifyingSummary(
    IReadOnlyList<SessionComparison> Parts,
    int? MyPosition,
    int? TeammatePosition,
    TeammateGap? Gap,
    int? GapAiDifficulty,
    int? AiDifficulty);

/// <summary>
/// 세션 하나의 나 대 AI 팀메이트 비교(AI 난이도 가이드·추세가 함께 쓴다, 순수 계산).
/// 팀메이트 = 내 팀과 같은 팀 대표 ID(<see cref="TeamCatalog.CanonicalTeamId"/>)의 다른 차 — 게임이 팀 ID 묶음을 바꿔 보내도 찾는다.
/// </summary>
public sealed record SessionComparison(
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
    private const double PercentScale = 100.0;
    private const int PercentDigits = 2;

    private static readonly HashSet<SessionKind> MainQualifyingKinds =
    [
        SessionKind.Qualifying1, SessionKind.Qualifying2, SessionKind.Qualifying3,
        SessionKind.ShortQualifying, SessionKind.OneShotQualifying,
    ];

    /// <summary>한 세션의 결과 행들(비어 있지 않음)로 비교를 만든다.</summary>
    public static SessionComparison Of(IReadOnlyList<AiPaceRow> rows, string gameCode)
    {
        ArgumentNullException.ThrowIfNull(rows);
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

        return new SessionComparison(
            head.WeekendId, head.SessionId, head.SessionKey, head.SessionType, head.SessionKind, head.ClassifiedAt,
            head.AiDifficulty, rows, me, teammate);
    }

    /// <summary>
    /// 레이스 페이스 차이 = (내 총 시간 − 팀메이트 총 시간) ÷ 랩 수. 둘 다 완주하고 랩 수가 같을 때만(아니면 null).
    /// </summary>
    public TeammateGap? PaceGap
    {
        get
        {
            if (Me is not { ResultStatus: ResultStatus.Finished, NumLaps: > 0, TotalRaceTimeMs: > 0 } me
                || Teammate is not { ResultStatus: ResultStatus.Finished, TotalRaceTimeMs: > 0 } teammate
                || teammate.NumLaps != me.NumLaps)
            {
                return null;
            }

            var myLap = (double)me.TotalRaceTimeMs / me.NumLaps;
            var theirLap = (double)teammate.TotalRaceTimeMs / teammate.NumLaps;
            return new TeammateGap((int)Math.Round(myLap - theirLap), Math.Round((myLap - theirLap) * PercentScale / theirLap, PercentDigits));
        }
    }

    /// <summary>두 시간(ms, 0 = 기록 없음)의 차이. 하나라도 없으면 null.</summary>
    public static TeammateGap? GapOf(int mine, int theirs)
        => mine > 0 && theirs > 0
            ? new TeammateGap(mine - theirs, Math.Round((mine - theirs) * PercentScale / theirs, PercentDigits))
            : null;

    /// <summary>한 주말 세션들의 예선 요약(예선 세션이 없으면 순위·차이가 모두 null).</summary>
    public static QualifyingSummary Qualifying(IEnumerable<SessionComparison> weekendSessions)
    {
        var qualifying = weekendSessions.Where(s => s.Type == SessionType.Qualifying).OrderBy(s => s.ClassifiedAt).ToList();
        var main = qualifying.Where(s => MainQualifyingKinds.Contains(s.Kind)).ToList();
        var parts = main.Count > 0 ? main : qualifying;

        var gapPart = parts.LastOrDefault(s => s.Me is { BestLapTimeMs: > 0 } && s.Teammate is { BestLapTimeMs: > 0 });
        return new QualifyingSummary(
            parts,
            Known(parts.LastOrDefault(s => s.Me is { Position: > 0 })?.Me!.Position),
            Known(parts.LastOrDefault(s => s.Teammate is { Position: > 0 })?.Teammate!.Position),
            gapPart is null ? null : GapOf(gapPart.Me!.BestLapTimeMs, gapPart.Teammate!.BestLapTimeMs),
            gapPart is { AiDifficulty: > 0 } ? gapPart.AiDifficulty : null,
            parts.LastOrDefault(s => s.AiDifficulty > 0)?.AiDifficulty);
    }

    /// <summary>순위가 0 이하(모름)면 null.</summary>
    public static int? Known(int? position) => position is > 0 ? position : null;
}
