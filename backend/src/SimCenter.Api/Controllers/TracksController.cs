using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Rankings;
using SimCenter.Application.TrackOverviews;
using SimCenter.Application.TrackSamples;
using SimCenter.Domain.Constants;

namespace SimCenter.Api.Controllers;

/// <summary>트랙 마스터 조회 엔드포인트(04-api-design §3.8). 기본 경로 /api/v1/tracks.</summary>
[ApiController]
[Route("api/v1/tracks")]
[Authorize]
public sealed class TracksController(
    IRankingService rankingService,
    ITrackOverviewService overviewService,
    ITrackGeometryService geometryService) : ControllerBase
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

    /// <summary>
    /// 트랙 형상: 모든 오프라인 세션의 전체 차 표본으로 랩 거리 5m마다 레이싱 라인·높이·차들이 달린 폭·연석 쪽.
    /// 개인 정보가 없는 모음이라 로그인 없이(공유 랩)도 본다. gameCode 생략 = F1_25. 표본이 없으면 404.
    /// </summary>
    [AllowAnonymous]
    [HttpGet("{trackId:guid}/geometry")]
    [ProducesResponseType(typeof(TrackGeometryResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<TrackGeometryResponse>> GetGeometry(
        Guid trackId, [FromQuery] string? gameCode, CancellationToken cancellationToken)
        => Ok(await geometryService.GetAsync(trackId, GameCodeQuery.ParseOptional(gameCode) ?? GameCodes.F1_25, cancellationToken));
}
