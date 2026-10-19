using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Hosting;
using SimCenter.Api.RateLimiting;
using SimCenter.Api.Startup;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 프록시 헤더(16 §4.3, D-58): 루프백 프록시(Tailscale Funnel)가 보낸 <c>X-Forwarded-Proto</c>·<c>X-Forwarded-For</c>만 믿는다.
/// Proto는 HTTPS 리다이렉트 판단에, For는 IP당 요청 제한(<c>POST /agent/pair</c>)에 쓰인다. 루프백이 아닌 곳에서 온 헤더는 무시한다.
/// 요청 제한 상태를 테스트마다 분리하려고 테스트마다 호스트를 새로 띄운다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class ForwardedHeadersE2ETests
{
    private const string LoopbackProxy = "127.0.0.1";
    private const string UntrustedProxy = "203.0.113.10";
    private const string ForwardedProtoHeader = "X-Forwarded-Proto";
    private const string ForwardedForHeader = "X-Forwarded-For";

    /// <summary>테스트 서버는 HTTPS 포트를 모르므로 지정해야 운영의 HTTPS 리다이렉트가 동작한다.</summary>
    private const string HttpsPort = "8443";

    /// <summary>Production은 user-secrets를 읽지 않으므로 테스트 전용 서명 키를 넣는다(시크릿 아님).</summary>
    private const string TestJwtKey = "integration-test-jwt-key-not-a-secret-0123456789";

    [Fact]
    public async Task Production_ForwardedProtoHttpsFromLoopbackProxy_IsNotRedirected()
    {
        await using var factory = CreateProductionFactory();
        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });

        var response = await client.SendAsync(BuildMeRequest(LoopbackProxy, forwardedProto: "https"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode); // 리다이렉트 없이 인증 단계까지 도달
    }

    [Fact]
    public async Task Production_ForwardedProtoHttpsFromUntrustedAddress_IsIgnoredAndRedirected()
    {
        await using var factory = CreateProductionFactory();
        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });

        var response = await client.SendAsync(BuildMeRequest(UntrustedProxy, forwardedProto: "https"));

        Assert.Equal(HttpStatusCode.TemporaryRedirect, response.StatusCode);
        Assert.Equal(Uri.UriSchemeHttps, response.Headers.Location?.Scheme);
    }

    [Fact]
    public async Task Pair_ForwardedForFromLoopbackProxy_LimitsPerClientIp()
    {
        await using var factory = new ApiFactory();
        var client = factory.CreateClient();
        var limitedClient = TestApi.RandomRemoteIp();
        var otherClient = TestApi.RandomRemoteIp();

        for (var i = 0; i < RateLimitPolicies.PermitLimit; i++)
        {
            var allowed = await client.SendAsync(BuildPairRequest(LoopbackProxy, limitedClient));
            Assert.Equal(HttpStatusCode.BadRequest, allowed.StatusCode); // 한도 안: 코드 오류(400)까지 도달
        }

        var limited = await client.SendAsync(BuildPairRequest(LoopbackProxy, limitedClient));
        var unaffected = await client.SendAsync(BuildPairRequest(LoopbackProxy, otherClient));

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, unaffected.StatusCode); // 같은 프록시를 거쳐도 다른 클라이언트는 별도 한도
    }

    [Fact]
    public async Task Pair_ForwardedForFromUntrustedAddress_IsIgnored()
    {
        await using var factory = new ApiFactory();
        var client = factory.CreateClient();
        var untrustedRemote = TestApi.RandomRemoteIp();

        for (var i = 0; i < RateLimitPolicies.PermitLimit; i++)
        {
            var allowed = await client.SendAsync(BuildPairRequest(untrustedRemote, TestApi.RandomRemoteIp()));
            Assert.Equal(HttpStatusCode.BadRequest, allowed.StatusCode);
        }

        // 헤더를 바꿔 끼워도 실제 원격 주소 기준으로 제한된다(위조로 우회 불가).
        var limited = await client.SendAsync(BuildPairRequest(untrustedRemote, TestApi.RandomRemoteIp()));

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
    }

    private static ApiFactory CreateProductionFactory()
        => new(Environments.Production, new Dictionary<string, string?>
        {
            ["Jwt:Key"] = TestJwtKey,
            ["https_port"] = HttpsPort,
            [DatabaseStartup.MigrateOnStartupKey] = "false", // 컬렉션 fixture가 이미 마이그레이션·시드했다
        });

    private static HttpRequestMessage BuildMeRequest(string remoteIp, string forwardedProto)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/me");
        request.Headers.Add(ApiFactory.RemoteIpHeader, remoteIp);
        request.Headers.Add(ForwardedProtoHeader, forwardedProto);
        return request;
    }

    private static HttpRequestMessage BuildPairRequest(string remoteIp, string forwardedFor)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/agent/pair")
        {
            Content = JsonContent.Create(new { code = "ZZZZ-ZZZZ", deviceName = "PC" }),
        };
        request.Headers.Add(ApiFactory.RemoteIpHeader, remoteIp);
        request.Headers.Add(ForwardedForHeader, forwardedFor);
        return request;
    }
}
