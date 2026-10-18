using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.SignalR;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.AspNetCore.SignalR.Protocol;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace SimCenter.Api.IntegrationTests;

/// <summary>통합 테스트 공통 헬퍼: 회원가입·로그인, Agent 장치 연결 흐름, 장치 키로 TelemetryHub 접속.</summary>
internal static class TestApi
{
    private const string Password = "P@ssw0rd!";

    /// <summary>
    /// 새 사용자를 가입·로그인시키고 <paramref name="client"/>의 기본 Authorization 헤더에 Bearer 토큰을 설정한다.
    /// </summary>
    /// <returns>가입한 사용자 ID.</returns>
    public static async Task<Guid> RegisterAndLoginAsync(HttpClient client)
    {
        var email = $"e2e-{Guid.NewGuid():N}@simcenter.test";

        var register = await client.PostAsJsonAsync("/api/v1/auth/register",
            new { email, password = Password, displayName = "E2E 드라이버" });
        register.EnsureSuccessStatusCode();
        var userId = (await register.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();

        var login = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password });
        login.EnsureSuccessStatusCode();
        var token = (await login.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("accessToken").GetString();
        client.DefaultRequestHeaders.Authorization = new("Bearer", token);

        return userId;
    }

    /// <summary>
    /// 로그인된 <paramref name="client"/>의 사용자로 연결 코드를 발급하고 그 코드로 장치를 연결한다.
    /// 연결 요청은 요청마다 무작위 원격 IP로 보내, 같은 테스트 클래스 안에서 여러 번 연결해도 IP 요청 제한에 걸리지 않는다.
    /// </summary>
    public static async Task<(Guid DeviceId, string DeviceKey)> PairDeviceAsync(HttpClient client, string deviceName)
    {
        var code = await IssuePairingCodeAsync(client);

        using var response = await PairAsync(client, code, deviceName);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();

        return (body.GetProperty("deviceId").GetGuid(), body.GetProperty("deviceKey").GetString()!);
    }

    /// <summary>연결 코드를 발급하고 표시 형식(<c>XXXX-XXXX</c>) 코드를 돌려준다.</summary>
    public static async Task<string> IssuePairingCodeAsync(HttpClient client)
    {
        using var issue = await client.PostAsync("/api/v1/me/agent-pairing-codes", content: null);
        issue.EnsureSuccessStatusCode();
        return (await issue.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString()!;
    }

    /// <summary>
    /// <c>POST /agent/pair</c>를 호출한다. <paramref name="remoteIp"/>를 생략하면 요청마다 무작위 IP를 쓴다.
    /// </summary>
    public static Task<HttpResponseMessage> PairAsync(HttpClient client, string code, string deviceName, string? remoteIp = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/agent/pair")
        {
            Content = JsonContent.Create(new { code, deviceName }),
        };
        request.Headers.Add(ApiFactory.RemoteIpHeader, remoteIp ?? RandomRemoteIp());
        return client.SendAsync(request);
    }

    /// <summary>사설 대역의 무작위 IPv4 주소(테스트 간 요청 제한 격리용).</summary>
    public static string RandomRemoteIp()
        => $"10.{Random.Shared.Next(0, 256)}.{Random.Shared.Next(0, 256)}.{Random.Shared.Next(1, 255)}";

    /// <summary>
    /// TestServer WebSocket으로 TelemetryHub에 장치 키(<c>X-Agent-Key</c>)로 접속하는 연결을 만든다(시작은 호출자가 한다).
    /// LongPolling은 요청마다 인증을 다시 하므로, "해제 후 이미 열린 연결로 전송" 같은 경로를 검증하려면 WebSocket이 필요하다.
    /// JSON 규약은 서버와 같다(camelCase + enum 문자열).
    /// </summary>
    public static HubConnection BuildTelemetryConnection(ApiFactory factory, string deviceKey)
    {
        return new HubConnectionBuilder()
            .WithUrl(new Uri(factory.Server.BaseAddress, "hubs/telemetry"), options =>
            {
                options.Transports = HttpTransportType.WebSockets;
                options.SkipNegotiation = true;
                options.WebSocketFactory = async (context, cancellationToken) =>
                {
                    var webSocketClient = factory.Server.CreateWebSocketClient();
                    webSocketClient.ConfigureRequest = request => request.Headers["X-Agent-Key"] = deviceKey;
                    return await webSocketClient.ConnectAsync(context.Uri, cancellationToken);
                };
            })
            .AddJsonProtocol(ConfigureJsonProtocol)
            .Build();
    }

    /// <summary>
    /// 웹 앱과 같은 방식으로 RankingHub에 접속하는 연결을 만든다(시작은 호출자가 한다). 브라우저 WebSocket은 헤더를 못 실으므로
    /// JWT를 쿼리 <c>access_token</c>으로 보낸다(docs/15 §9, D-50).
    /// </summary>
    public static HubConnection BuildRankingConnectionWithQueryToken(ApiFactory factory, string accessToken)
    {
        var url = new Uri(factory.Server.BaseAddress, $"hubs/ranking?access_token={Uri.EscapeDataString(accessToken)}");
        return new HubConnectionBuilder()
            .WithUrl(url, options =>
            {
                options.Transports = HttpTransportType.WebSockets;
                options.SkipNegotiation = true;
                options.WebSocketFactory = async (context, cancellationToken)
                    => await factory.Server.CreateWebSocketClient().ConnectAsync(context.Uri, cancellationToken);
            })
            .AddJsonProtocol(ConfigureJsonProtocol)
            .Build();
    }

    /// <summary>
    /// <c>SubmitEvent</c> 호출 한 건이 와이어에서 차지하는 바이트 수. <see cref="BuildTelemetryConnection"/>과 같은 설정으로 직렬화하므로
    /// 허브 수신 한도(<c>MaximumReceiveMessageSize</c>)에 실제로 걸리는 크기다.
    /// </summary>
    public static int MeasureInvocationBytes(object envelope)
    {
        var options = new JsonHubProtocolOptions();
        ConfigureJsonProtocol(options);
        var protocol = new JsonHubProtocol(Options.Create(options));
        return protocol.GetMessageBytes(new InvocationMessage("SubmitEvent", [envelope])).Length;
    }

    /// <summary>테스트 클라이언트의 허브 JSON 규약(서버와 같다: camelCase + enum 문자열).</summary>
    private static void ConfigureJsonProtocol(JsonHubProtocolOptions json)
    {
        json.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        json.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
        json.PayloadSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    }
}
