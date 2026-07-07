using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// Agent → TelemetryHub → DB 전체 경로 E2E. 실 PostgreSQL(로컬 dev)이 필요하다.
/// 흐름: 회원가입 → 로그인 → A-01 체크인 → Hub 접속(dev API Key) → LapFinished 전송 → DB Lap 귀속 확인.
/// </summary>
public sealed class TelemetryIngestE2ETests : IClassFixture<TelemetryIngestE2ETests.ApiFactory>
{
    private const string RigCode = "A-01";
    private const string DevKey = "dev-agent-key-A-01"; // DbSeeder.DevApiKeyFor("A-01")

    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly ApiFactory _factory;

    public TelemetryIngestE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task LapFinished_FromAgent_IsAttributedAndPersisted()
    {
        var client = _factory.CreateClient();
        var email = $"e2e-{Guid.NewGuid():N}@simcenter.test";

        // 0. 재실행 가능성 보장: 이전 실행이 남긴 A-01 활성 세션을 정리한다(타인 점유 409 방지).
        await ResetRigAsync();

        // 1. 회원가입.
        var register = await client.PostAsJsonAsync("/api/v1/auth/register",
            new { email, password = "P@ssw0rd!", displayName = "E2E 드라이버" });
        register.EnsureSuccessStatusCode();
        var userId = (await register.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();

        // 2. 로그인 → JWT.
        var login = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = "P@ssw0rd!" });
        login.EnsureSuccessStatusCode();
        var token = (await login.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("accessToken").GetString();
        client.DefaultRequestHeaders.Authorization = new("Bearer", token);

        // 3. A-01 체크인 → 활성 세션.
        var checkIn = await client.PostAsJsonAsync("/api/v1/sessions/check-in", new { rigCode = RigCode, gameCode = "F1_25" });
        checkIn.EnsureSuccessStatusCode();

        // 4. Hub 접속(LongPolling + TestServer 핸들러 + Agent 키).
        await using var connection = BuildConnection();
        await connection.StartAsync();

        // 5. LapFinished 전송.
        var eventId = Guid.NewGuid();
        var envelope = new
        {
            eventId,
            rigCode = RigCode,
            gameCode = "F1_25",
            occurredAt = new DateTime(2026, 7, 7, 9, 3, 21, DateTimeKind.Utc),
            type = "LapFinished",
            payload = new
            {
                sessionRef = "0xSESSION",
                lapNumber = 4,
                lapTimeMs = 83452,
                sectors = new[]
                {
                    new { sectorNumber = 1, sectorTimeMs = 27010 },
                    new { sectorNumber = 2, sectorTimeMs = 30110 },
                    new { sectorNumber = 3, sectorTimeMs = 26332 },
                },
                isValid = true,
                isOutOrInLap = false,
                trackId = 7, // Silverstone
                sessionType = "TimeTrial",
            },
        };

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", envelope);
        Assert.True(ack.Acknowledged, ack.RejectReason);

        // 6. DB에 Lap이 사용자에게 귀속 저장됐는지 확인.
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var lap = await db.Laps.Include(l => l.Sectors).FirstOrDefaultAsync(l => l.UserId == userId);

        Assert.NotNull(lap);
        Assert.Equal(83452, lap!.LapTimeMs);
        Assert.True(lap.IsRankingEligible);
        Assert.Equal(3, lap.Sectors.Count);
    }

    /// <summary>시드된 A-01 좌석의 활성 세션을 모두 종료해 체크인이 항상 가능하게 한다.</summary>
    private async Task ResetRigAsync()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var rig = await db.SimRigs.FirstAsync(r => r.RigCode == RigCode);
        var actives = await db.DrivingSessions
            .Where(s => s.SimRigId == rig.Id && s.Status == Domain.Enums.SessionStatus.Active)
            .ToListAsync();
        foreach (var session in actives)
        {
            session.Status = Domain.Enums.SessionStatus.Ended;
            session.EndedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync();
    }

    private HubConnection BuildConnection()
    {
        var baseAddress = _factory.Server.BaseAddress;
        return new HubConnectionBuilder()
            .WithUrl(new Uri(baseAddress, "hubs/telemetry"), options =>
            {
                options.Transports = HttpTransportType.LongPolling;
                options.HttpMessageHandlerFactory = _ => _factory.Server.CreateHandler();
                options.Headers.Add("X-Agent-Key", DevKey);
            })
            .AddJsonProtocol(json =>
            {
                json.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
                json.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
                json.PayloadSerializerOptions.Converters.Add(new JsonStringEnumConverter());
            })
            .Build();
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);

    /// <summary>Development 환경으로 부팅해 user-secrets 로드 + 마이그레이션/시드가 실행되게 한다.</summary>
    public sealed class ApiFactory : WebApplicationFactory<Program>
    {
        protected override IHost CreateHost(IHostBuilder builder)
        {
            builder.UseEnvironment("Development");
            return base.CreateHost(builder);
        }
    }
}
