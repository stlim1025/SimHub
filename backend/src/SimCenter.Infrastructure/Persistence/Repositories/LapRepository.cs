using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>ILapRepository의 EF Core 구현. Sectors는 관계로 함께 삽입된다(cascade).</summary>
public sealed class LapRepository : ILapRepository
{
    private readonly AppDbContext _context;

    public LapRepository(AppDbContext context) => _context = context;

    public async Task AddAsync(Lap lap, CancellationToken cancellationToken = default)
        => await _context.Laps.AddAsync(lap, cancellationToken);
}
