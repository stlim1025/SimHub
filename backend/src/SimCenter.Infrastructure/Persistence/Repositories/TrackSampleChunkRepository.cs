using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>ITrackSampleChunkRepository의 EF Core 구현.</summary>
public sealed class TrackSampleChunkRepository : ITrackSampleChunkRepository
{
    private readonly AppDbContext _context;

    public TrackSampleChunkRepository(AppDbContext context) => _context = context;

    public Task<bool> ExistsAsync(Guid agentDeviceId, string sessionRef, int chunkIndex, CancellationToken cancellationToken = default)
        => _context.TrackSampleChunks.AnyAsync(
            x => x.AgentDeviceId == agentDeviceId && x.SessionRef == sessionRef && x.ChunkIndex == chunkIndex,
            cancellationToken);

    public async Task AddAsync(TrackSampleChunk chunk, CancellationToken cancellationToken = default)
        => await _context.TrackSampleChunks.AddAsync(chunk, cancellationToken);

    public async Task<IReadOnlyList<StoredTrackSampleChunk>> ListForTrackAsync(
        Guid trackId, string gameCode, CancellationToken cancellationToken = default)
        => await _context.TrackSampleChunks
            .AsNoTracking()
            .Where(x => x.TrackId == trackId && x.GameCode == gameCode && !x.IsDeleted)
            .OrderBy(x => x.CreatedAt)
            .ThenBy(x => x.ChunkIndex)
            .Select(x => new StoredTrackSampleChunk(x.SessionRef, x.ChunkIndex, x.Format, x.Payload, x.TrackLengthM))
            .ToListAsync(cancellationToken);

    public async Task<IReadOnlyList<StoredTrackSampleChunk>> ListForSessionAsync(
        Guid userId, string sessionRef, CancellationToken cancellationToken = default)
        => await _context.TrackSampleChunks
            .AsNoTracking()
            .Where(x => x.UserId == userId && x.SessionRef == sessionRef && !x.IsDeleted)
            .OrderBy(x => x.ChunkIndex)
            .Select(x => new StoredTrackSampleChunk(x.SessionRef, x.ChunkIndex, x.Format, x.Payload, x.TrackLengthM))
            .ToListAsync(cancellationToken);

    public async Task<IReadOnlyList<UnclassifiedSampleSession>> ListUnclassifiedSessionsAsync(
        Guid userId, Guid trackId, string gameCode, SessionType sessionType, DateTime before,
        CancellationToken cancellationToken = default)
        => await _context.TrackSampleChunks
            .AsNoTracking()
            .Where(x => x.UserId == userId && x.TrackId == trackId && x.GameCode == gameCode && x.SessionType == sessionType
                        && !x.IsDeleted
                        && !_context.GameSessions.Any(g => g.UserId == userId && g.SessionRef == x.SessionRef && !g.IsDeleted))
            .GroupBy(x => x.SessionRef)
            .Select(g => new { SessionRef = g.Key, First = g.Min(x => x.CreatedAt) })
            .Where(s => s.First < before)
            .OrderByDescending(s => s.First)
            .Select(s => new UnclassifiedSampleSession(s.SessionRef, s.First))
            .ToListAsync(cancellationToken);

    public async Task<DateTime?> FirstReceivedAtAsync(Guid userId, string sessionRef, CancellationToken cancellationToken = default)
        => await _context.TrackSampleChunks
            .AsNoTracking()
            .Where(x => x.UserId == userId && x.SessionRef == sessionRef && !x.IsDeleted)
            .MinAsync(x => (DateTime?)x.CreatedAt, cancellationToken);
}
