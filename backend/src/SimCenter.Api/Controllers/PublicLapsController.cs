using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Laps;

namespace SimCenter.Api.Controllers;

/// <summary>
/// 공유 링크로 보는 랩(로그인 없음). 기본 경로 /api/v1/public/laps. 읽기 전용.
/// 지우지 않은 랩이면 주인과 관계없이 보인다(랩 ID = UUID v7, 링크를 받은 사람만 안다).
/// 주인 이름은 랭킹과 같은 공개 규칙(D-39)이고, 이메일·사용자 ID·장치 정보는 내보내지 않는다. 없는 랩은 404.
/// </summary>
[ApiController]
[Route("api/v1/public/laps")]
[AllowAnonymous]
public sealed class PublicLapsController(ILapQueryService lapQueryService) : ControllerBase
{
    /// <summary>
    /// 공유 랩 상세(랩 + 트랙 국가 + 주인 이름 + 스냅샷 + 어시스트). 세션 연결은 없다.
    /// <paramref name="compareLapId"/>를 주면 같은 트랙·게임의 그 랩을 비교 대상(<c>comparison</c>)으로 싣는다 — 맞지 않으면 무시한다.
    /// </summary>
    [HttpGet("{lapId:guid}")]
    [ProducesResponseType(typeof(PublicLapDetailResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PublicLapDetailResponse>> GetPublicLap(
        Guid lapId, [FromQuery] Guid? compareLapId, CancellationToken cancellationToken)
        => Ok(await lapQueryService.GetPublicLapAsync(lapId, compareLapId, cancellationToken));

    /// <summary>공유 랩 텔레메트리 트레이스(D-45 모양 그대로). 트레이스가 없거나 없는 랩이면 404.</summary>
    [HttpGet("{lapId:guid}/trace")]
    [PrivateCache(PrivateCacheAttribute.LapTraceSeconds)]
    [ProducesResponseType(typeof(LapTraceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<LapTraceResponse>> GetPublicLapTrace(Guid lapId, CancellationToken cancellationToken)
        => Ok(await lapQueryService.GetPublicLapTraceAsync(lapId, cancellationToken));
}
