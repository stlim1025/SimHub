using System.Net.Sockets;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Infrastructure.Pipeline;

namespace SimCenter.Agent.Infrastructure.Hosting;

/// <summary>
/// 텔레메트리 파이프라인을 호스트 생명주기에 태우는 백그라운드 서비스. Cli·Tray가 공유한다.
/// 연결 모니터에 수신 대기/바인딩 실패를 통지한다.
/// </summary>
public sealed class TelemetryHostedService : BackgroundService
{
    private readonly TelemetryPipeline _pipeline;
    private readonly GameConnectionMonitor _monitor;
    private readonly ILogger<TelemetryHostedService> _logger;

    public TelemetryHostedService(TelemetryPipeline pipeline, GameConnectionMonitor monitor, ILogger<TelemetryHostedService> logger)
    {
        _pipeline = pipeline;
        _monitor = monitor;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("SimCenter Agent 텔레메트리 파이프라인 시작");
        _monitor.MarkListening();

        try
        {
            await _pipeline.RunAsync(stoppingToken);
        }
        catch (OperationCanceledException)
        {
            // 정상 종료.
        }
        catch (SocketException ex)
        {
            _monitor.MarkListenerFailed($"UDP 바인딩 실패: {ex.Message}");
            _logger.LogError(ex, "UDP 소켓 바인딩 실패 — 포트가 이미 사용 중일 수 있습니다");
        }
    }
}
