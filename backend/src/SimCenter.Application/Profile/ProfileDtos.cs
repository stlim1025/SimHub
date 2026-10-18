namespace SimCenter.Application.Profile;

/// <summary>
/// 프로필·설정 저장 요청(<c>PUT /me/profile</c>, 14 §5). 전체 교체 — 모든 필드가 필요하다(<see cref="AvatarTeam"/>만 null 허용 = 사진 없음).
/// 빠진 필드가 기본값으로 조용히 바뀌지 않도록 전부 nullable로 받아 서비스가 필수 여부를 검증한다.
/// enum 필드는 이름 문자열(대소문자 무시)이며 모르는 값은 400이다.
/// </summary>
public sealed record UpdateProfileRequest(
    string? DisplayName,
    bool? ShowOnLeaderboard,
    string? AvatarTeam,
    string? PreferredGame,
    string? Controller,
    string? Console,
    string? Units,
    string? TimeZoneId,
    string? Theme);

/// <summary>이메일 변경 요청(<c>POST /me/email</c>, 14 §5). 현재 비밀번호로 본인을 다시 확인한다.</summary>
public sealed record ChangeEmailRequest(string? NewEmail, string? CurrentPassword);
