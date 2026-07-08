using Microsoft.Extensions.DependencyInjection;
using SimCenter.Application.Auth;
using SimCenter.Application.Rankings;
using SimCenter.Application.Sessions;
using SimCenter.Application.Telemetry;

namespace SimCenter.Application;

/// <summary>Application 계층 서비스 등록.</summary>
public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<ISessionService, SessionService>();
        services.AddScoped<ITelemetryIngestService, TelemetryIngestService>();
        services.AddScoped<IRankingService, RankingService>();
        return services;
    }
}
