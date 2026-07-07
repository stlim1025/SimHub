using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Seed;

/// <summary>
/// 마스터/초기 데이터 시드(멱등). 시작 시 1회 실행한다.
/// - Store 1개(MVP 단일 매장, D-1은 멀티스토어 선반영)
/// - SimRig 4개(A-01~A-04)
/// - Track 마스터: F1 25 UDP m_trackId 매핑(Codemasters 표준).
/// PK는 IIdGenerator(UUID v7), 시각은 IClock으로 주입한다.
/// </summary>
public sealed class DbSeeder
{
    private const string SeedStoreName = "SimCenter 1호점";

    // F1 25 UDP m_trackId → 트랙명(Codemasters 표준 매핑).
    private static readonly (int GameTrackId, string Name)[] F1Tracks =
    [
        (0, "Melbourne"),
        (1, "Paul Ricard"),
        (2, "Shanghai"),
        (3, "Sakhir (Bahrain)"),
        (4, "Catalunya"),
        (5, "Monaco"),
        (6, "Montreal"),
        (7, "Silverstone"),
        (8, "Hockenheim"),
        (9, "Hungaroring"),
        (10, "Spa"),
        (11, "Monza"),
        (12, "Singapore"),
        (13, "Suzuka"),
        (14, "Abu Dhabi"),
        (15, "Texas (COTA)"),
        (16, "Brazil (Interlagos)"),
        (17, "Austria (Red Bull Ring)"),
        (19, "Mexico"),
        (20, "Baku (Azerbaijan)"),
        (26, "Zandvoort"),
        (27, "Imola"),
        (28, "Portimão"),
        (29, "Jeddah"),
        (30, "Miami"),
        (31, "Las Vegas"),
        (32, "Losail (Qatar)"),
    ];

    private static readonly (string RigCode, string DisplayName)[] SeedRigs =
    [
        ("A-01", "1번 좌석"),
        ("A-02", "2번 좌석"),
        ("A-03", "3번 좌석"),
        ("A-04", "4번 좌석"),
    ];

    private readonly AppDbContext _context;
    private readonly IIdGenerator _idGenerator;
    private readonly IClock _clock;

    public DbSeeder(AppDbContext context, IIdGenerator idGenerator, IClock clock)
    {
        _context = context;
        _idGenerator = idGenerator;
        _clock = clock;
    }

    public async Task SeedAsync(CancellationToken cancellationToken = default)
    {
        var now = _clock.UtcNow;

        var store = await SeedStoreAsync(now, cancellationToken);
        await SeedRigsAsync(store.Id, now, cancellationToken);
        await SeedTracksAsync(now, cancellationToken);

        await _context.SaveChangesAsync(cancellationToken);
    }

    private async Task<Store> SeedStoreAsync(DateTime now, CancellationToken cancellationToken)
    {
        var store = await _context.Stores.FirstOrDefaultAsync(x => x.Name == SeedStoreName, cancellationToken);
        if (store is not null)
        {
            return store;
        }

        store = new Store { Id = _idGenerator.NewId(), Name = SeedStoreName, CreatedAt = now };
        await _context.Stores.AddAsync(store, cancellationToken);
        return store;
    }

    private async Task SeedRigsAsync(Guid storeId, DateTime now, CancellationToken cancellationToken)
    {
        var existingCodes = await _context.SimRigs.Select(x => x.RigCode).ToListAsync(cancellationToken);
        var existing = existingCodes.ToHashSet();

        foreach (var (rigCode, displayName) in SeedRigs)
        {
            if (existing.Contains(rigCode))
            {
                continue;
            }

            await _context.SimRigs.AddAsync(new SimRig
            {
                Id = _idGenerator.NewId(),
                StoreId = storeId,
                RigCode = rigCode,
                DisplayName = displayName,
                CreatedAt = now,
            }, cancellationToken);
        }
    }

    private async Task SeedTracksAsync(DateTime now, CancellationToken cancellationToken)
    {
        var existingIds = await _context.Tracks
            .Where(x => x.GameCode == GameCodes.F1_25)
            .Select(x => x.GameTrackId)
            .ToListAsync(cancellationToken);
        var existing = existingIds.ToHashSet();

        foreach (var (gameTrackId, name) in F1Tracks)
        {
            if (existing.Contains(gameTrackId))
            {
                continue;
            }

            await _context.Tracks.AddAsync(new Track
            {
                Id = _idGenerator.NewId(),
                GameCode = GameCodes.F1_25,
                GameTrackId = gameTrackId,
                Name = name,
                CreatedAt = now,
            }, cancellationToken);
        }
    }
}
