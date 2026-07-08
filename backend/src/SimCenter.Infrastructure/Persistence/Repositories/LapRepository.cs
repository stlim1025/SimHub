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
            .Select(u => new { u.Id, u.DisplayName })
            .ToListAsync(cancellationToken);

        var nameById = names.ToDictionary(x => x.Id, x => x.DisplayName);

        return best
            .Select(b =>
            {
                var bestLap = laps
                    .Where(l => l.UserId == b.UserId)
                    .OrderBy(l => l.LapTimeMs)
                    .ThenBy(l => l.SetAt)
                    .First();

                var displayName = nameById.TryGetValue(b.UserId, out var name) ? name : string.Empty;
                return new RankingLapRow(b.UserId, displayName, bestLap.LapTimeMs, bestLap.SetAt);
            })
            .OrderBy(r => r.LapTimeMs)
            .ThenBy(r => r.SetAt)
            .ToList();
    }

    public async Task<(IReadOnlyList<Lap> Items, int Total)> GetMyLapsAsync(
        Guid userId,
        Guid? trackId,
        SessionType? sessionType,
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

        var items = await query
            .Include(l => l.Track)
            .Include(l => l.Sectors)
            .OrderByDescending(l => l.SetAt)
            .Skip(skip)
            .Take(take)
            .ToListAsync(cancellationToken);

        return (items, total);
    }

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
