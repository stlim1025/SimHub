using Microsoft.Extensions.Logging;
using SimCenter.Application.Auth;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Profile;

/// <summary>
/// 내 프로필·설정 변경(14 §5). Domain·포트에만 의존한다(프레임워크 무의존). 로그에는 사용자 ID만 남긴다(이메일·비밀번호 미기록).
/// </summary>
public sealed class ProfileService : IProfileService
{
    public const string NewEmailField = "newEmail";
    public const string CurrentPasswordField = "currentPassword";

    private readonly IUserRepository _users;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IPasswordHasher _passwordHasher;
    private readonly IClock _clock;
    private readonly ILogger<ProfileService> _logger;

    public ProfileService(
        IUserRepository users,
        IUnitOfWork unitOfWork,
        IPasswordHasher passwordHasher,
        IClock clock,
        ILogger<ProfileService> logger)
    {
        _users = users;
        _unitOfWork = unitOfWork;
        _passwordHasher = passwordHasher;
        _clock = clock;
        _logger = logger;
    }

    public async Task<UserDto> UpdateProfileAsync(
        Guid userId, UpdateProfileRequest request, CancellationToken cancellationToken = default)
    {
        var profile = ProfileUpdateValidator.Validate(request);
        var user = await GetUserAsync(userId, cancellationToken);

        user.DisplayName = profile.DisplayName;
        user.ShowOnLeaderboard = profile.ShowOnLeaderboard;
        user.AvatarTeam = profile.AvatarTeam;
        user.PreferredGame = profile.PreferredGame;
        user.Controller = profile.Controller;
        user.Console = profile.Console;
        user.Units = profile.Units;
        user.TimeZoneId = profile.TimeZoneId;
        user.Theme = profile.Theme;
        user.UpdatedAt = _clock.UtcNow;

        await _unitOfWork.SaveChangesAsync(cancellationToken);
        _logger.LogInformation(
            "프로필 저장 userId={UserId} showOnLeaderboard={ShowOnLeaderboard}", userId, user.ShowOnLeaderboard);

        return UserDto.From(user);
    }

    public async Task<UserDto> ChangeEmailAsync(
        Guid userId, ChangeEmailRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var newEmail = UserInputRules.NormalizeEmail(request.NewEmail);
        UserInputRules.ValidateEmail(newEmail, NewEmailField);
        if (string.IsNullOrEmpty(request.CurrentPassword))
        {
            throw new ValidationException(CurrentPasswordField, "현재 비밀번호를 입력하세요.");
        }

        var user = await GetUserAsync(userId, cancellationToken);

        // 401이 아니라 400: 앱은 401을 "세션 만료"로 보고 로그아웃시킨다. 비밀번호를 잘못 친 것은 입력 오류다.
        if (!_passwordHasher.Verify(request.CurrentPassword, user.PasswordHash))
        {
            throw new ValidationException(CurrentPasswordField, "현재 비밀번호가 올바르지 않습니다.");
        }

        if (string.Equals(newEmail, user.Email, StringComparison.Ordinal))
        {
            return UserDto.From(user);
        }

        if (await _users.ExistsByEmailAsync(newEmail, cancellationToken))
        {
            throw new ConflictException(UserInputRules.EmailInUseMessage);
        }

        user.Email = newEmail;
        user.UpdatedAt = _clock.UtcNow;
        await _unitOfWork.SaveChangesAsync(cancellationToken);
        _logger.LogInformation("이메일 변경 userId={UserId}", userId);

        return UserDto.From(user);
    }

    private async Task<User> GetUserAsync(Guid userId, CancellationToken cancellationToken)
        => await _users.GetByIdAsync(userId, cancellationToken)
            ?? throw new NotFoundException("사용자를 찾을 수 없습니다.");
}
