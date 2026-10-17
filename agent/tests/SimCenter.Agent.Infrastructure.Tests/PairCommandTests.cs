using SimCenter.Agent.Infrastructure.Pairing;

namespace SimCenter.Agent.Infrastructure.Tests;

public sealed class PairCommandTests
{
    private const string Code = "K7F2-9QXM";
    private const string DeviceName = "SIM-RIG-01";
    private const string Usage = "사용법: SimCenter.Agent.Cli pair <코드>";

    private readonly FakePairingClient _client = new();
    private readonly StringWriter _output = new();

    [Fact]
    public async Task PairCommand_WithCode_Success_Returns0()
    {
        _client.Result = new PairOutcome(true, "연결되었습니다. 이제 기록이 이 계정에 쌓입니다.");

        var exitCode = await PairCommand.RunAsync(["pair", Code], _client, DeviceName, _output, CancellationToken.None);

        Assert.Equal(0, exitCode);
        Assert.Contains("연결되었습니다", _output.ToString());
        Assert.DoesNotContain(Code, _output.ToString());

        var call = Assert.Single(_client.Calls);
        Assert.Equal((Code, DeviceName), call);
    }

    [Theory]
    [MemberData(nameof(BadArguments))]
    public async Task PairCommand_MissingOrExtraArguments_PrintsUsage_Returns1(string[] args)
    {
        var exitCode = await PairCommand.RunAsync(args, _client, DeviceName, _output, CancellationToken.None);

        Assert.Equal(1, exitCode);
        Assert.Contains(Usage, _output.ToString());
        Assert.Empty(_client.Calls);
    }

    public static TheoryData<string[]> BadArguments() => new()
    {
        new[] { "pair" },
        new[] { "pair", "  " },
        new[] { "pair", Code, "extra" },
        new[] { "other", Code },
    };

    [Fact]
    public async Task PairCommand_Failure_PrintsMessage_Returns1()
    {
        _client.Result = new PairOutcome(false, "유효하지 않거나 만료된 코드입니다.");

        var exitCode = await PairCommand.RunAsync(["pair", Code], _client, DeviceName, _output, CancellationToken.None);

        Assert.Equal(1, exitCode);
        Assert.Contains("유효하지 않거나 만료된 코드입니다.", _output.ToString());
        Assert.DoesNotContain(Code, _output.ToString());
    }

    [Fact]
    public async Task PairCommand_Cancelled_PrintsNotice_Returns1()
    {
        _client.Failure = new OperationCanceledException();
        using var cts = new CancellationTokenSource();
        await cts.CancelAsync();

        var exitCode = await PairCommand.RunAsync(["pair", Code], _client, DeviceName, _output, cts.Token);

        Assert.Equal(1, exitCode);
        Assert.Contains("취소", _output.ToString());
    }

    private sealed class FakePairingClient : IAgentPairingClient
    {
        public List<(string Code, string DeviceName)> Calls { get; } = [];

        public PairOutcome Result { get; set; } = new(true, "연결되었습니다.");

        public Exception? Failure { get; set; }

        public Task<PairOutcome> PairAsync(string code, string deviceName, CancellationToken ct)
        {
            Calls.Add((code, deviceName));
            return Failure is null ? Task.FromResult(Result) : Task.FromException<PairOutcome>(Failure);
        }
    }
}
