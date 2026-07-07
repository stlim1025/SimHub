using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>User 영속성 포트(Repository Pattern). 구현은 Infrastructure(EF Core).</summary>
public interface IUserRepository
{
    Task<User?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    Task<User?> GetByEmailAsync(string email, CancellationToken cancellationToken = default);

    Task<bool> ExistsByEmailAsync(string email, CancellationToken cancellationToken = default);

    Task AddAsync(User user, CancellationToken cancellationToken = default);
}
