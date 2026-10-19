using System.Net;
using System.Net.Http.Json;
using SimCenter.Api.RateLimiting;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 로그인 요청 제한(16 §4.5, D-58): <c>POST /auth/login</c>은 클라이언트 IP당 고정 창 한도를 넘으면 429.
/// 외부 공개(Funnel) 시 비밀번호 무작위 대입을 늦춘다. 한도를 소진하는 테스트라 테스트마다 호스트를 새로 띄운다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class AuthLoginRateLimitE2ETests
{
    [Fact]
    public async Task Login_ExceedingPerIpLimit_Returns429_AndOtherIpIsUnaffected()
    {
        await using var factory = new ApiFactory();
        var client = factory.CreateClient();
        var limitedIp = TestApi.RandomRemoteIp();
        var otherIp = TestApi.RandomRemoteIp();

        for (var i = 0; i < RateLimitPolicies.PermitLimit; i++)
        {
            var allowed = await client.SendAsync(BuildLoginRequest(limitedIp));
            Assert.Equal(HttpStatusCode.Unauthorized, allowed.StatusCode); // 한도 안: 인증 실패(401)까지 도달
        }

        var limited = await client.SendAsync(BuildLoginRequest(limitedIp));
        var unaffected = await client.SendAsync(BuildLoginRequest(otherIp));

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, unaffected.StatusCode);
    }

    /// <summary>없는 계정으로 로그인한다(사용자를 만들지 않아 테스트 DB에 남는 것이 없다).</summary>
    private static HttpRequestMessage BuildLoginRequest(string remoteIp)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/login")
        {
            Content = JsonContent.Create(new { email = "nobody@simcenter.test", password = "wrong-password" }),
        };
        request.Headers.Add(ApiFactory.RemoteIpHeader, remoteIp);
        return request;
    }
}
