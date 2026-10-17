using SimCenter.Application.Rankings;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 내 시즌 조회 유스케이스(12 §7.1). 남의 시즌·없는 시즌은 같은 <c>NotFoundException</c>(404, D-34)이다.
/// </summary>
public interface ISeasonQueryService
{
    /// <summary>시즌 목록 기본 페이지 크기.</summary>
    const int DefaultPageSize = 20;

    /// <summary>
    /// 시즌 목록 최대 페이지 크기. 목록 한 번에 그 시즌들의 결과 행을 읽어 순위를 계산하므로 작게 제한한다(12 §7.1).
    /// </summary>
    const int MaxPageSize = 20;

    /// <summary>
    /// 내 시즌 목록(<c>LastSessionAt</c> 내림차순 → Id 내림차순). 페이지 보정은 <c>RankingService.GetMyLapsAsync</c>와 같다
    /// (page &lt; 1 → 1, pageSize &lt; 1 → <see cref="DefaultPageSize"/>, 최대 초과 → <see cref="MaxPageSize"/>).
    /// </summary>
    Task<PagedResult<SeasonSummaryDto>> GetMySeasonsAsync(
        Guid userId, int page, int pageSize, CancellationToken cancellationToken = default);

    /// <summary>내 시즌 상세(헤더 + 라운드 + Standings).</summary>
    /// <exception cref="Common.Exceptions.NotFoundException">남의 시즌이거나 없는 시즌.</exception>
    Task<SeasonDetailDto> GetMySeasonAsync(
        Guid userId, Guid seasonId, CancellationToken cancellationToken = default);
}
