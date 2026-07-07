namespace SimCenter.Application.Common.Interfaces;

/// <summary>트랜잭션 경계/영속화 커밋 포트. 구현은 Infrastructure(DbContext.SaveChanges).</summary>
public interface IUnitOfWork
{
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
