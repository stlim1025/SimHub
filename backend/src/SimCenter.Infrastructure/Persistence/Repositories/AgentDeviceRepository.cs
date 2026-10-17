using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// IAgentDeviceRepository의 EF Core 구현. 해제(soft delete)된 장치는 전역 쿼리 필터로 모든 조회에서 제외된다.
/// </summary>
public sealed class AgentDeviceRepository : IAgentDeviceRepository
{
    private readonly AppDbContext _context;

    public AgentDeviceRepository(AppDbContext context) => _context = context;

    public async Task AddAsync(AgentDevice device, CancellationToken cancellationToken = default)
        => await _context.AgentDevices.AddAsync(device, cancellationToken);

    public Task<AgentDevice?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
        => _context.AgentDevices.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);

    public Task<AgentDevice?> GetByApiKeyHashAsync(string hash, CancellationToken cancellationToken = default)
        => _context.AgentDevices.FirstOrDefaultAsync(x => x.ApiKeyHash == hash, cancellationToken);

    public async Task<IReadOnlyList<AgentDevice>> GetByUserAsync(Guid userId, CancellationToken cancellationToken = default)
        => await _context.AgentDevices
            .AsNoTracking()
            .Where(x => x.UserId == userId)
            .OrderByDescending(x => x.CreatedAt)
            .ThenByDescending(x => x.Id) // UUID v7은 시간순 → 생성 시각이 같아도 순서가 고정된다.
            .ToListAsync(cancellationToken);
}
