using System.Net;
using System.Net.Sockets;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Agent.Infrastructure.Udp;

namespace SimCenter.Agent.Infrastructure.Tests;

public class UdpTelemetryListenerTests
{
    [Fact]
    public async Task RunAsync_ReceivesDatagram_InvokesCallbackWithBytes()
    {
        const int port = 24557;
        var payload = Encoding.ASCII.GetBytes("hello-udp");
        var received = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);

        var listener = new UdpTelemetryListener(port, NullLogger<UdpTelemetryListener>.Instance);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));

        var run = listener.RunAsync((bytes, _) =>
        {
            received.TrySetResult(bytes.ToArray());
            return Task.CompletedTask;
        }, cts.Token);

        // 리스너가 바인딩될 때까지 재전송하며 콜백 수신을 대기.
        using var sender = new UdpClient();
        var endpoint = new IPEndPoint(IPAddress.Loopback, port);
        while (!received.Task.IsCompleted && !cts.IsCancellationRequested)
        {
            await sender.SendAsync(payload, payload.Length, endpoint);
            var done = await Task.WhenAny(received.Task, Task.Delay(100, cts.Token));
            if (done == received.Task)
            {
                break;
            }
        }

        Assert.True(received.Task.IsCompletedSuccessfully, "리스너가 데이터그램을 수신하지 못했습니다.");
        Assert.Equal(payload, await received.Task);

        await cts.CancelAsync();
        await run;
    }
}
