using Microsoft.Extensions.DependencyInjection;
using SimCenter.Application.Auth;

namespace SimCenter.Application;

/// <summary>Application 계층 서비스 등록.</summary>
public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<IAuthService, AuthService>();
        return services;
    }
}
