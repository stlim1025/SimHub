using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection; // AddJsonProtocol 확장 메서드

namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// SignalR <see cref="HubConnection"/>으로 TelemetryHub 세션을 만든다. 장치 키는 <c>X-Agent-Key</c> 헤더로 보내고,
/// 페이로드는 서버 계약(camelCase + enum 문자열)으로 직렬화하며, 끊기면 자동 재접속한다.
/// </summary>
public sealed class SignalRTelemetryHubSessionFactory : ITelemetryHubSessionFactory
{
    /// <summary>서버 AgentApiKeyAuthenticationHandler가 읽는 헤더 이름.</summary>
    private const string AgentKeyHeader = "X-Agent-Key";

    private const string SubmitEventMethod = "SubmitEvent";

    public ITelemetryHubSession Create(Uri hubUri, string deviceKey)
    {
        ArgumentNullException.ThrowIfNull(hubUri);
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceKey);

        var connection = new HubConnectionBuilder()
            .WithUrl(hubUri, options => options.Headers.Add(AgentKeyHeader, deviceKey))
            .WithAutomaticReconnect()
            .AddJsonProtocol(json =>
            {
                json.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
                json.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
                json.PayloadSerializerOptions.Converters.Add(new JsonStringEnumConverter());
            })
            .Build();

        return new SignalRTelemetryHubSession(connection);
    }

    private sealed class SignalRTelemetryHubSession(HubConnection connection) : ITelemetryHubSession
    {
        public bool IsConnected => connection.State == HubConnectionState.Connected;

        // 자동 재접속 중(Reconnecting)에 StartAsync를 부르면 HubConnection이 예외를 던지므로 끊긴 상태에서만 시작한다.
        public Task StartAsync(CancellationToken ct)
            => connection.State == HubConnectionState.Disconnected ? connection.StartAsync(ct) : Task.CompletedTask;

        public async Task<SubmitResult> SubmitAsync(JsonElement envelope, CancellationToken ct)
        {
            var result = await connection.InvokeAsync<SubmitResult?>(SubmitEventMethod, envelope, ct);
            return result ?? throw new InvalidOperationException("TelemetryHub가 빈 응답을 반환했습니다.");
        }

        public ValueTask DisposeAsync() => connection.DisposeAsync();
    }
}
