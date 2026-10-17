using Microsoft.AspNetCore.SignalR;

namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// TelemetryHub 호출 하나를 실행하고 실패를 분류한다(docs/13 §3.1, D-36). 서버 오류는 <see cref="TelemetryHubServerException"/>으로 바꾸고,
/// 연결 문제와 종료 취소는 그대로 올린다. SignalR 서버 없이 단위 테스트할 수 있게 실제 호출은 대리자로 받는다.
/// </summary>
internal static class HubSubmitInvoker
{
    /// <summary>
    /// 응답 시간 제한. SignalR 기본 <c>ServerTimeout</c>(30초)보다 <b>일부러 길다</b> — 네트워크가 반쯤 끊기면 그쪽이 먼저 연결을 닫아
    /// 네트워크로 분류되고, 연결은 살아 있는데 허브 메서드가 멈춘 경우만 여기서 서버 오류가 된다.
    /// </summary>
    internal static readonly TimeSpan SubmitTimeout = TimeSpan.FromSeconds(60);

    public static async Task<SubmitResult> InvokeAsync(
        Func<CancellationToken, Task<SubmitResult?>> invoke, TimeSpan timeout, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(invoke);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(timeout, TimeSpan.Zero);

        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutSource.CancelAfter(timeout);

        SubmitResult? result;
        try
        {
            result = await invoke(timeoutSource.Token);
        }
        catch (HubException ex)
        {
            // 허브 메서드 예외, 또는 서버가 오류와 함께 연결을 닫음(메시지 크기 초과 등) — 이 메시지에 대한 서버의 판정이다.
            throw new TelemetryHubServerException(ex.Message, ex);
        }
        catch (OperationCanceledException ex) when (timeoutSource.IsCancellationRequested && !ct.IsCancellationRequested)
        {
            // 시간 제한으로 취소됐다. 연결 종료로 인한 취소(우리 토큰과 무관)와 종료 취소(ct)는 여기 오지 않는다.
            throw new TelemetryHubServerException($"TelemetryHub가 {timeout.TotalSeconds:0.#}초 안에 답하지 않았습니다.", ex);
        }

        return result ?? throw new TelemetryHubServerException("TelemetryHub가 빈 응답을 반환했습니다.");
    }
}
