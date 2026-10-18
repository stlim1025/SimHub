using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Enums;

namespace SimCenter.Api.Controllers;

/// <summary>
/// 내 기록 엔드포인트(04-api-design §3.9, 15 §4.2). 기본 경로 /api/v1/me.
/// 남의 랩·없는 랩은 같은 404다(D-34). lapId가 GUID가 아니면 라우트가 맞지 않아 404다.
/// </summary>
[ApiController]
[Route("api/v1/me")]
[Authorize]
public sealed class MeController(IRankingService rankingService, ILapQueryService lapQueryService) : ControllerBase
{
    /// <summary>
    /// 내 랩 기록(무효 랩 포함, D-15/D-16). trackId 지정 시 개인 최고 동봉. sort=recent(기본)|fastest.
    /// validOnly=true면 유효 랩만(기본 false).
    /// </summary>
    [HttpGet("laps")]
    [ProducesResponseType(typeof(MyLapsResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<MyLapsResponse>> GetMyLaps(
        [FromQuery] Guid? trackId,
        [FromQuery] SessionType? sessionType,
        [FromQuery] MyLapsSort sort = MyLapsSort.Recent,
        [FromQuery] bool validOnly = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        var result = await rankingService.GetMyLapsAsync(
            User.GetRequiredUserId(), trackId, sessionType, validOnly, sort, page, pageSize, cancellationToken);
        return Ok(result);
    }

    /// <summary>
    /// 내 랩 상세(스냅샷·어시스트·비교 대상·세션 연결, D-46·D-51). 남의 랩이거나 없으면 404.
    /// compare=best(기본)|leaderboard|lap|none, compare=lap이면 compareLapId 필수.
    /// sameTeam·sameSessionType·sameAssists = best·leaderboard를 고를 때만 쓰는 필터(기본 false).
    /// </summary>
    [HttpGet("laps/{lapId:guid}")]
    [ProducesResponseType(typeof(LapDetailResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<LapDetailResponse>> GetMyLap(
        Guid lapId,
        [FromQuery] LapComparisonKind compare = LapComparisonKind.Best,
        [FromQuery] Guid? compareLapId = null,
        [FromQuery] bool sameTeam = false,
        [FromQuery] bool sameSessionType = false,
        [FromQuery] bool sameAssists = false,
        CancellationToken cancellationToken = default)
    {
        var comparison = new LapComparisonRequest(compare, compareLapId, sameTeam, sameSessionType, sameAssists);
        return Ok(await lapQueryService.GetMyLapAsync(User.GetRequiredUserId(), lapId, comparison, cancellationToken));
    }

    /// <summary>내 랩 텔레메트리 트레이스(D-45). 트레이스가 없거나 남의 랩이면 404.</summary>
    [HttpGet("laps/{lapId:guid}/trace")]
    [ProducesResponseType(typeof(LapTraceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<LapTraceResponse>> GetMyLapTrace(Guid lapId, CancellationToken cancellationToken)
        => Ok(await lapQueryService.GetMyLapTraceAsync(User.GetRequiredUserId(), lapId, cancellationToken));

    /// <summary>내 트랙별 요약(랩 수·유효 랩 최고·마지막 세운 시각). 마지막으로 랩을 세운 트랙 우선.</summary>
    [HttpGet("tracks")]
    [ProducesResponseType(typeof(MyTracksResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<MyTracksResponse>> GetMyTracks(CancellationToken cancellationToken = default)
    {
        var result = await rankingService.GetMyTracksAsync(User.GetRequiredUserId(), cancellationToken);
        return Ok(result);
    }
}
