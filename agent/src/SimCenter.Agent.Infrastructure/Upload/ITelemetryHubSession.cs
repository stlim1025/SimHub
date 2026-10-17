using System.Text.Json;

namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// 장치 키 하나로 맺은 TelemetryHub 연결. 업로더가 SignalR에 직접 의존하지 않게 하는 경계(테스트 대역 가능).
/// </summary>
public interface ITelemetryHubSession : IAsyncDisposable
{
    /// <summary>지금 이벤트를 보낼 수 있는 상태인지.</summary>
    bool IsConnected { get; }

    /// <summary>
    /// 끊긴 상태면 연결을 시작한다(이미 연결됐거나 자동 재접속 중이면 아무것도 하지 않는다).
    /// 서버가 장치 키를 거부하면 401 <see cref="HttpRequestException"/>이 난다(<see cref="UnauthorizedDetector"/>).
    /// </summary>
    Task StartAsync(CancellationToken ct);

    /// <summary>봉투 하나를 보내고 서버 응답(Ack/Reject)을 받는다. 응답이 없으면(장애) 예외.</summary>
    Task<SubmitResult> SubmitAsync(JsonElement envelope, CancellationToken ct);
}

/// <summary>서버 SubmitEvent 반환값(IngestResult). camelCase로 매핑된다.</summary>
public sealed record SubmitResult(bool Acknowledged, string? RejectReason);

/// <summary>허브 주소와 장치 키로 <see cref="ITelemetryHubSession"/>을 만든다. 키가 바뀌면 새 세션을 만든다.</summary>
public interface ITelemetryHubSessionFactory
{
    ITelemetryHubSession Create(Uri hubUri, string deviceKey);
}
