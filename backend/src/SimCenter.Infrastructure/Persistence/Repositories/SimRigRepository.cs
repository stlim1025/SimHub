using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>ISimRigRepository의 EF Core 구현.</summary>
public sealed class SimRigRepository : ISimRigRepository
{
    private readonly AppDbContext _context;

    public SimRigRepository(AppDbContext context) => _context = context;

    public Task<SimRig?> GetByRigCodeAsync(string rigCode, CancellationToken cancellationToken = default)
        => _context.SimRigs.FirstOrDefaultAsync(x => x.RigCode == rigCode, cancellationToken);

    public Task<SimRig?> GetByApiKeyHashAsync(string apiKeyHash, CancellationToken cancellationToken = default)
        => _context.SimRigs.FirstOrDefaultAsync(x => x.ApiKeyHash == apiKeyHash, cancellationToken);
}
