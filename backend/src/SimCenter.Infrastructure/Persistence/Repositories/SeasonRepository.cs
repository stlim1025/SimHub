using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// ISeasonRepository의 EF Core 구현. 조회는 추적(tracked)된 엔티티를 돌려주어 호출자가 바꾼 범위가 인입 커밋에 함께 저장된다.
/// 삭제된 행은 전역 쿼리 필터로 모든 조회에서 제외된다.
/// </summary>
public sealed class SeasonRepository : ISeasonRepository
{
    private readonly AppDbContext _context;

    public SeasonRepository(AppDbContext context) => _context = context;

    public Task<Season?> GetByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
        => _context.Seasons.FirstOrDefaultAsync(
            s => s.UserId == userId && s.GameCode == gameCode && s.SeasonLinkId == seasonLinkId, cancellationToken);

    /// <remarks>지운 행만 보므로 전역 필터를 끈다.</remarks>
    public Task<Season?> GetDeletedByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
        => _context.Seasons
            .IgnoreQueryFilters()
            .Where(s => s.IsDeleted && s.UserId == userId && s.GameCode == gameCode && s.SeasonLinkId == seasonLinkId)
            .OrderByDescending(s => s.UpdatedAt)
            .ThenByDescending(s => s.Id)
            .FirstOrDefaultAsync(cancellationToken);

    public Task<Season?> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
        => _context.Seasons.FirstOrDefaultAsync(s => s.UserId == userId && s.Id == seasonId, cancellationToken);

    public Task<RaceWeekend?> GetWeekendAsync(Guid seasonId, long weekendLinkId, CancellationToken cancellationToken = default)
        => _context.RaceWeekends.FirstOrDefaultAsync(
            w => w.SeasonId == seasonId && w.WeekendLinkId == weekendLinkId, cancellationToken);

    public async Task AddAsync(Season season, CancellationToken cancellationToken = default)
        => await _context.Seasons.AddAsync(season, cancellationToken);

    public async Task AddWeekendAsync(RaceWeekend weekend, CancellationToken cancellationToken = default)
        => await _context.RaceWeekends.AddAsync(weekend, cancellationToken);
}
