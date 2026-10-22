using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// ITrackOverviewQueryRepository의 EF Core 구현(no tracking). <c>Lap.AgentDevice</c>는 거치지 않는다(Ruling R10).
/// Time Trial 상위는 랭킹(<c>LapRepository.GetRankingAsync</c>)과 같은 적격 기준(Time Trial + 랭킹 적격)에 기간만 없앤 것이다.
/// </summary>
public sealed class TrackOverviewQueryRepository : ITrackOverviewQueryRepository
{
    private readonly AppDbContext _context;

    public TrackOverviewQueryRepository(AppDbContext context) => _context = context;

    public async Task<TrackMyStatsRow> GetMyStatsAsync(Guid userId, Guid trackId, CancellationToken cancellationToken = default)
    {
        var mine = _context.Laps.AsNoTracking().Where(l => l.UserId == userId && l.TrackId == trackId);
        var valid = mine.Where(l => l.IsValid);

        var lapCount = await mine.CountAsync(cancellationToken);
        var sessionCount = await mine
            .Where(l => l.SessionKey != null)
            .Select(l => l.SessionKey)
            .Distinct()
            .CountAsync(cancellationToken);
        var bestLapMs = await valid.MinAsync(l => (int?)l.LapTimeMs, cancellationToken);
        var bestTimeTrialMs = await mine
            .Where(l => l.IsRankingEligible && l.SessionType == SessionType.TimeTrial)
            .MinAsync(l => (int?)l.LapTimeMs, cancellationToken);
        var averageLapMs = await valid.AverageAsync(l => (double?)l.LapTimeMs, cancellationToken);
        var averageAi = await _context.GameSessions
            .AsNoTracking()
            .Where(s => s.UserId == userId && s.TrackId == trackId && !s.IsImported && s.AiDifficulty > 0)
            .AverageAsync(s => (double?)s.AiDifficulty, cancellationToken);

        return new TrackMyStatsRow(lapCount, sessionCount, bestLapMs, bestTimeTrialMs, averageLapMs, averageAi);
    }

    public async Task<IReadOnlyList<TrackTopLapRow>> GetTopTimeTrialAsync(
        Guid trackId, string gameCode, int top, CancellationToken cancellationToken = default)
    {
        var eligible = _context.Laps
            .AsNoTracking()
            .Where(l => l.TrackId == trackId
                && l.GameCode == gameCode
                && l.SessionType == SessionType.TimeTrial
                && l.IsRankingEligible);

        // 1) 사용자별 최고 랩타임 상위 N.
        var best = await eligible
            .GroupBy(l => l.UserId)
            .Select(g => new { UserId = g.Key, BestMs = g.Min(l => l.LapTimeMs) })
            .OrderBy(x => x.BestMs)
            .Take(top)
            .ToListAsync(cancellationToken);
        if (best.Count == 0)
        {
            return [];
        }

        // 2) 그 사용자들의 최고 랩(같은 시간이면 먼저 세운 랩)·팀·이름.
        var userIds = best.Select(b => b.UserId).ToList();
        var laps = await eligible
            .Where(l => userIds.Contains(l.UserId))
            .Select(l => new
            {
                l.Id,
                l.UserId,
                l.LapTimeMs,
                l.SetAt,
                TeamId = l.Snapshot == null ? null : l.Snapshot.TeamId,
            })
            .ToListAsync(cancellationToken);
        var users = await _context.Users
            .AsNoTracking()
            .Where(u => userIds.Contains(u.Id))
            .Select(u => new { u.Id, u.DisplayName, u.ShowOnLeaderboard })
            .ToDictionaryAsync(u => u.Id, cancellationToken);

        return best
            .Select(b =>
            {
                var lap = laps
                    .Where(l => l.UserId == b.UserId)
                    .OrderBy(l => l.LapTimeMs)
                    .ThenBy(l => l.SetAt)
                    .ThenBy(l => l.Id)
                    .First();

                // 사용자 행이 없으면(soft delete 등) 비공개로 둔다 → 서비스가 익명으로 보인다.
                var found = users.TryGetValue(b.UserId, out var user);
                return new TrackTopLapRow(
                    b.UserId,
                    found ? user!.DisplayName : string.Empty,
                    found && user!.ShowOnLeaderboard,
                    lap.Id,
                    lap.LapTimeMs,
                    lap.TeamId);
            })
            .ToList();
    }

    public async Task<IReadOnlyList<TrackMyLapRow>> GetMyBestLapsAsync(
        Guid userId, Guid trackId, int take, CancellationToken cancellationToken = default)
        => await _context.Laps
            .AsNoTracking()
            .Where(l => l.UserId == userId && l.TrackId == trackId && l.IsValid)
            .OrderBy(l => l.LapTimeMs)
            .ThenBy(l => l.SetAt)
            .ThenBy(l => l.Id)
            .Take(take)
            .Select(l => new TrackMyLapRow(
                l.Id,
                l.LapTimeMs,
                l.SessionType,
                l.Snapshot == null ? null : l.Snapshot.TeamId,
                l.IsValid,
                l.SetAt))
            .ToListAsync(cancellationToken);

    public async Task<IReadOnlyList<TrackTracedLapRow>> GetMyTracedLapsAsync(
        Guid userId, Guid trackId, int take, CancellationToken cancellationToken = default)
        => await (from lap in _context.Laps.AsNoTracking()
                  join trace in _context.LapTelemetryTraces.AsNoTracking() on lap.Id equals trace.LapId
                  where lap.UserId == userId && lap.TrackId == trackId
                  orderby lap.IsValid descending, lap.LapTimeMs, lap.SetAt, lap.Id
                  select new TrackTracedLapRow(lap.Id, trace.Payload))
            .Take(take)
            .ToListAsync(cancellationToken);
}
