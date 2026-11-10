using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.AiDifficulty;
using SimCenter.Application.Trends;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>
/// <see cref="ITrendsQueryRepository"/>의 EF Core 구현. 읽기 전용 — 모두 <c>AsNoTracking</c>이고 메서드마다 쿼리 1회다.
/// 삭제된 행은 전역 쿼리 필터로 제외된다.
/// </summary>
public sealed class TrendsQueryRepository : ITrendsQueryRepository
{
    private readonly AppDbContext _context;

    public TrendsQueryRepository(AppDbContext context) => _context = context;

    public async Task<IReadOnlyList<TrendResultRow>> GetMyResultRowsAsync(
        Guid userId, string? gameCode, CancellationToken cancellationToken = default)
    {
        var sessions = _context.GameSessions.AsNoTracking().Where(s =>
            s.UserId == userId && (s.SessionType == SessionType.Qualifying || s.SessionType == SessionType.Race));
        if (gameCode is not null)
        {
            sessions = sessions.Where(s => s.GameCode == gameCode);
        }

        var rows = await (
                from result in _context.SessionResults.AsNoTracking()
                join session in sessions on result.GameSessionId equals session.Id
                orderby session.ClassifiedAt, session.Id, result.CarIndex
                select new
                {
                    WeekendId = session.RaceWeekendId,
                    session.Id,
                    session.SessionKey,
                    session.SessionType,
                    session.SessionKind,
                    session.ClassifiedAt,
                    session.AiDifficulty,
                    session.GameCode,
                    session.GameMode,
                    session.TrackId,
                    session.IsImported,
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
                    result.NumLaps,
                })
            .ToListAsync(cancellationToken);

        return rows
            .Select(x => new TrendResultRow(
                new AiPaceRow(
                    x.WeekendId ?? Guid.Empty, x.Id, x.SessionKey, x.SessionType, x.SessionKind, x.ClassifiedAt, x.AiDifficulty,
                    x.DriverKey, x.DriverName, x.CarIndex, x.TeamId, x.IsPlayer, x.IsAiControlled, x.Position, x.GridPosition,
                    x.ResultStatus, x.BestLapTimeMs, x.TotalRaceTimeMs, x.NumLaps),
                x.GameCode,
                x.GameMode,
                x.TrackId,
                x.IsImported,
                x.WeekendId is not null))
            .ToList();
    }

    public async Task<IReadOnlyList<TrendLapRow>> GetMyLapsAsync(
        Guid userId, string? gameCode, CancellationToken cancellationToken = default)
    {
        var laps = _context.Laps.AsNoTracking().Where(l => l.UserId == userId);
        if (gameCode is not null)
        {
            laps = laps.Where(l => l.GameCode == gameCode);
        }

        return await laps
            .Select(l => new TrendLapRow(
                l.TrackId, l.SessionKey, l.SessionType, l.LapNumber, l.LapTimeMs, l.IsValid && !l.IsInvalidatedManually, l.SetAt))
            .ToListAsync(cancellationToken);
    }
}
