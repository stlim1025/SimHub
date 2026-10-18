using SimCenter.Application.Common;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Import;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 내 시즌 조회(12 §7). 시즌의 결과 행을 한 번에 읽어 순수 계산기(세션 선별 · Standings · 라운드 번호)로 만든다.
/// 목록은 페이지의 시즌들을 한 쿼리로(대상 행만), 상세는 시즌 하나의 전체 행으로 읽는다 — 시즌마다 따로 읽지 않는다(N+1 금지).
/// </summary>
public sealed class SeasonQueryService : ISeasonQueryService
{
    private readonly ISeasonQueryRepository _seasons;
    private readonly ISessionDetailQueryRepository _seasonOrder;
    private readonly ITrackRepository _tracks;

    public SeasonQueryService(ISeasonQueryRepository seasons, ISessionDetailQueryRepository seasonOrder, ITrackRepository tracks)
    {
        _seasons = seasons;
        _seasonOrder = seasonOrder;
        _tracks = tracks;
    }

    /// <summary>시즌 번호(D-54) — 내 시즌 전부를 한 쿼리로 읽어 매긴다.</summary>
    private async Task<IReadOnlyDictionary<Guid, int>> SeasonNumbersAsync(Guid userId, CancellationToken cancellationToken)
        => SeasonNumbering.Assign(await _seasonOrder.GetMySeasonOrderAsync(userId, cancellationToken));

    public async Task<PagedResult<SeasonSummaryDto>> GetMySeasonsAsync(
        Guid userId, int page, int pageSize, CancellationToken cancellationToken = default)
    {
        var window = PageWindow.Resolve(page, pageSize, ISeasonQueryService.DefaultPageSize, ISeasonQueryService.MaxPageSize);

        var (seasons, total) = await _seasons.GetMyPageAsync(userId, window.Skip, window.PageSize, cancellationToken);
        if (seasons.Count == 0)
        {
            return new PagedResult<SeasonSummaryDto>(window.Page, window.PageSize, total, []);
        }

        var seasonIds = seasons.Select(s => s.Id).ToList();
        var weekends = await _seasons.GetWeekendRowsAsync(seasonIds, cancellationToken);
        var rows = await _seasons.GetResultRowsAsync(seasonIds, scoringRowsOnly: true, cancellationToken);

        var numbers = await SeasonNumbersAsync(userId, cancellationToken);

        var roundCounts = weekends.GroupBy(w => w.SeasonId).ToDictionary(g => g.Key, g => g.Count());
        var rowsBySeason = rows.ToLookup(r => r.SeasonId);

        var items = seasons
            .Select(season => ToSummary(
                season,
                roundCounts.GetValueOrDefault(season.Id),
                Calculate(season, rowsBySeason[season.Id].ToList()).Standings,
                numbers))
            .ToList();

        return new PagedResult<SeasonSummaryDto>(window.Page, window.PageSize, total, items);
    }

    public async Task<SeasonDetailDto> GetMySeasonAsync(
        Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
    {
        var season = await _seasons.GetMineAsync(userId, seasonId, cancellationToken)
            ?? throw new NotFoundException("시즌을 찾을 수 없습니다.");

        var seasonIds = new[] { season.Id };
        var weekends = await _seasons.GetWeekendRowsAsync(seasonIds, cancellationToken);
        var rows = await _seasons.GetResultRowsAsync(seasonIds, scoringRowsOnly: false, cancellationToken);

        var numbers = await SeasonNumbersAsync(userId, cancellationToken);
        var calendar = SeasonCalendar.CalendarOf(await _tracks.GetAllAsync(cancellationToken), season.GameCode);

        var (selection, standings) = Calculate(season, rows);
        var rounds = RoundNumbering.Assign(weekends);
        var seasonTeamId = standings.Drivers.FirstOrDefault(d => d.IsPlayer)?.TeamId;

        return new SeasonDetailDto(
            ToSummary(season, weekends.Count, standings, numbers),
            BuildRounds(weekends, rounds, rows, selection),
            ToStandingsDto(standings, rounds, season.GameCode),
            // 시즌 탭(docs/15 §12): 캘린더 전부 + 내 라운드 값. 가져온 세션(D-55)은 내 결과 행만 있어도 된다.
            SeasonCalendar.Build(season.GameCode, calendar, weekends, selection, seasonTeamId));
    }

    // ---- 계산 ----

    private static (SeasonSelection Selection, SeasonStandings Standings) Calculate(
        Season season, IReadOnlyList<SeasonResultRow> rows)
    {
        var selection = SeasonSessionSelector.Select(rows);

        // 가져온 시즌(docs/15 §12, D-55)은 가져온 스탠딩이 기준선이다.
        var imported = ImportedSeasonSnapshot.TryRead(season.ImportedStandings);
        return (selection, StandingsCalculator.Calculate(selection, season.GameCode, imported));
    }

    // ---- 매핑: 요약 ----

    private static SeasonSummaryDto ToSummary(
        Season season, int roundCount, SeasonStandings standings, IReadOnlyDictionary<Guid, int> seasonNumbers)
    {
        var me = standings.Drivers.FirstOrDefault(d => d.IsPlayer);
        var leader = standings.Drivers.FirstOrDefault();
        var myTeam = me?.TeamId is { } teamId ? TeamCatalog.Resolve(season.GameCode, teamId) : null;

        return new SeasonSummaryDto(
            season.Id,
            season.GameCode,
            season.GameMode.ToString(),
            season.FirstSessionAt,
            season.LastSessionAt,
            roundCount,
            me?.Position,
            me?.Points,
            leader?.Name,
            leader?.Points,
            season.ImportedFrom,
            myTeam?.Name,
            myTeam?.Color,
            SeasonNumbering.Of(seasonNumbers, season.Id),
            me?.Name);
    }

    // ---- 매핑: 라운드 ----

    private static List<SeasonRoundDto> BuildRounds(
        IReadOnlyList<WeekendRow> weekends,
        IReadOnlyDictionary<Guid, int> rounds,
        IReadOnlyList<SeasonResultRow> allRows,
        SeasonSelection selection)
    {
        var winners = WinnerNames.ByWeekend(selection);
        var allByWeekend = allRows.ToLookup(r => r.WeekendId);
        var countedByWeekend = selection.CountedRows.ToLookup(r => r.WeekendId);

        return weekends
            .OrderBy(w => rounds[w.WeekendId])
            .Select(w => new SeasonRoundDto(
                rounds[w.WeekendId],
                w.WeekendId,
                w.TrackName,
                w.FirstSessionAt,
                winners.GetValueOrDefault(w.WeekendId),
                MyWeekendPoints(countedByWeekend[w.WeekendId]),
                BuildSessionChips(allByWeekend[w.WeekendId])))
            .ToList();
    }

    /// <summary>그 주말 내 점수 합(계산 대상 세션만). 내 결과가 없으면 null.</summary>
    private static int? MyWeekendPoints(IEnumerable<SeasonResultRow> countedRows)
    {
        var mine = countedRows.Where(r => r.IsPlayer).ToList();
        return mine.Count == 0 ? null : PointTotals.ToInt(mine.Sum(r => (long)r.Points));
    }

    /// <summary>저장된 모든 세션(옛 중복 포함)을 <c>ClassifiedAt</c> 오름차순으로. 칩의 내 값은 <c>IsPlayer</c> 행에서 읽는다.</summary>
    private static List<SeasonRoundSessionDto> BuildSessionChips(IEnumerable<SeasonResultRow> weekendRows)
    {
        return weekendRows
            .GroupBy(r => r.SessionId)
            .Select(g => g.ToList())
            .OrderBy(session => session[0].ClassifiedAt)
            .ThenBy(session => session[0].SessionId)
            .Select(session =>
            {
                var head = session[0];
                var mine = session.Where(r => r.IsPlayer).OrderBy(r => r.CarIndex).FirstOrDefault();
                return new SeasonRoundSessionDto(
                    head.SessionId,
                    head.SessionType.ToString(),
                    head.SessionKind.ToString(),
                    mine?.Position,
                    mine?.ResultStatus.ToString());
            })
            .ToList();
    }

    // ---- 매핑: Standings ----

    private static SeasonStandingsDto ToStandingsDto(
        SeasonStandings standings, IReadOnlyDictionary<Guid, int> rounds, string gameCode)
    {
        var drivers = standings.Drivers.Select(d =>
        {
            var team = TeamCatalog.Resolve(gameCode, d.TeamId);
            return new DriverStandingDto(
                d.Position,
                d.DriverKey,
                d.Name,
                team.Name,
                team.Color,
                d.IsPlayer,
                d.IsAiControlled,
                d.Points,
                d.Wins,
                d.Podiums,
                ToCellDtos(d.Cells, rounds));
        }).ToList();

        var constructors = standings.Constructors.Select(c =>
        {
            var team = TeamCatalog.Resolve(gameCode, c.TeamId);
            return new ConstructorStandingDto(c.Position, c.TeamId, team.Name, team.Color, c.Points, c.Wins);
        }).ToList();

        return new SeasonStandingsDto(drivers, constructors);
    }

    /// <summary>라운드 번호가 없는 주말(주말 행이 누락된 비정상 데이터)의 칸은 표에 놓을 자리가 없어 뺀다.</summary>
    private static List<StandingCellDto> ToCellDtos(
        IReadOnlyList<StandingCell> cells, IReadOnlyDictionary<Guid, int> rounds)
    {
        return cells
            .Where(c => rounds.ContainsKey(c.WeekendId))
            .Select(c => new StandingCellDto(rounds[c.WeekendId], c.Position, c.ResultStatus?.ToString(), c.Points))
            .OrderBy(c => c.Round)
            .ToList();
    }
}
