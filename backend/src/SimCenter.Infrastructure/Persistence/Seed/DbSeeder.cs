using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Seed;

/// <summary>
/// 마스터 데이터 시드(멱등). 시작 시 1회 실행한다.
/// - Track 마스터: F1 25 UDP m_trackId 매핑(Codemasters 표준). 없는 트랙은 추가하고, 있는 트랙은 국가·표시 순서만 시드 값으로 맞춘다(D-43).
///   기존 행의 이름은 바꾸지 않는다.
/// 개인 모드(D-25)에서는 매장·좌석·개발용 좌석 키를 시드하지 않는다. Agent는 연결 코드로 장치 키를 받는다(D-26).
/// PK는 IIdGenerator(UUID v7), 시각은 IClock으로 주입한다.
/// </summary>
public sealed class DbSeeder
{
    // F1 25 UDP m_trackId → 트랙명·국가(ISO 3166-1 alpha-2). 배열 순서가 표시 순서(1부터)다 — 15 §4.1의 표:
    // F1 25 캘린더 24개 → 리버스 3개 → Madrid → 옛 트랙(1·8·28).
    // Agent의 F1Game.UDP(25.1.1) Track enum 값과 2026 시즌팩 Madrid(42)를 모두 덮어야 한다(D-41) —
    // 매핑이 없으면 그 트랙의 랩·세션 결과가 Reject되어 영구 손실된다(TrackSeedE2ETests가 확인). 1·8·28은 이전 연식 트랙이라 그대로 둔다.
    private static readonly (int GameTrackId, string Name, string CountryCode)[] F1Tracks =
    [
        (0, "Melbourne", "AU"),
        (2, "Shanghai", "CN"),
        (13, "Suzuka", "JP"),
        (3, "Sakhir (Bahrain)", "BH"),
        (29, "Jeddah", "SA"),
        (30, "Miami", "US"),
        (27, "Imola", "IT"),
        (5, "Monaco", "MC"),
        (4, "Catalunya", "ES"),
        (6, "Montreal", "CA"),
        (17, "Austria (Red Bull Ring)", "AT"),
        (7, "Silverstone", "GB"),
        (10, "Spa", "BE"),
        (9, "Hungaroring", "HU"),
        (26, "Zandvoort", "NL"),
        (11, "Monza", "IT"),
        (20, "Baku (Azerbaijan)", "AZ"),
        (12, "Singapore", "SG"),
        (15, "Texas (COTA)", "US"),
        (19, "Mexico", "MX"),
        (16, "Brazil (Interlagos)", "BR"),
        (31, "Las Vegas", "US"),
        (32, "Losail (Qatar)", "QA"),
        (14, "Abu Dhabi", "AE"),
        (41, "Zandvoort (Reverse)", "NL"),
        (40, "Austria (Red Bull Ring, Reverse)", "AT"),
        (39, "Silverstone (Reverse)", "GB"),
        (42, "Madrid (Madring)", "ES"),
        (1, "Paul Ricard", "FR"),
        (8, "Hockenheim", "DE"),
        (28, "Portimão", "PT"),
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
        var existing = await _context.Tracks
            .Where(x => x.GameCode == GameCodes.F1_25)
            .ToDictionaryAsync(x => x.GameTrackId, cancellationToken);

        for (var index = 0; index < F1Tracks.Length; index++)
        {
            var (gameTrackId, name, countryCode) = F1Tracks[index];
            var displayOrder = index + 1;

            if (existing.TryGetValue(gameTrackId, out var track))
            {
                ApplyDisplayInfo(track, countryCode, displayOrder, now);
                continue;
            }

            await _context.Tracks.AddAsync(new Track
            {
                Id = _idGenerator.NewId(),
                GameCode = GameCodes.F1_25,
                GameTrackId = gameTrackId,
                Name = name,
                CountryCode = countryCode,
                DisplayOrder = displayOrder,
                CreatedAt = now,
            }, cancellationToken);
        }
    }

    /// <summary>기존 행의 국가·표시 순서를 시드 값으로 맞춘다(이름은 그대로). 바뀐 경우에만 UpdatedAt을 남긴다.</summary>
    private static void ApplyDisplayInfo(Track track, string countryCode, int displayOrder, DateTime now)
    {
        if (track.CountryCode == countryCode && track.DisplayOrder == displayOrder)
        {
            return;
        }

        track.CountryCode = countryCode;
        track.DisplayOrder = displayOrder;
        track.UpdatedAt = now;
    }
}
