using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Laps;

namespace SimCenter.Api.Controllers;

/// <summary>
/// 비교 랩 읽기(docs/15 §10, D-51). 기본 경로 /api/v1/laps. 로그인 필수.
/// 공개 규칙: 내 랩이거나 남의 <b>랭킹 적격</b> 랩(리더보드에 이미 공개된 기록)만. 남의 비공개 랩은 없는 랩과 같은 404다(D-34).
/// </summary>
[ApiController]
[Route("api/v1/laps")]
[Authorize]
public sealed class LapsController(ILapQueryService lapQueryService) : ControllerBase
{
    /// <summary>비교 랩 트레이스(D-45 모양 그대로). 트레이스가 없거나 비교할 수 없는 랩이면 404.</summary>
    [HttpGet("{lapId:guid}/trace")]
    [PrivateCache(PrivateCacheAttribute.LapTraceSeconds)]
    [ProducesResponseType(typeof(LapTraceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<LapTraceResponse>> GetComparableLapTrace(Guid lapId, CancellationToken cancellationToken)
        => Ok(await lapQueryService.GetComparableLapTraceAsync(User.GetRequiredUserId(), lapId, cancellationToken));
}
