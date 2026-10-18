using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Auth;
using SimCenter.Application.Profile;

namespace SimCenter.Api.Controllers;

/// <summary>
/// 내 프로필·설정 변경(04 §3.3a·3.3b, 14 §5). 조회는 <c>GET /me</c>(<see cref="AuthController"/>).
/// 오류는 ExceptionHandlingMiddleware가 RFC 7807로 바꾼다(검증 400 · 이메일 중복 409).
/// </summary>
[ApiController]
[Route("api/v1/me")]
[Authorize]
public sealed class MyProfileController(IProfileService profileService) : ControllerBase
{
    /// <summary>표시 이름·랭킹 공개·프로필 사진·게임 환경·타임존·테마를 한 번에 저장한다(전체 교체).</summary>
    [HttpPut("profile")]
    [ProducesResponseType(typeof(UserDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<UserDto>> UpdateProfile(UpdateProfileRequest request, CancellationToken cancellationToken)
    {
        var result = await profileService.UpdateProfileAsync(User.GetRequiredUserId(), request, cancellationToken);
        return Ok(result);
    }

    /// <summary>현재 비밀번호를 확인하고 로그인 이메일을 바꾼다. 발급된 JWT의 email 클레임은 다음 로그인 때 갱신된다.</summary>
    [HttpPost("email")]
    [ProducesResponseType(typeof(UserDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<UserDto>> ChangeEmail(ChangeEmailRequest request, CancellationToken cancellationToken)
    {
        var result = await profileService.ChangeEmailAsync(User.GetRequiredUserId(), request, cancellationToken);
        return Ok(result);
    }
}
