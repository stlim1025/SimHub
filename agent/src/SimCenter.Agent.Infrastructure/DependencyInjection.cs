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
using SimCenter.Agent.Infrastructure.Mapping;
using SimCenter.Agent.Infrastructure.Outbox;
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
            return new F1PacketMapper(options.ExpectedPacketFormat);
        });

        services.AddSingleton(sp =>
        {
            var options = sp.GetRequiredService<IOptions<AgentOptions>>().Value;
            return new AgentIdentity(options.RigCode, options.GameCode);
        });

        // LapAnalyzer는 상태 저장 — 단일 인스턴스로 파이프라인이 순차 소비.
        services.AddSingleton<LapAnalyzer>();
        services.AddSingleton<DomainEventFactory>();

        // P3: 봉투를 Outbox(SQLite)에 적재하고, 업로더가 TelemetryHub로 배수한다(전송 실패에도 무손실).
        services.AddSingleton<TelemetryOutbox>();
        services.AddSingleton<ITelemetrySink, OutboxTelemetrySink>();
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
