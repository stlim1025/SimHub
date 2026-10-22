using Microsoft.EntityFrameworkCore;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Infrastructure.Persistence.Repositories;

/// <summary>ISeasonImportRepository의 EF Core 구현(docs/15 §12, D-55). 삭제된 행은 전역 쿼리 필터로 제외된다.</summary>
public sealed class SeasonImportRepository : ISeasonImportRepository
{
    private readonly AppDbContext _context;

    public SeasonImportRepository(AppDbContext context) => _context = context;

    /// <remarks>결과는 미리보기 Standings에 쓰여 함께 읽는다(분할 쿼리 — 결과 × 스틴트 곱을 피한다).</remarks>
    public async Task<IReadOnlyList<GameSession>> GetUnseasonedLinkedSessionsAsync(
        Guid userId, string gameCode, IReadOnlyCollection<GameMode> modes, CancellationToken cancellationToken = default)
    {
        var modeList = modes.ToArray();
        return await _context.GameSessions
            .Include(s => s.Track)
            .Include(s => s.Results)
            .AsSplitQuery()
            .Where(s => s.UserId == userId
                && s.GameCode == gameCode
                && s.SeasonId == null
                && !s.IsImported
                && s.SeasonLinkId != 0
                && s.WeekendLinkId != 0
                && modeList.Contains(s.GameMode))
            .OrderBy(s => s.ClassifiedAt)
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<Season>> GetImportedSeasonsAsync(Guid userId, string gameCode, CancellationToken cancellationToken = default)
        => await _context.Seasons
            .AsNoTracking()
            .Where(s => s.UserId == userId && s.GameCode == gameCode && s.ImportedFrom != null)
            .ToListAsync(cancellationToken);

    /// <remarks>시즌 전역 필터가 지운 시즌을 빼므로 "활성 시즌이 없음" = 시즌이 삭제됨.</remarks>
    public async Task<IReadOnlyList<GameSession>> GetImportedSessionsOfDeletedSeasonsAsync(
        Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
        => await _context.GameSessions
            .Where(s => s.UserId == userId
                && s.GameCode == gameCode
                && s.IsImported
                && s.SeasonLinkId == seasonLinkId
                && s.SeasonId != null
                && !_context.Seasons.Any(season => season.Id == s.SeasonId))
            .ToListAsync(cancellationToken);

    public Task<bool> SessionKeyInUseAsync(Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
        => _context.GameSessions.AnyAsync(
            s => s.UserId == userId && s.GameCode == gameCode && s.SessionKey == sessionKey, cancellationToken);

    public async Task<IReadOnlyList<Lap>> GetLapsBySessionKeyAsync(
        Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
        => await _context.Laps
            .Where(l => l.UserId == userId && l.GameCode == gameCode && l.SessionKey == sessionKey)
            .ToListAsync(cancellationToken);
}
