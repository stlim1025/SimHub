using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>IStoreRepository의 EF Core 구현. MVP는 단일 매장이라 대표(첫) 매장 타임존을 반환한다.</summary>
public sealed class StoreRepository : IStoreRepository
{
    private readonly AppDbContext _context;

    public StoreRepository(AppDbContext context) => _context = context;

    public async Task<string> GetPrimaryTimeZoneIdAsync(CancellationToken cancellationToken = default)
    {
        var timeZoneId = await _context.Stores
            .AsNoTracking()
            .OrderBy(x => x.CreatedAt)
            .Select(x => x.TimeZoneId)
            .FirstOrDefaultAsync(cancellationToken);

        return timeZoneId ?? throw new NotFoundException("매장이 없습니다(시드 누락).");
    }
}
