using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 게임 세션 조회 포트(P7, 12 §7). 읽기 전용 — 모두 no tracking이다.
/// 인입용 <see cref="IGameSessionRepository"/>(tracked, 쓰기 경로)와 분리한다.
/// </summary>
public interface IGameSessionQueryRepository
{
    /// <summary>
    /// 내 세션 페이지(삭제 제외). <paramref name="sessionType"/>이 있으면 그 유형만.
    /// 정렬: <c>ClassifiedAt</c> 내림차순 → Id 내림차순. 총 개수 함께 반환.
    /// </summary>
    Task<(IReadOnlyList<SessionSummaryRow> Items, int Total)> GetMyPageAsync(
        Guid userId, SessionType? sessionType, int skip, int take, CancellationToken cancellationToken = default);

    /// <summary>
    /// 내 세션 1건과 <see cref="GameSession.Track"/>·활성 <see cref="GameSession.Results"/>·활성 스틴트. 남의 것·없는 것은 null.
    /// </summary>
    Task<GameSession?> GetMineDetailAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default);

    /// <summary>
    /// 같은 세션 키(<c>Lap.SessionKey</c>, D-29)의 내 세션 ID(랩 상세의 "세션 보기", 15 §4.2). 없으면 null.
    /// </summary>
    Task<Guid?> FindMySessionIdAsync(
        Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default);
}
