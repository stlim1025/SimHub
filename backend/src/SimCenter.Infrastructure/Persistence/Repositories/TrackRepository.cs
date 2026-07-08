using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>ITrackRepository의 EF Core 구현.</summary>
public sealed class TrackRepository : ITrackRepository
{
    private readonly AppDbContext _context;

    public TrackRepository(AppDbContext context) => _context = context;

    public Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken cancellationToken = default)
        => _context.Tracks.FirstOrDefaultAsync(
            x => x.GameCode == gameCode && x.GameTrackId == gameTrackId, cancellationToken);

    public Task<Track?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
        => _context.Tracks.FirstOrDefaultAsync(x => x.Id == id, cancellationToken);

    public async Task<IReadOnlyList<Track>> GetAllAsync(CancellationToken cancellationToken = default)
        => await _context.Tracks
            .AsNoTracking()
            .OrderBy(x => x.GameCode)
            .ThenBy(x => x.Name)
            .ToListAsync(cancellationToken);
}
