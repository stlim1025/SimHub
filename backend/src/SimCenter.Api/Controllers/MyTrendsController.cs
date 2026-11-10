using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Trends;

namespace SimCenter.Api.Controllers;

/// <summary>내 성과 추세 엔드포인트. 기본 경로 /api/v1/me/trends. 오류는 ExceptionHandlingMiddleware가 RFC 7807로 바꾼다.</summary>
[ApiController]
[Route("api/v1/me/trends")]
[Authorize]
public sealed class MyTrendsController(ITrendsService trends) : ControllerBase
{
    /// <summary>
    /// 레이스마다 순위·AI 난이도·팀메이트 대비 페이스·필드 대비 페이스·꾸준함, 주말마다 예선, 주마다 달린 랩 수, 트랙마다 최고 랩 변화.
    /// gameCode(선택)가 있으면 그 게임만, 지원하지 않는 값이면 400.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(TrendsDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<TrendsDto>> GetMyTrends([FromQuery] string? gameCode, CancellationToken cancellationToken)
    {
        var result = await trends.GetAsync(User.GetRequiredUserId(), GameCodeQuery.ParseOptional(gameCode), cancellationToken);
        return Ok(result);
    }
}
