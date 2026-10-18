using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Seed;

/// <summary>
/// 마스터 데이터 시드(멱등). 시작 시 1회 실행한다.
/// - Track 마스터: F1 25 UDP m_trackId 매핑(Codemasters 표준).
/// 개인 모드(D-25)에서는 매장·좌석·개발용 좌석 키를 시드하지 않는다. Agent는 연결 코드로 장치 키를 받는다(D-26).
/// PK는 IIdGenerator(UUID v7), 시각은 IClock으로 주입한다.
/// </summary>
public sealed class DbSeeder
{
    // F1 25 UDP m_trackId → 트랙명(Codemasters 표준 매핑). F1Game.UDP 26.0.0의 Track enum 값(2026 시즌팩 포함)을 모두 덮어야 한다 —
    // 매핑이 없으면 그 트랙의 랩·세션 결과가 Reject되어 영구 손실된다(TrackSeedE2ETests가 확인). 1·8·28은 이전 연식 트랙이라 그대로 둔다.
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
        (39, "Silverstone (Reverse)"),
        (40, "Austria (Red Bull Ring, Reverse)"),
        (41, "Zandvoort (Reverse)"),
        (42, "Madrid (Madring)"),
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
        await SeedTracksAsync(_clock.UtcNow, cancellationToken);

        await _context.SaveChangesAsync(cancellationToken);
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
