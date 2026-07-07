namespace SimCenter.Application.Auth;

/// <summary>회원가입 요청(04-api-design §3.1).</summary>
public sealed record RegisterRequest(string Email, string Password, string DisplayName);

/// <summary>회원가입 응답(201).</summary>
public sealed record RegisterResponse(Guid UserId, string DisplayName);

/// <summary>로그인 요청(04-api-design §3.2).</summary>
public sealed record LoginRequest(string Email, string Password);

/// <summary>로그인/프로필 공통 사용자 요약.</summary>
public sealed record UserDto(Guid UserId, string Email, string DisplayName);

/// <summary>로그인 응답(200). access token + 만료 + 사용자 요약.</summary>
public sealed record LoginResponse(string AccessToken, DateTime ExpiresAt, UserSummary User);

/// <summary>로그인 응답에 포함되는 사용자 요약(email 미포함).</summary>
public sealed record UserSummary(Guid UserId, string DisplayName);
