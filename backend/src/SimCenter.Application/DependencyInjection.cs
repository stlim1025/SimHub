using Microsoft.Extensions.DependencyInjection;
using SimCenter.Application.AgentDevices;
using SimCenter.Application.Auth;
using SimCenter.Application.Laps;
using SimCenter.Application.Laps.Ingest;
using SimCenter.Application.Profile;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Commands;
using SimCenter.Application.Seasons.Import;
using SimCenter.Application.Seasons.Ingest;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Application.Setups;
using SimCenter.Application.Setups.Refresh;
using SimCenter.Application.Telemetry;
using SimCenter.Application.TrackOverviews;
using SimCenter.Application.TrackSamples;

namespace SimCenter.Application;

/// <summary>Application 계층 서비스 등록.</summary>
public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IProfileService, ProfileService>();
        services.AddScoped<ITelemetryIngestService, TelemetryIngestService>();
        services.AddScoped<LapDetailExtractor>();
        services.AddScoped<ISessionClassificationIngestor, SessionClassificationIngestor>();
        services.AddScoped<ITrackSamplesIngestor, TrackSamplesIngestor>();
        services.AddScoped<ITrackGeometryService, TrackGeometryService>();
        services.AddScoped<IFieldLapService, FieldLapService>();
        services.AddScoped<ISeasonQueryService, SeasonQueryService>();
        services.AddScoped<ISeasonImportService, SeasonImportService>();
        services.AddScoped<ISeasonCommandService, SeasonCommandService>();
        services.AddScoped<ISessionQueryService, SessionQueryService>();
        services.AddScoped<IRankingService, RankingService>();
        services.AddScoped<ILapQueryService, LapQueryService>();
        services.AddScoped<IAgentPairingService, AgentPairingService>();
        services.AddScoped<IAgentDeviceService, AgentDeviceService>();
        services.AddScoped<ICommunitySetupService, CommunitySetupService>();
        services.AddScoped<ICommunitySetupRefresher, CommunitySetupRefresher>();
        services.AddScoped<ITrackOverviewService, TrackOverviewService>();
        return services;
    }
}
