using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Infrastructure.Common;
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
        services.AddScoped<IUserRepository, UserRepository>();
        services.AddScoped<DbSeeder>();

        // ── 어댑터 ──
        services.AddSingleton<IClock, SystemClock>();
        services.AddSingleton<IIdGenerator, UuidV7Generator>();
        services.AddSingleton<IPasswordHasher, BCryptPasswordHasher>();
        services.AddScoped<IJwtTokenGenerator, JwtTokenGenerator>();

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
            });

        services.AddAuthorization();

        return services;
    }
}
