using SimCenter.Application.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 팀메이트 맞대결 계산(순수 함수 — 상태 없음). 팀메이트 = 계산 대상 세션에서 내 팀과 같은 팀 대표 ID
/// (<see cref="TeamCatalog.CanonicalTeamId"/>)로 가장 자주 함께 나온 다른 차. 내 행·팀메이트가 없으면 null.
/// 레이스 항목은 본 레이스만(스프린트 제외), 예선은 주말마다 본 예선(없으면 스프린트 슛아웃)에서 각자 마지막으로 달린 단계의 순위다.
/// </summary>
public static class TeammateHeadToHead
{
    private static readonly HashSet<SessionKind> MainQualifyingKinds =
    [
        SessionKind.Qualifying1, SessionKind.Qualifying2, SessionKind.Qualifying3,
        SessionKind.ShortQualifying, SessionKind.OneShotQualifying,
    ];

    private static readonly HashSet<ResultStatus> RetiredStatuses = [ResultStatus.DidNotFinish, ResultStatus.Retired];

    public static TeammateHeadToHeadDto? Build(SeasonSelection selection, SeasonStandings standings, string gameCode)
    {
        ArgumentNullException.ThrowIfNull(selection);
        ArgumentNullException.ThrowIfNull(standings);

        var me = standings.Drivers.FirstOrDefault(d => d.IsPlayer);
        var sessions = selection.CountedRows.GroupBy(r => r.SessionId).Select(g => g.ToList()).ToList();
        var teammateKey = TeammateKey(sessions, gameCode);
        var teammate = teammateKey is null ? null : standings.Drivers.FirstOrDefault(d => d.DriverKey == teammateKey);
        if (me is null || teammate is null)
        {
            return null;
        }

        (SeasonResultRow? Me, SeasonResultRow? Teammate) Pair(IReadOnlyList<SeasonResultRow> rows)
            => (rows.Where(r => r.IsPlayer).OrderBy(r => r.CarIndex).FirstOrDefault(),
                rows.FirstOrDefault(r => r.DriverKey == teammateKey));

        var mainRaces = sessions
            .Where(rows => selection.MainRaceSessionByWeekend.TryGetValue(rows[0].WeekendId, out var main) && rows[0].SessionId == main)
            .Select(Pair)
            .ToList();
        var team = TeamCatalog.Resolve(gameCode, me.TeamId, me.TeamName);

        return new TeammateHeadToHeadDto(
            me.Name,
            teammate.Name,
            team.Name,
            team.Color,
            Ahead(mainRaces.Select(p => (p.Me?.Position, p.Teammate?.Position))),
            Ahead(Qualifying(sessions, Pair)),
            new HeadToHeadCountDto(me.Points, teammate.Points),
            new HeadToHeadCountDto(me.Podiums, teammate.Podiums),
            new HeadToHeadPositionDto(
                BestFinish(mainRaces.Select(p => p.Me)), BestFinish(mainRaces.Select(p => p.Teammate))),
            new HeadToHeadPositionDto(BestGrid(mainRaces.Select(p => p.Me)), BestGrid(mainRaces.Select(p => p.Teammate))),
            new HeadToHeadCountDto(Retirements(mainRaces.Select(p => p.Me)), Retirements(mainRaces.Select(p => p.Teammate))));
    }

    /// <summary>세션마다 내 팀과 같은 팀 대표 ID의 다른 차를 세어 가장 많이 나온 드라이버(동률이면 키 순). 없으면 null.</summary>
    private static string? TeammateKey(IEnumerable<List<SeasonResultRow>> sessions, string gameCode)
    {
        var counts = new Dictionary<string, int>();
        foreach (var rows in sessions)
        {
            if (rows.FirstOrDefault(r => r.IsPlayer)?.TeamId is not { } myTeam)
            {
                continue;
            }

            var team = TeamCatalog.CanonicalTeamId(gameCode, myTeam);
            foreach (var row in rows.Where(r => !r.IsPlayer && r.TeamId is { } t && TeamCatalog.CanonicalTeamId(gameCode, t) == team))
            {
                counts[row.DriverKey] = counts.GetValueOrDefault(row.DriverKey) + 1;
            }
        }

        return counts
            .OrderByDescending(c => c.Value)
            .ThenBy(c => c.Key, StringComparer.Ordinal)
            .Select(c => c.Key)
            .FirstOrDefault();
    }

    /// <summary>주말마다 (내 예선 순위, 팀메이트 예선 순위) — 각자 마지막으로 순위가 있는 단계.</summary>
    private static IEnumerable<(int? Me, int? Teammate)> Qualifying(
        IReadOnlyList<List<SeasonResultRow>> sessions,
        Func<IReadOnlyList<SeasonResultRow>, (SeasonResultRow? Me, SeasonResultRow? Teammate)> pair)
    {
        foreach (var weekend in sessions.Where(rows => rows[0].SessionType == SessionType.Qualifying).GroupBy(rows => rows[0].WeekendId))
        {
            var parts = weekend.OrderBy(rows => rows[0].ClassifiedAt).Select(rows => (Kind: rows[0].SessionKind, Pair: pair(rows))).ToList();
            var main = parts.Where(p => MainQualifyingKinds.Contains(p.Kind)).ToList();
            var chosen = main.Count > 0 ? main : parts;
            yield return (
                chosen.LastOrDefault(p => p.Pair.Me is { Position: > 0 }).Pair.Me?.Position,
                chosen.LastOrDefault(p => p.Pair.Teammate is { Position: > 0 }).Pair.Teammate?.Position);
        }
    }

    /// <summary>둘 다 순위가 있는 판에서 앞선 횟수(나 · 팀메이트).</summary>
    private static HeadToHeadCountDto Ahead(IEnumerable<(int? Me, int? Teammate)> positions)
    {
        var mine = 0;
        var theirs = 0;
        foreach (var (me, teammate) in positions)
        {
            if (me is not > 0 || teammate is not > 0)
            {
                continue;
            }

            if (me < teammate)
            {
                mine++;
            }
            else
            {
                theirs++;
            }
        }

        return new HeadToHeadCountDto(mine, theirs);
    }

    private static int? BestFinish(IEnumerable<SeasonResultRow?> rows)
        => rows.Where(r => r is { ResultStatus: ResultStatus.Finished, Position: > 0 }).Select(r => (int?)r!.Position).Min();

    private static int? BestGrid(IEnumerable<SeasonResultRow?> rows)
        => rows.Where(r => r is { GridPosition: > 0 }).Select(r => (int?)r!.GridPosition).Min();

    private static int Retirements(IEnumerable<SeasonResultRow?> rows)
        => rows.Count(r => r is not null && RetiredStatuses.Contains(r.ResultStatus));
}
