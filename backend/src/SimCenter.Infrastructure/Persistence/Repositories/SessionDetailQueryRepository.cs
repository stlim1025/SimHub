using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// ISessionDetailQueryRepository의 EF Core 구현(P8, docs/15 §11.4 D-53). 읽기 전용 — 모두 <c>AsNoTracking</c> + <c>UserId</c> 조건,
/// 메서드마다 쿼리 1회. 삭제된 행은 전역 쿼리 필터로 빠진다. <c>Lap.AgentDevice</c>는 거치지 않는다(Ruling R10).
/// </summary>
public sealed class SessionDetailQueryRepository : ISessionDetailQueryRepository
{
    private const int SectorCount = 3;

    private readonly AppDbContext _context;

    public SessionDetailQueryRepository(AppDbContext context) => _context = context;

    /// <remarks>
    /// 트랙 조건을 함께 걸어 (UserId, TrackId, …) 인덱스 앞부분을 탄다. 스냅샷은 left join 프로젝션, 섹터는 상관 서브쿼리 — 랩마다 따로 읽지 않는다.
    /// </remarks>
    public async Task<IReadOnlyList<SessionLapRow>> GetMySessionLapsAsync(
        Guid userId, string gameCode, Guid trackId, string sessionKey, CancellationToken cancellationToken = default)
    {
        var rows = await _context.Laps
            .AsNoTracking()
            .Where(l => l.UserId == userId && l.TrackId == trackId && l.GameCode == gameCode && l.SessionKey == sessionKey)
            .OrderBy(l => l.LapNumber)
            .ThenBy(l => l.SetAt)
            .Select(l => new
            {
                l.Id,
                l.LapNumber,
                l.LapTimeMs,
                l.IsValid,
                l.SetAt,
                Sectors = l.Sectors
                    .OrderBy(s => s.SectorNumber)
                    .Select(s => new { s.SectorNumber, s.SectorTimeMs })
                    .ToList(),
                Snapshot = l.Snapshot == null
                    ? null
                    : new
                    {
                        l.Snapshot.Details,
                        l.Snapshot.Weather,
                        l.Snapshot.TyreWearEndFrontLeft,
                        l.Snapshot.TyreWearEndFrontRight,
                        l.Snapshot.TyreWearEndRearLeft,
                        l.Snapshot.TyreWearEndRearRight,
                        l.Snapshot.GearboxDamage,
                        l.Snapshot.EngineDamage,
                    },
            })
            .ToListAsync(cancellationToken);

        return rows
            .Select(l => new SessionLapRow(
                l.Id,
                l.LapNumber,
                l.LapTimeMs,
                l.IsValid,
                l.SetAt,
                Enumerable.Range(1, SectorCount)
                    .Select(n => l.Sectors.FirstOrDefault(s => s.SectorNumber == n) is { } sector ? (int?)sector.SectorTimeMs : null)
                    .ToList(),
                l.Snapshot?.Details,
                l.Snapshot?.Weather,
                l.Snapshot?.TyreWearEndFrontLeft,
                l.Snapshot?.TyreWearEndFrontRight,
                l.Snapshot?.TyreWearEndRearLeft,
                l.Snapshot?.TyreWearEndRearRight,
                l.Snapshot?.GearboxDamage,
                l.Snapshot?.EngineDamage))
            .ToList();
    }

    public async Task<IReadOnlyList<WeekendQualifyingRow>> GetMyWeekendQualifyingAsync(
        Guid userId, Guid raceWeekendId, CancellationToken cancellationToken = default)
        => await _context.GameSessions
            .AsNoTracking()
            .Where(s => s.UserId == userId && s.RaceWeekendId == raceWeekendId && s.SessionType == SessionType.Qualifying)
            .Select(s => new WeekendQualifyingRow(
                s.Id,
                s.SessionKind,
                s.ClassifiedAt,
                s.Results
                    .Where(r => r.IsPlayer)
                    .OrderBy(r => r.CarIndex)
                    // 순위 0 = 모름 → null.
                    .Select(r => r.Position > 0 ? (int?)r.Position : null)
                    .FirstOrDefault()))
            .ToListAsync(cancellationToken);

    public Task<bool> IsMySprintWeekendAsync(Guid userId, Guid raceWeekendId, CancellationToken cancellationToken = default)
        => _context.GameSessions
            .AsNoTracking()
            .AnyAsync(s => s.UserId == userId && s.RaceWeekendId == raceWeekendId && s.SessionKind == SessionKind.Race2, cancellationToken);

    public async Task<IReadOnlyList<SeasonOrderRow>> GetMySeasonOrderAsync(Guid userId, CancellationToken cancellationToken = default)
        => await _context.Seasons
            .AsNoTracking()
            .Where(s => s.UserId == userId)
            .Select(s => new SeasonOrderRow(s.Id, s.GameCode, s.GameMode, s.FirstSessionAt))
            .ToListAsync(cancellationToken);
}
