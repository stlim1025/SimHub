using SimCenter.Domain.Entities;

namespace SimCenter.Application.Auth;

/// <summary>회원가입 요청(04-api-design §3.1).</summary>
public sealed record RegisterRequest(string Email, string Password, string DisplayName);

/// <summary>회원가입 응답(201).</summary>
public sealed record RegisterResponse(Guid UserId, string DisplayName);

/// <summary>로그인 요청(04-api-design §3.2).</summary>
public sealed record LoginRequest(string Email, string Password);

/// <summary>
/// 내 프로필(04 §3.3). <c>GET /me</c>·<c>PUT /me/profile</c>·<c>POST /me/email</c>가 같은 형태를 돌려준다(14 §5).
/// enum 값은 이름 문자열이다(<c>Gamepad</c>·<c>Wheel</c> 등).
/// </summary>
public sealed record UserDto(
    Guid UserId,
    string Email,
    string DisplayName,
    bool ShowOnLeaderboard,
    string? AvatarTeam,
    string PreferredGame,
    string Controller,
    string Console,
    string Units,
    string TimeZoneId,
    string Theme)
{
    public static UserDto From(User user) => new(
        user.Id,
        user.Email,
        user.DisplayName,
        user.ShowOnLeaderboard,
        user.AvatarTeam,
        user.PreferredGame,
        user.Controller.ToString(),
        user.Console.ToString(),
        user.Units.ToString(),
        user.TimeZoneId,
        user.Theme.ToString());
}

/// <summary>로그인 응답(200). access token + 만료 + 사용자 요약.</summary>
public sealed record LoginResponse(string AccessToken, DateTime ExpiresAt, UserSummary User);

/// <summary>로그인 응답에 포함되는 사용자 요약(email·설정 미포함 — 앱은 로그인 뒤 <c>GET /me</c>로 프로필을 받는다).</summary>
public sealed record UserSummary(Guid UserId, string DisplayName);
