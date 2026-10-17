namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 여러 영속화 단계를 하나의 DB 트랜잭션으로 묶는 포트. 작업이 예외 없이 끝나야만 커밋하고,
/// 예외가 나면 커밋 없이 롤백된다. 구현은 Infrastructure(DbContext 트랜잭션).
/// </summary>
public interface ITransactionRunner
{
    Task<T> RunAsync<T>(Func<CancellationToken, Task<T>> work, CancellationToken cancellationToken = default);
}
