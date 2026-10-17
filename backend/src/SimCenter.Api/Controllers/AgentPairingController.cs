using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using SimCenter.Api.RateLimiting;
using SimCenter.Application.AgentDevices;

namespace SimCenter.Api.Controllers;

/// <summary>
/// Agent 연결 엔드포인트(11 §4.3). 기본 경로 /api/v1/agent. Agent는 아직 계정 자격이 없으므로 익명이며,
/// 코드 추측을 막기 위해 IP당 분당 10회로 제한한다(초과 시 429).
/// </summary>
[ApiController]
[Route("api/v1/agent")]
[AllowAnonymous]
[EnableRateLimiting(RateLimitPolicies.AgentPair)]
public sealed class AgentPairingController(IAgentPairingService pairingService) : ControllerBase
{
    /// <summary>연결 코드를 소비하고 장치를 만든다. 장치 키 원문은 이 응답에서 한 번만 내려간다.</summary>
    [HttpPost("pair")]
    [ProducesResponseType(typeof(PairResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<PairResponse>> Pair(PairRequest request, CancellationToken cancellationToken)
    {
        var result = await pairingService.PairAsync(request, cancellationToken);
        return Ok(result);
    }
}
