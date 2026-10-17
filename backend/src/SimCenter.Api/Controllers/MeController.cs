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
    /// <summary>내 랩 기록(무효 랩 포함, D-15/D-16). trackId 지정 시 개인 최고 동봉. sort=recent(기본)|fastest.</summary>
    [HttpGet("laps")]
    [ProducesResponseType(typeof(MyLapsResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<MyLapsResponse>> GetMyLaps(
        [FromQuery] Guid? trackId,
        [FromQuery] SessionType? sessionType,
        [FromQuery] MyLapsSort sort = MyLapsSort.Recent,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        var result = await rankingService.GetMyLapsAsync(
            User.GetRequiredUserId(), trackId, sessionType, sort, page, pageSize, cancellationToken);
        return Ok(result);
    }

    /// <summary>내 트랙별 요약(랩 수·유효 랩 최고·마지막 세운 시각). 마지막으로 랩을 세운 트랙 우선.</summary>
    [HttpGet("tracks")]
    [ProducesResponseType(typeof(MyTracksResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<MyTracksResponse>> GetMyTracks(CancellationToken cancellationToken = default)
    {
        var result = await rankingService.GetMyTracksAsync(User.GetRequiredUserId(), cancellationToken);
        return Ok(result);
    }
}
