using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Sessions;

namespace SimCenter.Api.Controllers;

/// <summary>체크인 세션 엔드포인트(04-api-design §3.4~3.6). 기본 경로 /api/v1/sessions.</summary>
[ApiController]
[Route("api/v1/sessions")]
[Authorize]
public sealed class SessionsController(ISessionService sessionService) : ControllerBase
{
    /// <summary>SimRig 체크인 → DrivingSession 생성(D-2 랩 귀속 시작점).</summary>
    [HttpPost("check-in")]
    [ProducesResponseType(typeof(SessionDto), StatusCodes.Status201Created)]
    public async Task<IActionResult> CheckIn(CheckInRequest request, CancellationToken cancellationToken)
    {
        var result = await sessionService.CheckInAsync(GetUserId(), request, cancellationToken);
        return CreatedAtAction(nameof(GetActive), null, result);
    }

    /// <summary>세션 종료(본인만).</summary>
    [HttpPost("{id:guid}/check-out")]
    [ProducesResponseType(typeof(CheckOutResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<CheckOutResponse>> CheckOut(Guid id, CancellationToken cancellationToken)
    {
        var result = await sessionService.CheckOutAsync(GetUserId(), id, cancellationToken);
        return Ok(result);
    }

    /// <summary>내 활성 세션(없으면 null).</summary>
    [HttpGet("active")]
    [ProducesResponseType(typeof(SessionDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<SessionDto?>> GetActive(CancellationToken cancellationToken)
    {
        var result = await sessionService.GetActiveAsync(GetUserId(), cancellationToken);
        return Ok(result);
    }

    /// <summary>인증 주체(sub 클레임)에서 사용자 ID를 추출한다.</summary>
    private Guid GetUserId()
    {
        var value = User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? User.FindFirstValue("sub");

        if (!Guid.TryParse(value, out var userId))
        {
            throw new AuthenticationException("유효하지 않은 토큰입니다.");
        }

        return userId;
    }
}
