using SimCenter.Application.Rankings;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 내 세션 조회 유스케이스(12 §7.1). 남의 세션·없는 세션은 같은 <c>NotFoundException</c>(404, D-34)이다.
/// </summary>
public interface ISessionQueryService
{
    /// <summary>세션 목록 기본 페이지 크기.</summary>
    const int DefaultPageSize = 20;

    /// <summary>세션 목록 최대 페이지 크기.</summary>
    const int MaxPageSize = 100;

    /// <summary>
    /// 내 세션 목록(<c>ClassifiedAt</c> 내림차순 → Id 내림차순). <paramref name="sessionType"/>이 있으면 그 유형만.
    /// 페이지 보정은 <c>RankingService.GetMyLapsAsync</c>와 같다. <paramref name="gameCode"/>가 있으면 그 게임의 세션만.
    /// </summary>
    Task<PagedResult<SessionSummaryDto>> GetMySessionsAsync(
        Guid userId, SessionType? sessionType, int page, int pageSize, string? gameCode = null,
        CancellationToken cancellationToken = default);

    /// <summary>내 세션 상세(헤더 + 결과).</summary>
    /// <exception cref="Common.Exceptions.NotFoundException">남의 세션이거나 없는 세션.</exception>
    Task<SessionDetailDto> GetMySessionAsync(
        Guid userId, Guid sessionId, CancellationToken cancellationToken = default);
}
