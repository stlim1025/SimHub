using System.Net.Sockets;
using Microsoft.Extensions.Logging;

namespace SimCenter.Agent.Infrastructure.Udp;

/// <summary>
/// UDP 데이터그램 수신 루프(소켓 I/O만). 파싱/판정은 하지 않고 수신 바이트를 콜백으로 넘긴다.
/// docs/06: Raw 패킷은 서버로 보내거나 저장하지 않고 로컬에서만 소비.
/// </summary>
public sealed class UdpTelemetryListener
{
    private readonly int _port;
    private readonly ILogger<UdpTelemetryListener> _logger;

    public UdpTelemetryListener(int port, ILogger<UdpTelemetryListener> logger)
    {
        _port = port;
        _logger = logger;
    }

    /// <summary>취소될 때까지 데이터그램을 수신하며 <paramref name="onDatagram"/>을 호출한다.</summary>
    public async Task RunAsync(Func<ReadOnlyMemory<byte>, CancellationToken, Task> onDatagram, CancellationToken cancellationToken)
    {
        using var client = new UdpClient(_port);
        _logger.LogInformation("UDP 텔레메트리 수신 시작 (포트 {Port})", _port);

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                var result = await client.ReceiveAsync(cancellationToken);
                await onDatagram(result.Buffer, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                // 개별 데이터그램 오류는 수신 루프를 중단시키지 않는다.
                _logger.LogError(ex, "UDP 수신/처리 중 오류");
            }
        }

        _logger.LogInformation("UDP 텔레메트리 수신 종료 (포트 {Port})", _port);
    }
}
