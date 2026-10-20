using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Core.Abstractions;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Infrastructure.Common;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;
using SimCenter.Agent.Infrastructure.Mapping;
using SimCenter.Agent.Infrastructure.Outbox;
using SimCenter.Agent.Infrastructure.Pairing;
using SimCenter.Agent.Infrastructure.Pipeline;
using SimCenter.Agent.Infrastructure.Sinks;
using SimCenter.Agent.Infrastructure.Time;
using SimCenter.Agent.Infrastructure.Udp;
using SimCenter.Agent.Infrastructure.Upload;

namespace SimCenter.Agent.Infrastructure;

/// <summary>Agent Infrastructure 서비스 등록(파싱·수신·파이프라인·어댑터).</summary>
public static class DependencyInjection
{
    public static IServiceCollection AddAgentInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<AgentOptions>(configuration.GetSection(AgentOptions.SectionName));

        services.AddSingleton<IClock, SystemClock>();
        services.AddSingleton<IIdGenerator, UuidV7Generator>();

        // 게임 연결 상태 모니터(GUI가 폴링).
        services.AddSingleton<ConnectionThresholds>();
        services.AddSingleton<GameConnectionMonitor>();

        services.AddSingleton(sp =>
        {
            var options = sp.GetRequiredService<IOptions<AgentOptions>>().Value;
            return new F1PacketMapper(options.ExpectedPacketFormat, sp.GetRequiredService<ILogger<F1PacketMapper>>());
        });

        // 세션별 게임 에디션(F1 25 / F1 26 = 2026 시즌팩) 판별. 파이프라인이 프레임을 먹이고 봉투 생성기가 현재 값을 쓴다 — 같은 인스턴스.
        services.AddSingleton(sp =>
        {
            var options = sp.GetRequiredService<IOptions<AgentOptions>>().Value;
            return new GameEditionDetector(options.GameCode);
        });
        services.AddSingleton<IGameCodeSource>(sp => sp.GetRequiredService<GameEditionDetector>());

        // 분석기는 상태 저장 — 각각 단일 인스턴스로 파이프라인이 순차 소비한다(P7: 분석기 목록, 순서 무관).
        // 목록의 LapAnalyzer·SessionResultTracker는 위 구체 타입과 같은 인스턴스다.
        services.AddSingleton<LapAnalyzer>();
        services.AddSingleton<SessionResultTracker>();
        services.AddSingleton<ITelemetryAnalyzer>(sp => sp.GetRequiredService<LapAnalyzer>());
        services.AddSingleton<ITelemetryAnalyzer>(sp => sp.GetRequiredService<SessionResultTracker>());
        services.AddSingleton<DomainEventFactory>();

        // P6: 계정 연결 시 발급된 장치 키는 Windows DPAPI로 암호화해 보관한다(Windows 전용).
        services.AddSingleton<IDeviceCredentialStore>(sp =>
        {
            if (!OperatingSystem.IsWindows())
            {
                throw new PlatformNotSupportedException("장치 키 저장소는 Windows DPAPI가 필요합니다.");
            }

            var logger = sp.GetRequiredService<ILogger<DpapiDeviceCredentialStore>>();
            return new DpapiDeviceCredentialStore(DpapiDeviceCredentialStore.DefaultPath, logger);
        });

        // P6: 계정 연결 클라이언트. 데스크톱 단일 프로세스라 IHttpClientFactory(Microsoft.Extensions.Http) 없이
        // HttpClient 하나를 프로세스 수명 동안 재사용한다.
        services.AddSingleton<IAgentPairingClient>(sp => new AgentPairingClient(
            new HttpClient { Timeout = AgentPairingClient.RequestTimeout },
            sp.GetRequiredService<IDeviceCredentialStore>(),
            sp.GetRequiredService<IOptions<AgentOptions>>(),
            sp.GetRequiredService<ILogger<AgentPairingClient>>()));

        // P3: 봉투를 Outbox(SQLite)에 적재하고, 업로더가 TelemetryHub로 배수한다(전송 실패에도 무손실).
        // P6: 업로더는 저장된 장치 키로 연결하고, 상태(미연결·401 등)를 UploadStatusTracker로 알린다.
        services.AddSingleton<TelemetryOutbox>();
        services.AddSingleton<ITelemetrySink, OutboxTelemetrySink>();
        services.AddSingleton<UploadStatusTracker>();
        services.AddSingleton<ITelemetryHubSessionFactory, SignalRTelemetryHubSessionFactory>();
        services.AddHostedService<TelemetryUploadService>();

        services.AddSingleton(sp =>
        {
            var options = sp.GetRequiredService<IOptions<AgentOptions>>().Value;
            var logger = sp.GetRequiredService<ILogger<UdpTelemetryListener>>();
            return new UdpTelemetryListener(options.UdpPort, logger);
        });

        services.AddSingleton<TelemetryPipeline>();

        return services;
    }
}
