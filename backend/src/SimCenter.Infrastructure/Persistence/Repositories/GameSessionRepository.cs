using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// IGameSessionRepository의 EF Core 구현. 결과·스틴트는 부모에 매달아 그래프째 추가한다(Id를 미리 채워 두므로
/// 새 엔티티 5종의 <c>ValueGeneratedNever</c> 매핑 아래서 INSERT가 된다).
/// </summary>
public sealed class GameSessionRepository : IGameSessionRepository
{
    private readonly AppDbContext _context;

    public GameSessionRepository(AppDbContext context) => _context = context;

    /// <remarks>
    /// 전역 soft-delete 필터가 Include된 결과·스틴트에도 적용되어 활성 행만 실린다(재분류 병합이 지워진 행을 건드리지 않게).
    /// 결과 → 스틴트 두 컬렉션을 한 쿼리로 합치면 행이 곱해지므로 분할 쿼리로 읽는다.
    /// </remarks>
    public Task<GameSession?> GetByKeyWithResultsAsync(
        Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
        => _context.GameSessions
            .Include(s => s.Results)
            .ThenInclude(r => r.TyreStints)
            .AsSplitQuery()
            .FirstOrDefaultAsync(
                s => s.UserId == userId && s.GameCode == gameCode && s.SessionKey == sessionKey, cancellationToken);

    public async Task AddAsync(GameSession session, CancellationToken cancellationToken = default)
        => await _context.GameSessions.AddAsync(session, cancellationToken);
}
