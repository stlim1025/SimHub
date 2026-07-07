using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SimCenter.Agent.Infrastructure.Pipeline;

namespace SimCenter.Agent.Cli;

/// <summary>텔레메트리 파이프라인을 호스트 생명주기에 태우는 백그라운드 워커.</summary>
public sealed class TelemetryWorker : BackgroundService
{
    private readonly TelemetryPipeline _pipeline;
    private readonly ILogger<TelemetryWorker> _logger;

    public TelemetryWorker(TelemetryPipeline pipeline, ILogger<TelemetryWorker> logger)
    {
        _pipeline = pipeline;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("SimCenter Agent (CLI) 시작 — 텔레메트리 파이프라인 구동");
        await _pipeline.RunAsync(stoppingToken);
    }
}
