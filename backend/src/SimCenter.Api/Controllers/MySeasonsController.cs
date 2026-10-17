using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Queries;

namespace SimCenter.Api.Controllers;

/// <summary>
/// 내 시즌 조회 엔드포인트(12 §7.1). 기본 경로 /api/v1/me/seasons.
/// 남의 시즌·없는 시즌은 같은 404다(D-34). Id가 GUID가 아니면 라우트가 맞지 않아 404다.
/// </summary>
[ApiController]
[Route("api/v1/me/seasons")]
[Authorize]
public sealed class MySeasonsController(ISeasonQueryService seasonService) : ControllerBase
{
    /// <summary>내 시즌 목록(마지막 세션 시각 내림차순). pageSize 기본 20, 최대 20.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResult<SeasonSummaryDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PagedResult<SeasonSummaryDto>>> GetMySeasons(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = ISeasonQueryService.DefaultPageSize,
        CancellationToken cancellationToken = default)
    {
        var result = await seasonService.GetMySeasonsAsync(User.GetRequiredUserId(), page, pageSize, cancellationToken);
        return Ok(result);
    }

    /// <summary>내 시즌 상세(헤더 + 라운드 + Standings). 남의 시즌이거나 없으면 404.</summary>
    [HttpGet("{seasonId:guid}")]
    [ProducesResponseType(typeof(SeasonDetailDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<SeasonDetailDto>> GetMySeason(Guid seasonId, CancellationToken cancellationToken)
    {
        var result = await seasonService.GetMySeasonAsync(User.GetRequiredUserId(), seasonId, cancellationToken);
        return Ok(result);
    }
}
