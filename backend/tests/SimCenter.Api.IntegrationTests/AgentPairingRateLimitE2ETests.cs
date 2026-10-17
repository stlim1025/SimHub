using System.Net;
using SimCenter.Api.RateLimiting;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 연결 API 요청 제한(11 §4.4): <c>POST /agent/pair</c>는 IP당, 코드 발급은 사용자당 고정 창 한도를 넘으면 429.
/// 한도(분당 10회)를 소진하는 테스트라 전용 호스트(고정 창 상태 분리)에서 실행한다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class AgentPairingRateLimitE2ETests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;

    public AgentPairingRateLimitE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Pair_ExceedingPerIpLimit_Returns429_AndOtherIpIsUnaffected()
    {
        var client = _factory.CreateClient();
        var limitedIp = TestApi.RandomRemoteIp();
        var otherIp = TestApi.RandomRemoteIp();

        for (var i = 0; i < RateLimitPolicies.PermitLimit; i++)
        {
            var allowed = await TestApi.PairAsync(client, "ZZZZ-ZZZZ", "PC", limitedIp);
            Assert.Equal(HttpStatusCode.BadRequest, allowed.StatusCode); // 한도 안: 코드 오류(400)까지 도달.
        }

        var limited = await TestApi.PairAsync(client, "ZZZZ-ZZZZ", "PC", limitedIp);
        var unaffected = await TestApi.PairAsync(client, "ZZZZ-ZZZZ", "PC", otherIp);

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, unaffected.StatusCode);
    }

    [Fact]
    public async Task IssueCode_ExceedingPerUserLimit_Returns429_AndOtherUserIsUnaffected()
    {
        var heavyUser = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(heavyUser);
        var otherUser = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(otherUser);

        for (var i = 0; i < RateLimitPolicies.PermitLimit; i++)
        {
            var allowed = await heavyUser.PostAsync("/api/v1/me/agent-pairing-codes", content: null);
            Assert.Equal(HttpStatusCode.Created, allowed.StatusCode);
        }

        var limited = await heavyUser.PostAsync("/api/v1/me/agent-pairing-codes", content: null);
        var unaffected = await otherUser.PostAsync("/api/v1/me/agent-pairing-codes", content: null);

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.Equal(HttpStatusCode.Created, unaffected.StatusCode);
    }
}
