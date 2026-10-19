using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// IGameSessionQueryRepository의 EF Core 구현(P7, 12 §7). 읽기 전용 — 모두 <c>AsNoTracking</c> + <c>UserId</c> 조건이고
/// 메서드마다 쿼리 1회다(총 개수 집계 제외). 삭제된 행은 전역 쿼리 필터로 제외된다.
/// </summary>
public sealed class GameSessionQueryRepository : IGameSessionQueryRepository
{
    private readonly AppDbContext _context;

    public GameSessionQueryRepository(AppDbContext context) => _context = context;

    /// <remarks>
    /// 트랙 이름은 조인 프로젝션으로, 활성 결과 수(<c>CarCount</c>)와 내 차(<c>IsPlayer</c>) 값은 상관 서브쿼리로 읽는다 —
    /// 세션마다 결과를 따로 읽지 않는다. 플레이어 행이 둘 이상이면(비정상) 차 번호가 가장 작은 행을 쓴다.
    /// </remarks>
    public async Task<(IReadOnlyList<SessionSummaryRow> Items, int Total)> GetMyPageAsync(
        Guid userId, SessionType? sessionType, int skip, int take, CancellationToken cancellationToken = default)
    {
        var sessions = _context.GameSessions.AsNoTracking().Where(s => s.UserId == userId);
        if (sessionType is { } type)
        {
            sessions = sessions.Where(s => s.SessionType == type);
        }

        var total = await sessions.CountAsync(cancellationToken);

        var page = await (
                from session in sessions
                join track in _context.Tracks.AsNoTracking() on session.TrackId equals track.Id
                orderby session.ClassifiedAt descending, session.Id descending
                select new
                {
                    session.Id,
                    session.ClassifiedAt,
                    TrackName = track.Name,
                    track.CountryCode,
                    session.GameCode,
                    session.SessionType,
                    session.SessionKind,
                    session.GameMode,
                    session.SeasonId,
                    CarCount = session.Results.Count(),
                    Me = session.Results
                        .Where(r => r.IsPlayer)
                        .OrderBy(r => r.CarIndex)
                        .Select(r => new { r.Position, r.GridPosition, r.ResultStatus, r.BestLapTimeMs, r.Points, r.TeamId })
                        .FirstOrDefault(),
                    // 같은 주말에 Race2나 스프린트 슛아웃이 있으면 스프린트 주말(그 주말 Race = 스프린트, SessionPositions).
                    IsSprintWeekend = session.RaceWeekendId != null && _context.GameSessions.Any(o =>
                        o.UserId == userId && o.RaceWeekendId == session.RaceWeekendId && SessionPositions.SprintWeekendMarkers.Contains(o.SessionKind)),
                })
            .Skip(skip)
            .Take(take)
            .ToListAsync(cancellationToken);

        var items = page
            .Select(row => new SessionSummaryRow(
                row.Id,
                row.ClassifiedAt,
                row.TrackName,
                row.SessionType,
                row.SessionKind,
                row.GameMode,
                row.SeasonId,
                row.CarCount,
                row.Me?.Position,
                row.Me?.GridPosition,
                row.Me?.ResultStatus,
                row.Me?.BestLapTimeMs,
                row.Me?.Points,
                row.GameCode,
                row.CountryCode,
                row.Me?.TeamId,
                row.IsSprintWeekend))
            .ToList();

        return (items, total);
    }

    /// <remarks>
    /// 트랙 → 활성 결과 → 활성 스틴트를 한 쿼리로 읽는다. 결과 → 스틴트는 형제가 아닌 체인이라 행이 곱해지지 않고(스틴트 수만큼),
    /// <c>AsSingleQuery</c>를 명시해 EF의 "컬렉션 Include 여러 개, 쿼리 분할 미설정" 경고가 로그에 남지 않게 한다.
    /// 삭제된 결과·스틴트는 전역 필터가 Include에도 적용되어 빠진다.
    /// </remarks>
    public Task<GameSession?> GetMineDetailAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
        => _context.GameSessions
            .AsNoTracking()
            .Include(s => s.Track)
            .Include(s => s.Results)
            .ThenInclude(r => r.TyreStints)
            .AsSingleQuery()
            .FirstOrDefaultAsync(s => s.UserId == userId && s.Id == sessionId, cancellationToken);

    /// <remarks>(UserId, GameCode, SessionKey) unique index(활성 행)를 그대로 탄다.</remarks>
    public Task<Guid?> FindMySessionIdAsync(
        Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
        => _context.GameSessions
            .AsNoTracking()
            .Where(s => s.UserId == userId && s.GameCode == gameCode && s.SessionKey == sessionKey)
            .Select(s => (Guid?)s.Id)
            .FirstOrDefaultAsync(cancellationToken);
}
