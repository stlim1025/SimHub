using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// IAgentPairingCodeRepository의 EF Core 구현. 무효화(soft delete)된 코드는 전역 쿼리 필터로 조회에서 제외되며,
/// 해시 중복 확인만 필터를 무시한다(고유 인덱스가 soft delete 행도 포함하므로).
/// </summary>
public sealed class AgentPairingCodeRepository : IAgentPairingCodeRepository
{
    private readonly AppDbContext _context;

    public AgentPairingCodeRepository(AppDbContext context) => _context = context;

    public async Task AddAsync(AgentPairingCode code, CancellationToken cancellationToken = default)
        => await _context.AgentPairingCodes.AddAsync(code, cancellationToken);

    public async Task<IReadOnlyList<AgentPairingCode>> GetUnconsumedByUserAsync(Guid userId, CancellationToken cancellationToken = default)
        => await _context.AgentPairingCodes
            .Where(x => x.UserId == userId && x.ConsumedAt == null)
            .ToListAsync(cancellationToken);

    public Task<bool> ExistsByHashAsync(string codeHash, CancellationToken cancellationToken = default)
        => _context.AgentPairingCodes
            .IgnoreQueryFilters()
            .AnyAsync(x => x.CodeHash == codeHash, cancellationToken);

    public Task<AgentPairingCode?> GetRedeemableByHashAsync(string codeHash, DateTime nowUtc, CancellationToken cancellationToken = default)
        // 소비는 TryConsumeAsync(조건부 UPDATE)가 하므로 추적하지 않는다 — 추적 엔티티의 ConsumedAt이 낡은 값으로 남지 않게.
        => _context.AgentPairingCodes
            .AsNoTracking()
            .FirstOrDefaultAsync(
                x => x.CodeHash == codeHash && !x.IsDeleted && x.ConsumedAt == null && x.ExpiresAt > nowUtc,
                cancellationToken);

    public async Task<bool> TryConsumeAsync(Guid codeId, DateTime nowUtc, CancellationToken cancellationToken = default)
    {
        // 조회와 갱신 사이에 다른 요청이 먼저 소비했다면 consumed_at IS NULL 조건이 거짓이 되어 0행이 갱신된다.
        var affected = await _context.AgentPairingCodes
            .Where(x => x.Id == codeId && x.ConsumedAt == null && !x.IsDeleted && x.ExpiresAt > nowUtc)
            .ExecuteUpdateAsync(
                setters => setters
                    .SetProperty(x => x.ConsumedAt, nowUtc)
                    .SetProperty(x => x.UpdatedAt, nowUtc),
                cancellationToken);

        return affected == 1;
    }
}
