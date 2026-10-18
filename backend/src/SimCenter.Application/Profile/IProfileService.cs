using SimCenter.Application.Auth;

namespace SimCenter.Application.Profile;

/// <summary>내 프로필·설정 변경 유스케이스(14 §5). 조회(<c>GET /me</c>)는 <see cref="IAuthService.GetMeAsync"/>가 맡는다.</summary>
public interface IProfileService
{
    /// <summary>표시 이름·공개 여부·프로필 사진·게임 환경·타임존·테마를 한 번에 저장한다. 틀린 값은 필드별 400.</summary>
    Task<UserDto> UpdateProfileAsync(Guid userId, UpdateProfileRequest request, CancellationToken cancellationToken = default);

    /// <summary>현재 비밀번호를 확인하고 이메일을 바꾼다. 비밀번호 불일치 = 400(<c>currentPassword</c>), 중복 = 409.</summary>
    Task<UserDto> ChangeEmailAsync(Guid userId, ChangeEmailRequest request, CancellationToken cancellationToken = default);
}
