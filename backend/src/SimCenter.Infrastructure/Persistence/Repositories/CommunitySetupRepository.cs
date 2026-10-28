using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>ICommunitySetupRepository의 EF Core 구현.</summary>
public sealed class CommunitySetupRepository : ICommunitySetupRepository
{
    private readonly AppDbContext _context;

    public CommunitySetupRepository(AppDbContext context) => _context = context;

    public async Task<IReadOnlyList<CommunitySetupCount>> GetCountsAsync(string gameCode, CancellationToken cancellationToken = default)
        => await _context.CommunitySetups
            .AsNoTracking()
            .Where(s => s.GameCode == gameCode)
            .GroupBy(s => new { s.TrackId, s.Condition })
            .Select(g => new CommunitySetupCount(g.Key.TrackId, g.Key.Condition, g.Count()))
            .ToListAsync(cancellationToken);

    public async Task<IReadOnlyList<CommunitySetup>> GetActiveAsync(
        Guid trackId, string condition, string sessionType, CancellationToken cancellationToken = default)
        => await _context.CommunitySetups
            .AsNoTracking()
            .Where(s => s.TrackId == trackId && s.Condition == condition && s.SessionType == sessionType)
            .OrderBy(s => s.Rank)
            .ThenBy(s => s.Id)
            .ToListAsync(cancellationToken);

    public Task<CommunitySetup?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
        => _context.CommunitySetups
            .AsNoTracking()
            .Include(s => s.Track)
            .FirstOrDefaultAsync(s => s.Id == id, cancellationToken);

    public async Task<IReadOnlyList<CommunitySetup>> GetGroupAsync(
        string gameCode, Guid trackId, string condition, CancellationToken cancellationToken = default)
        => await Group(gameCode, trackId, condition).AsNoTracking().ToListAsync(cancellationToken);

    public async Task ReplaceGroupAsync(
        string gameCode,
        Guid trackId,
        string condition,
        string sessionType,
        IReadOnlyList<CommunitySetup> setups,
        DateTime now,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(setups);

        try
        {
            await using var transaction = await _context.Database.BeginTransactionAsync(cancellationToken);

            var existing = await Group(gameCode, trackId, condition).ToDictionaryAsync(s => s.SourceId, cancellationToken);
            var incomingIds = new HashSet<string>(StringComparer.Ordinal);

            foreach (var setup in setups)
            {
                incomingIds.Add(setup.SourceId);
                if (existing.TryGetValue(setup.SourceId, out var row))
                {
                    Overwrite(row, setup, now);
                }
                else
                {
                    await _context.CommunitySetups.AddAsync(setup, cancellationToken);
                }
            }

            // 지우는 것은 이 세션 종류의 행만(같은 조건의 다른 세션 종류 묶음은 그대로).
            foreach (var row in existing.Values.Where(r =>
                         !r.IsDeleted && r.SessionType == sessionType && !incomingIds.Contains(r.SourceId)))
            {
                row.IsDeleted = true;
                row.UpdatedAt = now;
            }

            await _context.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        finally
        {
            // 성공·실패와 관계없이 추적을 비운다 — 실패한 묶음의 변경이 다음 묶음의 저장에 섞이지 않게.
            _context.ChangeTracker.Clear();
        }
    }

    /// <summary>게임·트랙·조건의 모든 행(세션 종류 전부, 지운 행 포함, tracked) — SourceId는 이 안에서 하나다(고유 인덱스).</summary>
    private IQueryable<CommunitySetup> Group(string gameCode, Guid trackId, string condition)
        => _context.CommunitySetups
            .IgnoreQueryFilters()
            .Where(s => s.GameCode == gameCode && s.TrackId == trackId && s.Condition == condition);

    private static void Overwrite(CommunitySetup row, CommunitySetup source, DateTime now)
    {
        row.Rank = source.Rank;
        row.SourceUrl = source.SourceUrl;
        row.TeamName = source.TeamName;
        row.SessionType = source.SessionType;
        row.LapTimeMs = source.LapTimeMs;
        row.Steering = source.Steering;
        row.SetOn = source.SetOn;
        row.Sections = source.Sections;
        row.FetchedAt = source.FetchedAt;
        row.IsDeleted = false;
        row.UpdatedAt = now;
    }
}
