using Microsoft.AspNetCore.SignalR;
using SimCenter.Agent.Infrastructure.Upload;

namespace SimCenter.Agent.Infrastructure.Tests;

public class HubSubmitInvokerTests
{
    private static readonly SubmitResult Acked = new(true, null);
    private static readonly TimeSpan LongTimeout = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan ShortTimeout = TimeSpan.FromMilliseconds(50);

    [Fact]
    public async Task ServerAnswer_IsReturned()
    {
        var result = await HubSubmitInvoker.InvokeAsync(_ => Task.FromResult<SubmitResult?>(Acked), LongTimeout, CancellationToken.None);

        Assert.Equal(Acked, result);
    }

    [Fact]
    public async Task HubException_BecomesServerError()
    {
        var hubError = new HubException("An unexpected error occurred invoking 'SubmitEvent' on the server.");

        var ex = await Assert.ThrowsAsync<TelemetryHubServerException>(
            () => HubSubmitInvoker.InvokeAsync(_ => Task.FromException<SubmitResult?>(hubError), LongTimeout, CancellationToken.None));

        Assert.Same(hubError, ex.InnerException);
        Assert.Contains("SubmitEvent", ex.Message);
    }

    [Fact]
    public async Task NullAnswer_BecomesServerError()
    {
        await Assert.ThrowsAsync<TelemetryHubServerException>(
            () => HubSubmitInvoker.InvokeAsync(_ => Task.FromResult<SubmitResult?>(null), LongTimeout, CancellationToken.None));
    }

    [Fact]
    public async Task NoAnswerWithinTimeout_BecomesServerError()
    {
        await Assert.ThrowsAsync<TelemetryHubServerException>(() => HubSubmitInvoker.InvokeAsync(
            async token =>
            {
                await Task.Delay(Timeout.Infinite, token);
                return Acked;
            },
            ShortTimeout,
            CancellationToken.None));
    }

    public static TheoryData<Exception> NetworkFailures() => new()
    {
        new TaskCanceledException("Invocation canceled due to the underlying connection being closed."),
        new IOException("The remote party closed the WebSocket connection."),
        new InvalidOperationException("The 'InvokeCoreAsync' method cannot be called if the connection is not active"),
        new TimeoutException("Server timeout elapsed without receiving a message from the server."),
    };

    [Theory]
    [MemberData(nameof(NetworkFailures))]
    public async Task ConnectionFailures_PassThroughUnchanged(Exception failure)
    {
        var ex = await Assert.ThrowsAnyAsync<Exception>(
            () => HubSubmitInvoker.InvokeAsync(_ => Task.FromException<SubmitResult?>(failure), LongTimeout, CancellationToken.None));

        Assert.Same(failure, ex);
    }

    [Fact]
    public async Task Shutdown_PassesCancellationThrough()
    {
        using var shutdown = new CancellationTokenSource();

        var ex = await Assert.ThrowsAnyAsync<OperationCanceledException>(() => HubSubmitInvoker.InvokeAsync(
            async token =>
            {
                await shutdown.CancelAsync();
                await Task.Delay(Timeout.Infinite, token);
                return Acked;
            },
            LongTimeout,
            shutdown.Token));

        Assert.IsNotType<TelemetryHubServerException>(ex);
    }

    [Fact]
    public async Task NonPositiveTimeout_Throws()
    {
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(
            () => HubSubmitInvoker.InvokeAsync(_ => Task.FromResult<SubmitResult?>(Acked), TimeSpan.Zero, CancellationToken.None));
    }
}
