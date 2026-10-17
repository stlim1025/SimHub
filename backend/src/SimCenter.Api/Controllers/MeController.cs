using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Enums;

namespace SimCenter.Api.Controllers;

/// <summary>내 기록 엔드포인트(04-api-design §3.9). 기본 경로 /api/v1/me.</summary>
[ApiController]
[Route("api/v1/me")]
[Authorize]
public sealed class MeController(IRankingService rankingService) : ControllerBase
{
    /// <summary>내 랩 기록(무효 랩 포함, D-15/D-16). trackId 지정 시 개인 최고 동봉.</summary>
    [HttpGet("laps")]
    [ProducesResponseType(typeof(MyLapsResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<MyLapsResponse>> GetMyLaps(
        [FromQuery] Guid? trackId,
        [FromQuery] SessionType? sessionType,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        var result = await rankingService.GetMyLapsAsync(User.GetRequiredUserId(), trackId, sessionType, page, pageSize, cancellationToken);
        return Ok(result);
    }
}
