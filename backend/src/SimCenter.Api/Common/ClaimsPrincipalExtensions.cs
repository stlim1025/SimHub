using System.Security.Claims;
using SimCenter.Application.Common.Exceptions;

namespace SimCenter.Api.Common;

/// <summary>인증 주체(JWT)에서 사용자 식별자를 꺼내는 확장 메서드. 컨트롤러·요청 제한이 같은 규칙을 쓴다.</summary>
public static class ClaimsPrincipalExtensions
{
    private const string SubjectClaimType = "sub";

    /// <summary>
    /// 사용자 ID 클레임의 원문 값. <c>sub</c>를 먼저 보고, JWT 인바운드 클레임 매핑으로 바뀐
    /// <see cref="ClaimTypes.NameIdentifier"/>를 대체로 쓴다. 없으면 null.
    /// </summary>
    public static string? FindUserIdClaim(this ClaimsPrincipal user)
    {
        ArgumentNullException.ThrowIfNull(user);
        return user.FindFirstValue(SubjectClaimType) ?? user.FindFirstValue(ClaimTypes.NameIdentifier);
    }

    /// <summary>인증 주체의 사용자 ID. 클레임이 없거나 Guid가 아니면 <see cref="AuthenticationException"/>(401).</summary>
    public static Guid GetRequiredUserId(this ClaimsPrincipal user)
    {
        if (!Guid.TryParse(user.FindUserIdClaim(), out var userId))
        {
            throw new AuthenticationException("유효하지 않은 토큰입니다.");
        }

        return userId;
    }
}
