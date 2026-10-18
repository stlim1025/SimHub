using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using Serilog;
using SimCenter.Api.Hubs;
using SimCenter.Api.Middleware;
using SimCenter.Api.Notifications;
using SimCenter.Api.RateLimiting;
using SimCenter.Application;
using SimCenter.Application.Rankings.Notifications;
using SimCenter.Infrastructure;
using SimCenter.Infrastructure.Persistence;
using SimCenter.Infrastructure.Persistence.Seed;

var builder = WebApplication.CreateBuilder(args);

// ── Serilog(헌장: Logging 필수) ──
// ASP.NET Core 내부 로그는 Warning부터만 남긴다. Hosting 진단 로그("Request starting …")가 쿼리 문자열까지 찍어
// RankingHub의 `?access_token=`(JWT)이 로그에 그대로 남았다. 요청 기록은 경로만 쓰는 UseSerilogRequestLogging이 맡는다.
// 설정 파일의 Serilog 섹션이 있으면 그 값이 우선한다(아래 ReadFrom이 덮어쓴다).
builder.Host.UseSerilog((context, config) =>
    config.MinimumLevel.Override("Microsoft.AspNetCore", Serilog.Events.LogEventLevel.Warning)
        .ReadFrom.Configuration(context.Configuration)
        .Enrich.FromLogContext()
        .WriteTo.Console());

// ── 계층 서비스 등록 ──
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

// 실시간 브로드캐스트 포트(Application) → SignalR 구현(Api). 의존 방향 Api → Application 유지.
builder.Services.AddScoped<IRankingNotifier, RankingNotifier>();

// SignalR 사용자 식별 = JWT sub → Clients.User(userId)로 랩 주인에게만 보낸다(docs/15 §9, D-50).
builder.Services.AddSingleton<Microsoft.AspNetCore.SignalR.IUserIdProvider, JwtSubjectUserIdProvider>();

// Flutter 웹 dev 실행을 위한 CORS(Development 전용). 루프백 오리진만 반사 허용 → 운영은 미개방.
const string DevCorsPolicy = "DevCors";
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options =>
        options.AddPolicy(DevCorsPolicy, policy =>
            policy.SetIsOriginAllowed(origin => Uri.TryCreate(origin, UriKind.Absolute, out var uri) && uri.IsLoopback)
                .AllowAnyHeader()
                .AllowAnyMethod()
                .AllowCredentials()));
}

builder.Services.AddControllers();

// ── 연결 API 요청 제한(11 §4.4): /agent/pair는 IP당, 코드 발급은 사용자당 분당 10회. ──
builder.Services.AddSimCenterRateLimiting();

// ── SignalR(실시간 인입, 05-signalr-design). JSON은 camelCase + enum 문자열로 계약 고정. ──
builder.Services.AddSignalR()
    .AddJsonProtocol(options =>
    {
        options.PayloadSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
        options.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
        options.PayloadSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    })
    // 인입 메시지 한도는 기본값(32KB)에 기대지 않고 명시한다(12 §5.5). 넘으면 연결이 끊겨 Agent가 같은 항목을 재시도하게 된다.
    .AddHubOptions<TelemetryHub>(options => options.MaximumReceiveMessageSize = TelemetryHub.MaxMessageBytes);

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

// 요청 로깅이 예외 매핑을 감싸야(바깥) 처리된 4xx(ProblemDetails)가 실제 상태 코드로 기록된다.
// 반대 순서면 요청 로깅이 매핑 전의 예외를 먼저 보고 400·403·404도 "responded 500"(Error)으로 남긴다.
app.UseSerilogRequestLogging();
app.UseMiddleware<ExceptionHandlingMiddleware>();

// 운영은 HTTPS 강제. 개발은 앱(웹/에뮬레이터) cleartext 접속을 위해 리다이렉트를 생략한다.
if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}
else
{
    app.UseCors(DevCorsPolicy);
}

app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter(); // 인증 뒤: 사용자 파티션이 주체를 읽고, 401 요청이 한도를 소모하지 않는다.

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
