using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Rankings;
using SimCenter.Application.TrackOverviews;

namespace SimCenter.Api.Controllers;

/// <summary>트랙 마스터 조회 엔드포인트(04-api-design §3.8). 기본 경로 /api/v1/tracks.</summary>
[ApiController]
[Route("api/v1/tracks")]
[Authorize]
public sealed class TracksController(IRankingService rankingService, ITrackOverviewService overviewService) : ControllerBase
{
    /// <summary>트랙 목록(마스터). gameCode(선택) = F1_25|F1_26이면 그 게임만, 생략하면 전체. 그 밖의 값은 400.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(TrackListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<TrackListResponse>> GetTracks([FromQuery] string? gameCode, CancellationToken cancellationToken)
        => Ok(await rankingService.GetTracksAsync(GameCodeQuery.ParseOptional(gameCode), cancellationToken));

    /// <summary>트랙 개요: 트랙 정보(서킷·그랑프리·길이·랩 레코드), 내 통계, 전체 기간 Time Trial 상위 3, 내 최고 랩 10, 지도용 랩. 트랙이 없으면 404.</summary>
    [HttpGet("{trackId:guid}/overview")]
    [ProducesResponseType(typeof(TrackOverviewResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<TrackOverviewResponse>> GetOverview(Guid trackId, CancellationToken cancellationToken)
        => Ok(await overviewService.GetAsync(User.GetRequiredUserId(), trackId, cancellationToken));
}
