using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>IDrivingSessionRepository의 EF Core 구현.</summary>
public sealed class DrivingSessionRepository : IDrivingSessionRepository
{
    private readonly AppDbContext _context;

    public DrivingSessionRepository(AppDbContext context) => _context = context;

    public Task<DrivingSession?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
        => _context.DrivingSessions.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);

    public Task<DrivingSession?> GetActiveByRigAsync(Guid simRigId, CancellationToken cancellationToken = default)
        => _context.DrivingSessions
            .FirstOrDefaultAsync(x => x.SimRigId == simRigId && x.Status == SessionStatus.Active, cancellationToken);

    public Task<DrivingSession?> GetActiveByUserAsync(Guid userId, CancellationToken cancellationToken = default)
        => _context.DrivingSessions
            .Include(x => x.SimRig)
            .Where(x => x.UserId == userId && x.Status == SessionStatus.Active)
            .OrderByDescending(x => x.StartedAt)
            .FirstOrDefaultAsync(cancellationToken);

    public async Task<IReadOnlyList<DrivingSession>> GetActiveSessionsByUserAsync(Guid userId, CancellationToken cancellationToken = default)
        => await _context.DrivingSessions
            .Where(x => x.UserId == userId && x.Status == SessionStatus.Active)
            .ToListAsync(cancellationToken);

    public async Task AddAsync(DrivingSession session, CancellationToken cancellationToken = default)
        => await _context.DrivingSessions.AddAsync(session, cancellationToken);
}
