using System.ComponentModel;
using System.Diagnostics;
using Microsoft.Extensions.Logging;

namespace SimCenter.Agent.Tray;

/// <summary>
/// 한 PC에서 UDP 포트를 쓰는 Agent가 하나만 남도록, 새로 켠 Agent가 이미 돌고 있는 Agent를 끈다(창을 닫아도 트레이에 남아 포트를 쥐고 있으므로).
/// 이 기능이 있는 Agent는 종료 신호(이름 붙은 이벤트)를 받으면 스스로 정상 종료하고, 신호를 모르는 예전 Agent나 제때 끝나지 않은 Agent는 강제로 끝낸다.
/// Agent 프로세스는 이름(다운로드 exe·빌드 exe·지금 exe)과 exe 버전 정보의 원래 파일 이름으로 가려낸다.
/// </summary>
internal sealed class AgentInstanceHandoff : IDisposable
{
    /// <summary>같은 사용자 세션 안에서만 보이는 종료 신호 이름.</summary>
    private const string ExitSignalName = @"Local\SimHubAgent.Exit";

    private const string AssemblyFileExtension = ".dll";

    /// <summary>다운로드 exe(<c>SimHubAgent.exe</c>, 브라우저가 붙이는 " (1)" 포함)와 빌드 exe 이름.</summary>
    private static readonly string[] AgentProcessNamePrefixes = ["SimHubAgent", "SimCenter.Agent.Tray"];

    /// <summary>예전 Agent의 종료(호스트 정지 최대 3초 포함)를 기다리는 시간. 넘기면 강제로 끝낸다.</summary>
    private static readonly TimeSpan GracefulExitTimeout = TimeSpan.FromSeconds(6);

    private static readonly TimeSpan KillTimeout = TimeSpan.FromSeconds(3);

    private readonly EventWaitHandle _exitSignal = new(false, EventResetMode.ManualReset, ExitSignalName);
    private RegisteredWaitHandle? _registration;

    /// <summary>다른 Agent 프로세스에 종료를 알리고 끝날 때까지 기다린다. 제때 끝나지 않거나 신호를 모르면 강제로 끝낸다.</summary>
    public void CloseOtherAgents(ILogger logger)
    {
        var others = FindOtherAgents();
        if (others.Count == 0)
        {
            return;
        }

        logger.LogInformation("Closing {Count} running agent process(es) before binding the UDP port", others.Count);
        _exitSignal.Set();
        var waited = Stopwatch.StartNew();
        foreach (var process in others)
        {
            using (process)
            {
                var remaining = GracefulExitTimeout - waited.Elapsed;
                if (!process.WaitForExit(remaining > TimeSpan.Zero ? remaining : TimeSpan.Zero))
                {
                    Kill(process, logger);
                }
            }
        }
    }

    /// <summary>다음에 켜지는 Agent의 종료 신호를 기다린다. 신호가 오면 <paramref name="onExitRequested"/>를 스레드 풀에서 한 번 부른다.</summary>
    public void ListenForExitSignal(Action onExitRequested)
    {
        // 앞서 보낸 신호가 남아 있으면 자기 자신이 바로 꺼지므로 지운 뒤 기다린다.
        _exitSignal.Reset();
        _registration = ThreadPool.RegisterWaitForSingleObject(
            _exitSignal, (_, _) => onExitRequested(), state: null, Timeout.Infinite, executeOnlyOnce: true);
    }

    public void Dispose()
    {
        _registration?.Unregister(null);
        _exitSignal.Dispose();
    }

    private static List<Process> FindOtherAgents()
    {
        using var current = Process.GetCurrentProcess();
        var agentFileName = typeof(AgentInstanceHandoff).Assembly.GetName().Name + AssemblyFileExtension;
        var agents = new List<Process>();
        foreach (var process in Process.GetProcesses())
        {
            if (process.Id != current.Id
                && IsAgentProcessName(process.ProcessName, current.ProcessName)
                && string.Equals(OriginalFileName(process), agentFileName, StringComparison.OrdinalIgnoreCase))
            {
                agents.Add(process);
            }
            else
            {
                process.Dispose();
            }
        }

        return agents;
    }

    private static bool IsAgentProcessName(string name, string currentName) =>
        name.Equals(currentName, StringComparison.OrdinalIgnoreCase)
        || AgentProcessNamePrefixes.Any(prefix => name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));

    /// <summary>exe 버전 정보의 원래 파일 이름. 읽을 수 없으면(권한·이미 종료) null.</summary>
    private static string? OriginalFileName(Process process)
    {
        try
        {
            return process.MainModule?.FileVersionInfo.OriginalFilename;
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or NotSupportedException)
        {
            return null;
        }
    }

    private static void Kill(Process process, ILogger logger)
    {
        var processId = process.Id;
        var processName = process.ProcessName;
        try
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit(KillTimeout);
            logger.LogWarning("Force-closed agent process {ProcessId} ({ProcessName}) that did not exit on signal", processId, processName);
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or NotSupportedException or AggregateException)
        {
            // 관리자 권한으로 켠 Agent 등은 끌 수 없다 — 포트 바인딩 실패가 창에 그대로 보인다.
            logger.LogWarning(ex, "Could not close agent process {ProcessId} ({ProcessName})", processId, processName);
        }
    }
}
