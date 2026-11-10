using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.AiDifficulty;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// <see cref="IAiDifficultyQueryRepository"/>의 EF Core 구현. 읽기 전용 — 모두 <c>AsNoTracking</c>이고 메서드마다 쿼리 1회다.
/// 삭제된 행은 전역 쿼리 필터로 제외된다.
/// </summary>
public sealed class AiDifficultyQueryRepository : IAiDifficultyQueryRepository
{
    private readonly AppDbContext _context;

    public AiDifficultyQueryRepository(AppDbContext context) => _context = context;

    public async Task<IReadOnlyList<AiPaceRow>> GetPaceRowsAsync(Guid seasonId, CancellationToken cancellationToken = default)
    {
        return await (
                from result in _context.SessionResults.AsNoTracking()
                join session in _context.GameSessions.AsNoTracking() on result.GameSessionId equals session.Id
                where session.SeasonId == seasonId
                    && session.RaceWeekendId != null
                    && !session.IsImported
                    && (session.SessionType == SessionType.Qualifying || session.SessionType == SessionType.Race)
                orderby session.ClassifiedAt, session.Id, result.CarIndex
                select new AiPaceRow(
                    session.RaceWeekendId!.Value,
                    session.Id,
                    session.SessionKey,
                    session.SessionType,
                    session.SessionKind,
                    session.ClassifiedAt,
                    session.AiDifficulty,
                    result.DriverKey,
                    result.DriverName,
                    result.CarIndex,
                    result.TeamId,
                    result.IsPlayer,
                    result.IsAiControlled,
                    result.Position,
                    result.GridPosition,
                    result.ResultStatus,
                    result.BestLapTimeMs,
                    result.TotalRaceTimeMs,
                    result.NumLaps))
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<SessionLapWeatherRow>> GetMyLapWeatherAsync(
        Guid userId, IReadOnlyCollection<string> sessionKeys, CancellationToken cancellationToken = default)
    {
        if (sessionKeys.Count == 0)
        {
            return [];
        }

        var keys = sessionKeys.ToArray();
        return await (
                from lap in _context.Laps.AsNoTracking()
                join snapshot in _context.LapSnapshots.AsNoTracking() on lap.Id equals snapshot.LapId
                where lap.UserId == userId
                    && lap.SessionKey != null
                    && keys.Contains(lap.SessionKey)
                    && snapshot.Weather != null
                select new SessionLapWeatherRow(lap.SessionKey!, snapshot.Weather!.Value))
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<TimeTrialLapRow>> GetMyTimeTrialLapsAsync(
        Guid userId, string gameCode, IReadOnlyCollection<Guid> trackIds, CancellationToken cancellationToken = default)
    {
        if (trackIds.Count == 0)
        {
            return [];
        }

        var ids = trackIds.ToArray();
        return await (
                from lap in _context.Laps.AsNoTracking()
                join snapshot in _context.LapSnapshots.AsNoTracking() on lap.Id equals snapshot.LapId into snapshots
                from snapshot in snapshots.DefaultIfEmpty()
                where lap.UserId == userId
                    && lap.GameCode == gameCode
                    && lap.SessionType == SessionType.TimeTrial
                    && lap.IsValid
                    && !lap.IsInvalidatedManually
                    && ids.Contains(lap.TrackId)
                select new TimeTrialLapRow(lap.TrackId, lap.LapTimeMs, snapshot == null ? null : snapshot.Weather))
            .ToListAsync(cancellationToken);
    }
}
