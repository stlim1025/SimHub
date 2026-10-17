namespace SimCenter.Agent.Infrastructure.Pairing;

/// <summary>
/// Cli <c>pair &lt;코드&gt;</c> 명령(docs/11 §6.3). 서버에 연결 코드를 보내 이 PC를 계정에 연결하고,
/// 결과를 <paramref name="output"/>에 쓴 뒤 종료 코드(성공 0, 실패 1)를 돌려준다. 연결 코드는 출력하지 않는다.
/// </summary>
public static class PairCommand
{
    /// <summary>명령 이름(첫 번째 인자).</summary>
    public const string Name = "pair";

    private const string UsageMessage = "사용법: SimCenter.Agent.Cli pair <코드>";
    private const string CancelledMessage = "연결이 취소되었습니다.";

    private const int SuccessExitCode = 0;
    private const int FailureExitCode = 1;
    private const int ExpectedArgumentCount = 2;

    /// <summary>첫 인자가 <c>pair</c>이면 true — Program이 호스트 대신 이 명령을 실행할지 가른다.</summary>
    public static bool IsPairInvocation(IReadOnlyList<string> args)
        => args.Count > 0 && string.Equals(args[0], Name, StringComparison.OrdinalIgnoreCase);

    /// <param name="args"><c>["pair", 코드]</c> 형태만 받아들인다.</param>
    /// <param name="client">연결 클라이언트.</param>
    /// <param name="deviceName">서버에 표시할 PC 이름(보통 <see cref="Environment.MachineName"/>).</param>
    /// <param name="output">안내·결과를 쓸 출력.</param>
    /// <param name="ct">취소 토큰(Ctrl+C).</param>
    /// <returns>성공 0, 사용법 오류·연결 실패·취소 1.</returns>
    public static async Task<int> RunAsync(
        IReadOnlyList<string> args,
        IAgentPairingClient client,
        string deviceName,
        TextWriter output,
        CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(client);
        ArgumentNullException.ThrowIfNull(output);

        if (!IsPairInvocation(args) || args.Count != ExpectedArgumentCount || string.IsNullOrWhiteSpace(args[1]))
        {
            await output.WriteLineAsync(UsageMessage);
            return FailureExitCode;
        }

        try
        {
            var outcome = await client.PairAsync(args[1], deviceName, ct);
            await output.WriteLineAsync(outcome.Message);
            return outcome.Succeeded ? SuccessExitCode : FailureExitCode;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            await output.WriteLineAsync(CancelledMessage);
            return FailureExitCode;
        }
    }
}
