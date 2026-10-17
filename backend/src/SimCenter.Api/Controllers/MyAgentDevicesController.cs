using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using SimCenter.Api.Common;
using SimCenter.Api.RateLimiting;
using SimCenter.Application.AgentDevices;

namespace SimCenter.Api.Controllers;

/// <summary>내 Agent 장치 엔드포인트(11 §8): 연결 코드 발급, 장치 목록, 연결 해제. 기본 경로 /api/v1/me.</summary>
[ApiController]
[Route("api/v1/me")]
[Authorize]
public sealed class MyAgentDevicesController(
    IAgentPairingService pairingService,
    IAgentDeviceService deviceService) : ControllerBase
{
    /// <summary>연결 코드를 발급한다(10분 유효, 1회용). 이전 미사용 코드는 무효화된다. 사용자당 분당 10회.</summary>
    [HttpPost("agent-pairing-codes")]
    [EnableRateLimiting(RateLimitPolicies.PairingCodeIssue)]
    [ProducesResponseType(typeof(PairingCodeResponse), StatusCodes.Status201Created)]
    public async Task<ActionResult<PairingCodeResponse>> IssuePairingCode(CancellationToken cancellationToken)
    {
        var result = await pairingService.IssueCodeAsync(User.GetRequiredUserId(), cancellationToken);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    /// <summary>내 장치 목록(생성 시각 내림차순, 해제된 장치 제외).</summary>
    [HttpGet("agent-devices")]
    [ProducesResponseType(typeof(AgentDeviceListResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<AgentDeviceListResponse>> GetDevices(CancellationToken cancellationToken)
    {
        var result = await deviceService.GetMyDevicesAsync(User.GetRequiredUserId(), cancellationToken);
        return Ok(result);
    }

    /// <summary>장치 연결을 해제한다. 타인 장치는 403, 없는 장치는 404.</summary>
    [HttpDelete("agent-devices/{deviceId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> RevokeDevice(Guid deviceId, CancellationToken cancellationToken)
    {
        await deviceService.RevokeAsync(User.GetRequiredUserId(), deviceId, cancellationToken);
        return NoContent();
    }
}
