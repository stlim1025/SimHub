using System.Text;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Infrastructure.Common;
using SimCenter.Infrastructure.Configuration;
using SimCenter.Infrastructure.Identity;
using SimCenter.Infrastructure.Persistence;
using SimCenter.Infrastructure.Persistence.Repositories;
using SimCenter.Infrastructure.Persistence.Seed;
using SimCenter.Infrastructure.Time;

namespace SimCenter.Infrastructure;

/// <summary>Infrastructure 계층 서비스 등록(EF Core, 인증, 어댑터).</summary>
public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        // ── 영속성(PostgreSQL, snake_case) ──
        var connectionString = configuration.GetConnectionString("Postgres")
            ?? throw new InvalidOperationException("연결 문자열 'ConnectionStrings:Postgres'가 설정되지 않았습니다.");

        services.AddDbContext<AppDbContext>(options =>
            options.UseNpgsql(connectionString).UseSnakeCaseNamingConvention());

        services.AddScoped<IUnitOfWork>(sp => sp.GetRequiredService<AppDbContext>());
        services.AddScoped<ITransactionRunner>(sp => sp.GetRequiredService<AppDbContext>());
        services.AddScoped<IUserRepository, UserRepository>();
        services.AddScoped<ITrackRepository, TrackRepository>();
        services.AddScoped<ILapRepository, LapRepository>();
        services.AddScoped<ILapQueryRepository, LapQueryRepository>();
        services.AddScoped<IProcessedEventRepository, ProcessedEventRepository>();
        services.AddScoped<IAgentDeviceRepository, AgentDeviceRepository>();
        services.AddScoped<IAgentPairingCodeRepository, AgentPairingCodeRepository>();
        services.AddScoped<ISeasonRepository, SeasonRepository>();
        services.AddScoped<IGameSessionRepository, GameSessionRepository>();
        services.AddScoped<ISeasonQueryRepository, SeasonQueryRepository>();
        services.AddScoped<IGameSessionQueryRepository, GameSessionQueryRepository>();
        services.AddScoped<ISessionDetailQueryRepository, SessionDetailQueryRepository>();
        services.AddScoped<DbSeeder>();

        // ── 어댑터 ──
        services.AddSingleton<IClock, Time.SystemClock>();
        services.AddSingleton<IIdGenerator, UuidV7Generator>();
        services.AddSingleton<IPasswordHasher, BCryptPasswordHasher>();
        services.AddSingleton<IApiKeyHasher, Sha256ApiKeyHasher>();
        services.AddSingleton<IRandomSource, CryptoRandomSource>();
        services.AddScoped<IJwtTokenGenerator, JwtTokenGenerator>();

        // ── 랭킹 설정(기간 경계 타임존, D-27) ──
        services.AddOptions<RankingOptions>()
            .Bind(configuration.GetSection(RankingOptions.SectionName))
            .Validate(
                o => !string.IsNullOrWhiteSpace(o.TimeZoneId) && TimeZoneInfo.TryFindSystemTimeZoneById(o.TimeZoneId, out _),
                "Ranking:TimeZoneId가 유효한 IANA 타임존이 아닙니다.")
            .ValidateOnStart();
        services.AddSingleton<IRankingTimeZoneProvider, ConfiguredRankingTimeZoneProvider>();

        // ── 인증(JWT Bearer) ──
        services.AddOptions<JwtOptions>()
            .Bind(configuration.GetSection(JwtOptions.SectionName))
            .Validate(o => !string.IsNullOrWhiteSpace(o.Key), "Jwt:Key가 설정되지 않았습니다.")
            .ValidateOnStart();

        var jwt = configuration.GetSection(JwtOptions.SectionName).Get<JwtOptions>() ?? new JwtOptions();

        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidateAudience = true,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    ValidIssuer = jwt.Issuer,
                    ValidAudience = jwt.Audience,
                    IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Key)),
                    ClockSkew = TimeSpan.FromSeconds(30),
                };

                // WebSocket은 Authorization 헤더를 실을 수 없으므로 RankingHub 경로에 한해 쿼리 access_token을 토큰으로 채택한다
                // (SignalR+JWT 표준). REST는 계속 헤더만 허용 → 쿼리 토큰 로그 유출면을 Hub로 한정.
                options.Events = new JwtBearerEvents
                {
                    OnMessageReceived = context =>
                    {
                        var accessToken = context.Request.Query["access_token"].ToString();
                        if (!string.IsNullOrEmpty(accessToken)
                            && context.HttpContext.Request.Path.StartsWithSegments("/hubs/ranking"))
                        {
                            context.Token = accessToken;
                        }

                        return Task.CompletedTask;
                    },
                };
            })
            // Agent(TelemetryHub) 전용 장치 키 스킴(D-26). 사용자 JWT와 분리.
            .AddScheme<AuthenticationSchemeOptions, AgentApiKeyAuthenticationHandler>(
                AgentApiKeyDefaults.Scheme, _ => { });

        services.AddAuthorization();

        return services;
    }
}
