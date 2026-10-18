using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// ILapQueryRepository의 EF Core 구현(15 §4.2). 읽기 전용 — 모두 <c>AsNoTracking</c> + <c>UserId</c> 조건.
/// 랩 행은 <see cref="Project"/> 한 프로젝션으로 트랙 이름·국가, 스냅샷의 팀·날씨(left join), 트레이스 유무(EXISTS), 섹터를 함께 읽는다.
/// 주의(Ruling R10): <c>Lap.AgentDevice</c>는 거치지 않는다 — 연결 해제된 장치의 랩이 사라진다.
/// </summary>
public sealed class LapQueryRepository : ILapQueryRepository
{
    private readonly AppDbContext _context;

    public LapQueryRepository(AppDbContext context) => _context = context;

    public async Task<(IReadOnlyList<LapRow> Items, int Total)> GetMyPageAsync(
        Guid userId, MyLapsFilter filter, MyLapsSort sort, int skip, int take, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(filter);

        var query = Mine(userId);
        if (filter.TrackId is { } trackId)
        {
            query = query.Where(l => l.TrackId == trackId);
        }

        if (filter.SessionType is { } sessionType)
        {
            query = query.Where(l => l.SessionType == sessionType);
        }

        if (filter.ValidOnly)
        {
            query = query.Where(l => l.IsValid);
        }

        var total = await query.CountAsync(cancellationToken);
        var items = await Project(Order(query, sort).Skip(skip).Take(take)).ToListAsync(cancellationToken);

        return (items, total);
    }

    public Task<LapRow?> GetMineAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
        => Project(Mine(userId).Where(l => l.Id == lapId)).FirstOrDefaultAsync(cancellationToken);

    public Task<LapRow?> GetMyFastestValidAsync(
        Guid userId, Guid trackId, string gameCode, CancellationToken cancellationToken = default)
        => Project(Mine(userId)
                .Where(l => l.TrackId == trackId && l.GameCode == gameCode && l.IsValid)
                .OrderBy(l => l.LapTimeMs)
                .ThenBy(l => l.SetAt)
                .ThenBy(l => l.Id)
                .Take(1))
            .FirstOrDefaultAsync(cancellationToken);

    public Task<LapSnapshot?> GetSnapshotAsync(Guid lapId, CancellationToken cancellationToken = default)
        => _context.LapSnapshots.AsNoTracking().FirstOrDefaultAsync(s => s.LapId == lapId, cancellationToken);

    public Task<LapTelemetryTrace?> GetMyTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
        => (from trace in _context.LapTelemetryTraces.AsNoTracking()
            join lap in Mine(userId) on trace.LapId equals lap.Id
            where lap.Id == lapId
            select trace)
            .FirstOrDefaultAsync(cancellationToken);

    private IQueryable<Lap> Mine(Guid userId) => _context.Laps.AsNoTracking().Where(l => l.UserId == userId);

    /// <summary>
    /// 정렬 적용. Fastest = 유효 랩 우선 → 랩타임 오름차순 → 먼저 세운 순. 그 외(Recent 포함)는 최근 순.
    /// 동률이 나와도 페이지 경계가 흔들리지 않도록 마지막에 Id로 결정적 순서를 보장한다.
    /// </summary>
    private static IOrderedQueryable<Lap> Order(IQueryable<Lap> query, MyLapsSort sort)
        => sort == MyLapsSort.Fastest
            ? query.OrderByDescending(l => l.IsValid).ThenBy(l => l.LapTimeMs).ThenBy(l => l.SetAt).ThenBy(l => l.Id)
            : query.OrderByDescending(l => l.SetAt).ThenBy(l => l.Id);

    /// <summary>랩 → 읽기 행(쿼리 1회). 트랙은 필수 관계(inner join), 스냅샷은 선택 관계(left join).</summary>
    private IQueryable<LapRow> Project(IQueryable<Lap> laps)
        => laps.Select(l => new LapRow(
            l.Id,
            l.TrackId,
            l.Track!.Name,
            l.Track.CountryCode,
            l.GameCode,
            l.SessionType,
            l.LapNumber,
            l.LapTimeMs,
            l.IsValid,
            l.IsRankingEligible,
            l.SetAt,
            l.GameMode,
            l.SessionKey,
            l.Snapshot == null ? null : l.Snapshot.TeamId,
            l.Snapshot == null ? null : l.Snapshot.Weather,
            _context.LapTelemetryTraces.Any(t => t.LapId == l.Id),
            l.Sectors
                .OrderBy(s => s.SectorNumber)
                .Select(s => new LapSectorDto(s.SectorNumber, s.SectorTimeMs))
                .ToList()));
}
