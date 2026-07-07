namespace SimCenter.Application.Auth;

/// <summary>인증 유스케이스(얇은 Service, D-3 — MediatR 미도입).</summary>
public interface IAuthService
{
    Task<RegisterResponse> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken = default);

    Task<LoginResponse> LoginAsync(LoginRequest request, CancellationToken cancellationToken = default);

    Task<UserDto> GetMeAsync(Guid userId, CancellationToken cancellationToken = default);
}
