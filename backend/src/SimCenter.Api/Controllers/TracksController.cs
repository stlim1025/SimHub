using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Application.Rankings;

namespace SimCenter.Api.Controllers;

/// <summary>트랙 마스터 조회 엔드포인트(04-api-design §3.8). 기본 경로 /api/v1/tracks.</summary>
[ApiController]
[Route("api/v1/tracks")]
[Authorize]
public sealed class TracksController(IRankingService rankingService) : ControllerBase
{
    /// <summary>트랙 목록(마스터).</summary>
    [HttpGet]
    [ProducesResponseType(typeof(TrackListResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<TrackListResponse>> GetTracks(CancellationToken cancellationToken)
        => Ok(await rankingService.GetTracksAsync(cancellationToken));
}
