using System.Net.Http.Json;
using System.Text.Json;

namespace SimCenter.Api.IntegrationTests;

/// <summary>통합 테스트 공통 헬퍼: 회원가입·로그인과 Agent 장치 연결 흐름.</summary>
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
}
