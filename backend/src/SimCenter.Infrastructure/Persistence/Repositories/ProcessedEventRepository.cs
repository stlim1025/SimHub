using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>IProcessedEventRepository의 EF Core 구현(멱등 원장).</summary>
public sealed class ProcessedEventRepository : IProcessedEventRepository
{
    private readonly AppDbContext _context;

    public ProcessedEventRepository(AppDbContext context) => _context = context;

    public Task<bool> ExistsAsync(Guid eventId, CancellationToken cancellationToken = default)
        => _context.ProcessedEvents.AnyAsync(x => x.EventId == eventId, cancellationToken);

    public async Task AddAsync(ProcessedEvent processedEvent, CancellationToken cancellationToken = default)
        => await _context.ProcessedEvents.AddAsync(processedEvent, cancellationToken);
}
