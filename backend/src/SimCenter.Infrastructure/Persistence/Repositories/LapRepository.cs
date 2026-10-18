using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>ILapRepository의 EF Core 구현. Sectors는 관계로 함께 삽입된다(cascade).</summary>
public sealed class LapRepository : ILapRepository
{
    private readonly AppDbContext _context;

    public LapRepository(AppDbContext context) => _context = context;

    public async Task AddAsync(Lap lap, CancellationToken cancellationToken = default)
        => await _context.Laps.AddAsync(lap, cancellationToken);

    public async Task<IReadOnlyList<RankingLapRow>> GetRankingAsync(
        Guid trackId,
        string gameCode,
        SessionType sessionType,
        DateTime fromUtc,
        DateTime toUtc,
        int top,
        CancellationToken cancellationToken = default)
    {
        var eligible = _context.Laps
            .AsNoTracking()
            .Where(l => l.TrackId == trackId
                && l.GameCode == gameCode
                && l.SessionType == sessionType
                && l.IsRankingEligible
                && l.SetAt >= fromUtc
                && l.SetAt < toUtc);

        // 1) 유저별 최고 랩타임 상위 N(DB 그룹핑).
        var best = await eligible
            .GroupBy(l => l.UserId)
            .Select(g => new { UserId = g.Key, BestMs = g.Min(l => l.LapTimeMs) })
            .OrderBy(x => x.BestMs)
            .Take(top)
            .ToListAsync(cancellationToken);

        if (best.Count == 0)
        {
            return [];
        }

        // 2) 상위 유저들의 최고 랩(SetAt)·표시명을 확보한다(동타임은 먼저 세운 기록 우선).
        var userIds = best.Select(b => b.UserId).ToList();

        var laps = await eligible
            .Where(l => userIds.Contains(l.UserId))
            .Select(l => new { l.UserId, l.LapTimeMs, l.SetAt })
            .ToListAsync(cancellationToken);

        var names = await _context.Users
            .AsNoTracking()
            .Where(u => userIds.Contains(u.Id))
            .Select(u => new { u.Id, u.DisplayName, u.ShowOnLeaderboard })
            .ToListAsync(cancellationToken);

        var userById = names.ToDictionary(x => x.Id);

        return best
            .Select(b =>
            {
                var bestLap = laps
                    .Where(l => l.UserId == b.UserId)
                    .OrderBy(l => l.LapTimeMs)
                    .ThenBy(l => l.SetAt)
                    .First();

                // 사용자 행이 없으면(soft delete 등) 이름을 비우고 비공개로 둔다 → 서비스가 익명으로 보인다.
                var found = userById.TryGetValue(b.UserId, out var user);
                return new RankingLapRow(
                    b.UserId,
                    found ? user!.DisplayName : string.Empty,
                    bestLap.LapTimeMs,
                    bestLap.SetAt,
                    found && user!.ShowOnLeaderboard);
            })
            .OrderBy(r => r.LapTimeMs)
            .ThenBy(r => r.SetAt)
            .ToList();
    }

    public async Task<(IReadOnlyList<Lap> Items, int Total)> GetMyLapsAsync(
        Guid userId,
        Guid? trackId,
        SessionType? sessionType,
        MyLapsSort sort,
        int skip,
        int take,
        CancellationToken cancellationToken = default)
    {
        var query = _context.Laps.AsNoTracking().Where(l => l.UserId == userId);

        if (trackId.HasValue)
        {
            query = query.Where(l => l.TrackId == trackId.Value);
        }

        if (sessionType.HasValue)
        {
            query = query.Where(l => l.SessionType == sessionType.Value);
        }

        var total = await query.CountAsync(cancellationToken);

        var items = await Order(query, sort)
            .Include(l => l.Track)
            .Include(l => l.Sectors)
            .Skip(skip)
            .Take(take)
            .ToListAsync(cancellationToken);

        return (items, total);
    }

    public async Task<IReadOnlyList<MyTrackSummaryRow>> GetMyTrackSummariesAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        // 트랙별 집계(DB 그룹핑): 무효 랩까지 센 개수, 유효 랩만의 최소 랩타임(없으면 null), 최근 SetAt.
        var perTrack = _context.Laps
            .AsNoTracking()
            .Where(l => l.UserId == userId)
            .GroupBy(l => l.TrackId)
            .Select(g => new
            {
                TrackId = g.Key,
                LapCount = g.Count(),
                BestValidLapTimeMs = g.Where(l => l.IsValid).Min(l => (int?)l.LapTimeMs),
                LastSetAt = g.Max(l => l.SetAt),
            });

        var rows = await (
                from summary in perTrack
                join track in _context.Tracks.AsNoTracking() on summary.TrackId equals track.Id
                orderby summary.LastSetAt descending, track.Name
                select new
                {
                    summary.TrackId,
                    track.Name,
                    track.GameCode,
                    summary.LapCount,
                    summary.BestValidLapTimeMs,
                    summary.LastSetAt,
                })
            .ToListAsync(cancellationToken);

        return rows
            .Select(r => new MyTrackSummaryRow(r.TrackId, r.Name, r.GameCode, r.LapCount, r.BestValidLapTimeMs, r.LastSetAt))
            .ToList();
    }

    /// <summary>
    /// 정렬 적용. Fastest = 유효 랩 우선 → 랩타임 오름차순 → 먼저 세운 순. 그 외(Recent 포함)는 최근 순.
    /// 동률이 나와도 페이지 경계가 흔들리지 않도록 마지막에 Id로 결정적 순서를 보장한다.
    /// </summary>
    private static IOrderedQueryable<Lap> Order(IQueryable<Lap> query, MyLapsSort sort)
        => sort == MyLapsSort.Fastest
            ? query.OrderByDescending(l => l.IsValid).ThenBy(l => l.LapTimeMs).ThenBy(l => l.SetAt).ThenBy(l => l.Id)
            : query.OrderByDescending(l => l.SetAt).ThenBy(l => l.Id);

    public async Task<Lap?> GetPersonalBestLapAsync(
        Guid userId,
        Guid trackId,
        string gameCode,
        CancellationToken cancellationToken = default)
        => await _context.Laps
            .AsNoTracking()
            .Where(l => l.UserId == userId
                && l.TrackId == trackId
                && l.GameCode == gameCode
                && l.IsRankingEligible)
            .OrderBy(l => l.LapTimeMs)
            .ThenBy(l => l.SetAt)
            .FirstOrDefaultAsync(cancellationToken);
}
