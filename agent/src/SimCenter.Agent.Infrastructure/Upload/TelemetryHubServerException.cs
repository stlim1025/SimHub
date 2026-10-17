namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// TelemetryHub가 이벤트를 받고도 처리하지 못했다 — 허브 메서드 예외, 오류와 함께 연결 종료(메시지 크기 초과 등), 빈 응답, 응답 시간 초과
/// (docs/13 §3.1, D-36). 연결 문제(연결 실패·전송 중 끊김)는 이 예외가 아니다.
/// 업로더는 이 예외만 세어, 같은 항목에서 되풀이되면 그 항목만 미룬다(D-35).
/// </summary>
public sealed class TelemetryHubServerException : Exception
{
    public TelemetryHubServerException(string message)
        : base(message)
    {
    }

    public TelemetryHubServerException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
