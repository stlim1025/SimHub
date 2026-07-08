using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using Serilog;
using SimCenter.Api.Hubs;
using SimCenter.Api.Middleware;
using SimCenter.Api.Notifications;
using SimCenter.Application;
using SimCenter.Application.Rankings.Notifications;
using SimCenter.Infrastructure;
using SimCenter.Infrastructure.Persistence;
using SimCenter.Infrastructure.Persistence.Seed;

var builder = WebApplication.CreateBuilder(args);

// ── Serilog(헌장: Logging 필수) ──
builder.Host.UseSerilog((context, config) =>
    config.ReadFrom.Configuration(context.Configuration)
        .Enrich.FromLogContext()
        .WriteTo.Console());

// ── 계층 서비스 등록 ──
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

// 실시간 브로드캐스트 포트(Application) → SignalR 구현(Api). 의존 방향 Api → Application 유지.
builder.Services.AddScoped<IRankingNotifier, RankingNotifier>();

builder.Services.AddControllers();

// ── SignalR(실시간 인입, 05-signalr-design). JSON은 camelCase + enum 문자열로 계약 고정. ──
builder.Services.AddSignalR()
    .AddJsonProtocol(options =>
    {
        options.PayloadSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
        options.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
        options.PayloadSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    });

// ── Swagger(JWT Bearer 지원) ──
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo { Title = "SimCenter API", Version = "v1" });

    var scheme = new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "JWT access token. 'Bearer' 접두사 없이 토큰만 입력하세요.",
        Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" },
    };
    options.AddSecurityDefinition("Bearer", scheme);
    options.AddSecurityRequirement(new OpenApiSecurityRequirement { [scheme] = Array.Empty<string>() });
});

var app = builder.Build();

// 개발 환경: 마이그레이션 적용 + 시드.
if (app.Environment.IsDevelopment())
{
    await MigrateAndSeedAsync(app);
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseSerilogRequestLogging();

app.UseHttpsRedirection();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapHub<TelemetryHub>("/hubs/telemetry");
app.MapHub<RankingHub>("/hubs/ranking");

app.Run();

static async Task MigrateAndSeedAsync(WebApplication app)
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();

    var seeder = scope.ServiceProvider.GetRequiredService<DbSeeder>();
    await seeder.SeedAsync();
}

/// <summary>통합 테스트에서 진입점 타입 참조용.</summary>
public partial class Program;
