using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// ISeasonQueryRepository의 EF Core 구현(P7, 12 §7). 읽기 전용 — 모두 <c>AsNoTracking</c>이고 메서드마다 쿼리 1회다.
/// 삭제된 행은 전역 쿼리 필터로 제외된다. 시즌 Id를 받는 두 메서드는 호출자가 사용자 조건으로 찾은 시즌의 Id만 넘긴다
/// (<see cref="GetMyPageAsync"/>·<see cref="GetMineAsync"/>가 UserId 조건을 건다).
/// </summary>
public sealed class SeasonQueryRepository : ISeasonQueryRepository
{
    private readonly AppDbContext _context;

    public SeasonQueryRepository(AppDbContext context) => _context = context;

    public async Task<(IReadOnlyList<Season> Items, int Total)> GetMyPageAsync(
        Guid userId, int skip, int take, CancellationToken cancellationToken = default)
    {
        var query = _context.Seasons.AsNoTracking().Where(s => s.UserId == userId);

        var total = await query.CountAsync(cancellationToken);
        var items = await query
            .OrderByDescending(s => s.LastSessionAt)
            .ThenByDescending(s => s.Id)
            .Skip(skip)
            .Take(take)
            .ToListAsync(cancellationToken);

        return (items, total);
    }

    public Task<Season?> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
        => _context.Seasons
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.UserId == userId && s.Id == seasonId, cancellationToken);

    /// <remarks>트랙 이름은 내비게이션 Include 대신 조인 프로젝션으로 읽는다.</remarks>
    public async Task<IReadOnlyList<WeekendRow>> GetWeekendRowsAsync(
        IReadOnlyCollection<Guid> seasonIds, CancellationToken cancellationToken = default)
    {
        var ids = seasonIds.ToArray();

        return await (
                from weekend in _context.RaceWeekends.AsNoTracking()
                join track in _context.Tracks.AsNoTracking() on weekend.TrackId equals track.Id
                join season in _context.Seasons.AsNoTracking() on weekend.SeasonId equals season.Id
                where ids.Contains(weekend.SeasonId)
                orderby weekend.FirstSessionAt, weekend.Id
                select new WeekendRow(
                    weekend.Id,
                    weekend.SeasonId,
                    track.Name,
                    weekend.FirstSessionAt,
                    track.DisplayOrder,
                    season.ImportedFrom != null))
            .ToListAsync(cancellationToken);
    }

    /// <remarks>
    /// <c>session_results</c> ⨝ <c>game_sessions</c> 프로젝션 1쿼리(활성 행만 — 전역 필터가 두 테이블 모두에 걸린다).
    /// <paramref name="scoringRowsOnly"/>면 레이스 세션이거나 <c>Points &gt; 0</c>인 행만 읽는다.
    /// </remarks>
    public async Task<IReadOnlyList<SeasonResultRow>> GetResultRowsAsync(
        IReadOnlyCollection<Guid> seasonIds, bool scoringRowsOnly, CancellationToken cancellationToken = default)
    {
        var ids = seasonIds.ToArray();

        var rows =
            from result in _context.SessionResults.AsNoTracking()
            join session in _context.GameSessions.AsNoTracking() on result.GameSessionId equals session.Id
            join season in _context.Seasons.AsNoTracking() on session.SeasonId equals (Guid?)season.Id
            where session.SeasonId != null
                && session.RaceWeekendId != null
                && ids.Contains(session.SeasonId.Value)
            // 가져온 시즌(docs/15 §12, D-55): 가져온 세션과 가져오기 전에 기록된(옮긴) 세션의 점수는 가져온 스탠딩에 이미 들어 있다.
            select new
            {
                result,
                session,
                coveredByBaseline = session.IsImported || (season.ImportedAt != null && session.ClassifiedAt <= season.ImportedAt),
            };

        if (scoringRowsOnly)
        {
            rows = rows.Where(x => x.session.SessionType == SessionType.Race || x.result.Points > 0);
        }

        return await rows
            .OrderBy(x => x.session.ClassifiedAt)
            .ThenBy(x => x.session.Id)
            .ThenBy(x => x.result.CarIndex)
            .Select(x => new SeasonResultRow(
                x.session.SeasonId!.Value,
                x.session.RaceWeekendId!.Value,
                x.session.Id,
                x.session.SessionType,
                x.session.SessionKind,
                x.session.ClassifiedAt,
                x.result.DriverKey,
                x.result.DriverName,
                x.result.CarIndex,
                x.result.TeamId,
                x.result.IsPlayer,
                x.result.IsAiControlled,
                x.result.Position,
                x.result.ResultStatus,
                x.result.Points,
                x.coveredByBaseline))
            .ToListAsync(cancellationToken);
    }
}
