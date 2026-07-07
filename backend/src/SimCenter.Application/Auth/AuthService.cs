using System.Net.Mail;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Auth;

/// <summary>
/// 인증 유스케이스 구현. Domain·포트(Interface)에만 의존하며 프레임워크 무의존이라
/// Fake 주입으로 결정론적 단위 테스트가 가능하다.
/// </summary>
public sealed class AuthService : IAuthService
{
    private const int MinPasswordLength = 8;
    private const int MaxDisplayNameLength = 50;

    private readonly IUserRepository _users;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IPasswordHasher _passwordHasher;
    private readonly IJwtTokenGenerator _tokenGenerator;
    private readonly IIdGenerator _idGenerator;
    private readonly IClock _clock;

    public AuthService(
        IUserRepository users,
        IUnitOfWork unitOfWork,
        IPasswordHasher passwordHasher,
        IJwtTokenGenerator tokenGenerator,
        IIdGenerator idGenerator,
        IClock clock)
    {
        _users = users;
        _unitOfWork = unitOfWork;
        _passwordHasher = passwordHasher;
        _tokenGenerator = tokenGenerator;
        _idGenerator = idGenerator;
        _clock = clock;
    }

    public async Task<RegisterResponse> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken = default)
    {
        var email = NormalizeEmail(request.Email);
        ValidateEmail(email);
        ValidatePassword(request.Password);
        var displayName = ValidateDisplayName(request.DisplayName);

        if (await _users.ExistsByEmailAsync(email, cancellationToken))
        {
            throw new ConflictException("이미 사용 중인 이메일입니다.");
        }

        var now = _clock.UtcNow;
        var user = new User
        {
            Id = _idGenerator.NewId(),
            Email = email,
            PasswordHash = _passwordHasher.Hash(request.Password),
            DisplayName = displayName,
            CreatedAt = now,
        };

        await _users.AddAsync(user, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return new RegisterResponse(user.Id, user.DisplayName);
    }

    public async Task<LoginResponse> LoginAsync(LoginRequest request, CancellationToken cancellationToken = default)
    {
        var email = NormalizeEmail(request.Email);
        var user = await _users.GetByEmailAsync(email, cancellationToken);

        // 사용자 부재/비밀번호 불일치를 동일 메시지로 처리해 계정 존재 여부 노출을 막는다.
        if (user is null || !_passwordHasher.Verify(request.Password, user.PasswordHash))
        {
            throw new AuthenticationException("이메일 또는 비밀번호가 올바르지 않습니다.");
        }

        var (token, expiresAt) = _tokenGenerator.Generate(user);
        return new LoginResponse(token, expiresAt, new UserSummary(user.Id, user.DisplayName));
    }

    public async Task<UserDto> GetMeAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        var user = await _users.GetByIdAsync(userId, cancellationToken)
            ?? throw new NotFoundException("사용자를 찾을 수 없습니다.");

        return new UserDto(user.Id, user.Email, user.DisplayName);
    }

    private static string NormalizeEmail(string email) => (email ?? string.Empty).Trim().ToLowerInvariant();

    private static void ValidateEmail(string email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            throw new ValidationException("email", "이메일은 필수입니다.");
        }

        if (email.Length > 256 || !MailAddress.TryCreate(email, out _))
        {
            throw new ValidationException("email", "이메일 형식이 올바르지 않습니다.");
        }
    }

    private static void ValidatePassword(string password)
    {
        if (string.IsNullOrEmpty(password) || password.Length < MinPasswordLength)
        {
            throw new ValidationException("password", $"비밀번호는 최소 {MinPasswordLength}자 이상이어야 합니다.");
        }
    }

    private static string ValidateDisplayName(string displayName)
    {
        var trimmed = (displayName ?? string.Empty).Trim();
        if (trimmed.Length is < 1 or > MaxDisplayNameLength)
        {
            throw new ValidationException("displayName", $"표시 이름은 1~{MaxDisplayNameLength}자여야 합니다.");
        }

        return trimmed;
    }
}
