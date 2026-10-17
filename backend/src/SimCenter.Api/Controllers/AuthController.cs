using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Auth;

namespace SimCenter.Api.Controllers;

/// <summary>인증/프로필 엔드포인트(04-api-design §3.1~3.3). 기본 경로 /api/v1.</summary>
[ApiController]
[Route("api/v1")]
public sealed class AuthController(IAuthService authService) : ControllerBase
{
    /// <summary>회원가입(self-signup, D-11).</summary>
    [AllowAnonymous]
    [HttpPost("auth/register")]
    [ProducesResponseType(typeof(RegisterResponse), StatusCodes.Status201Created)]
    public async Task<IActionResult> Register(RegisterRequest request, CancellationToken cancellationToken)
    {
        var result = await authService.RegisterAsync(request, cancellationToken);
        return CreatedAtAction(nameof(GetMe), null, result);
    }

    /// <summary>로그인 → JWT 발급.</summary>
    [AllowAnonymous]
    [HttpPost("auth/login")]
    [ProducesResponseType(typeof(LoginResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<LoginResponse>> Login(LoginRequest request, CancellationToken cancellationToken)
    {
        var result = await authService.LoginAsync(request, cancellationToken);
        return Ok(result);
    }

    /// <summary>내 프로필.</summary>
    [Authorize]
    [HttpGet("me")]
    [ProducesResponseType(typeof(UserDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<UserDto>> GetMe(CancellationToken cancellationToken)
    {
        var result = await authService.GetMeAsync(User.GetRequiredUserId(), cancellationToken);
        return Ok(result);
    }
}
