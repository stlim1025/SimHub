using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Domain.Entities;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// Agent 연결 흐름 E2E(11 §4): 코드 발급 → 장치 연결 → 목록 → 해제. 실 PostgreSQL(로컬 dev)이 필요하다.
/// 요청 제한(429)은 <see cref="AgentPairingRateLimitE2ETests"/>에서 별도 호스트로 검증한다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class AgentPairingE2ETests : IClassFixture<ApiFactory>
{
    private const string DevicesUrl = "/api/v1/me/agent-devices";
    private const string InvalidCodeMessage = "유효하지 않거나 만료된 코드입니다.";

    private static readonly Regex CodePattern = new("^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$");

    private readonly ApiFactory _factory;

    public AgentPairingE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task IssueCode_Pair_List_Revoke_RoundTrip()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        // 1. 코드 발급 → 201, 표시 형식 XXXX-XXXX.
        var issue = await client.PostAsync("/api/v1/me/agent-pairing-codes", content: null);
        Assert.Equal(HttpStatusCode.Created, issue.StatusCode);
        var issued = await issue.Content.ReadFromJsonAsync<JsonElement>();
        var code = issued.GetProperty("code").GetString()!;
        Assert.Matches(CodePattern, code);
        Assert.True(issued.GetProperty("expiresAt").GetDateTime() > DateTime.UtcNow);

        // 2. 익명 클라이언트(Agent)로 연결 → 200, 43자 장치 키.
        var anonymous = _factory.CreateClient();
        var pair = await TestApi.PairAsync(anonymous, code, "E2E-PC");
        Assert.Equal(HttpStatusCode.OK, pair.StatusCode);
        var paired = await pair.Content.ReadFromJsonAsync<JsonElement>();
        var deviceId = paired.GetProperty("deviceId").GetGuid();
        Assert.Equal(43, paired.GetProperty("deviceKey").GetString()!.Length);

        // 3. 내 장치 목록에 방금 연결한 장치가 있다(아직 수신 이력 없음).
        var list = await client.GetFromJsonAsync<JsonElement>(DevicesUrl);
        var item = Assert.Single(list.GetProperty("items").EnumerateArray());
        Assert.Equal(deviceId, item.GetProperty("deviceId").GetGuid());
        Assert.Equal("E2E-PC", item.GetProperty("name").GetString());
        Assert.Equal(JsonValueKind.Null, item.GetProperty("lastSeenAt").ValueKind);

        // 4. 해제 → 204, 목록이 비어 있다.
        var revoke = await client.DeleteAsync($"{DevicesUrl}/{deviceId}");
        Assert.Equal(HttpStatusCode.NoContent, revoke.StatusCode);

        var after = await client.GetFromJsonAsync<JsonElement>(DevicesUrl);
        Assert.Equal(0, after.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task Pair_SameCodeTwice_SecondReturns400()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var code = await TestApi.IssuePairingCodeAsync(client);

        var first = await TestApi.PairAsync(client, code, "PC-1");
        var second = await TestApi.PairAsync(client, code, "PC-2");

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        await AssertInvalidCodeAsync(second);
    }

    [Fact]
    public async Task IssueCode_WithoutToken_Returns401()
    {
        var anonymous = _factory.CreateClient();

        var response = await anonymous.PostAsync("/api/v1/me/agent-pairing-codes", content: null);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetDevices_ReturnsOnlyCallersActiveDevices_NewestFirst()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var first = await TestApi.PairDeviceAsync(client, "PC-1");
        var second = await TestApi.PairDeviceAsync(client, "PC-2");
        var revoked = await TestApi.PairDeviceAsync(client, "PC-3");
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"{DevicesUrl}/{revoked.DeviceId}")).StatusCode);

        var other = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(other);
        var otherDevice = await TestApi.PairDeviceAsync(other, "OTHER-PC");

        var mine = await GetDeviceIdsAsync(client);
        var theirs = await GetDeviceIdsAsync(other);

        // 본인 장치만, 해제된 장치 제외, 생성 시각 내림차순(최신 먼저).
        Assert.Equal(new[] { second.DeviceId, first.DeviceId }, mine);
        Assert.Equal(new[] { otherDevice.DeviceId }, theirs);
    }

    [Fact]
    public async Task Revoke_OtherUsersDevice_Returns403_AndKeepsDevice()
    {
        var owner = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(owner);
        var device = await TestApi.PairDeviceAsync(owner, "OWNER-PC");

        var intruder = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(intruder);

        var response = await intruder.DeleteAsync($"{DevicesUrl}/{device.DeviceId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(new[] { device.DeviceId }, await GetDeviceIdsAsync(owner));
    }

    [Fact]
    public async Task Revoke_UnknownDevice_Returns404()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var response = await client.DeleteAsync($"{DevicesUrl}/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Pair_WithInvalidCode_Returns400()
    {
        var anonymous = _factory.CreateClient();

        var response = await TestApi.PairAsync(anonymous, "ZZZZ-ZZZZ", "PC");

        await AssertInvalidCodeAsync(response);
    }

    [Fact]
    public async Task Pair_AcceptsLowercaseCodeWithoutHyphen()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var code = await TestApi.IssuePairingCodeAsync(client);

        var response = await TestApi.PairAsync(client, code.Replace("-", string.Empty).ToLowerInvariant(), "PC");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task IssueCode_Again_InvalidatesPreviousUnconsumedCode()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var oldCode = await TestApi.IssuePairingCodeAsync(client);
        var newCode = await TestApi.IssuePairingCodeAsync(client);

        var withOld = await TestApi.PairAsync(client, oldCode, "PC-OLD");
        var withNew = await TestApi.PairAsync(client, newCode, "PC-NEW");

        await AssertInvalidCodeAsync(withOld);
        Assert.Equal(HttpStatusCode.OK, withNew.StatusCode);
    }

    [Fact]
    public async Task Pair_WithExpiredCode_Returns400()
    {
        var client = _factory.CreateClient();
        var userId = await TestApi.RegisterAndLoginAsync(client);
        var code = await TestApi.IssuePairingCodeAsync(client);
        await ExpireCodesAsync(userId);

        var response = await TestApi.PairAsync(client, code, "PC");

        await AssertInvalidCodeAsync(response);
        Assert.Empty(await GetDeviceIdsAsync(client));
    }

    [Fact]
    public async Task Pair_ConcurrentRequestsWithSameCode_ExactlyOneSucceeds()
    {
        const int attempts = 5;
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var code = await TestApi.IssuePairingCodeAsync(client);

        var responses = await Task.WhenAll(Enumerable.Range(0, attempts)
            .Select(i => TestApi.PairAsync(client, code, $"PC-{i}")));

        Assert.Equal(1, responses.Count(r => r.StatusCode == HttpStatusCode.OK));
        Assert.Equal(attempts - 1, responses.Count(r => r.StatusCode == HttpStatusCode.BadRequest));
        Assert.Single(await GetDeviceIdsAsync(client));
    }

    /// <summary>코드가 없음·만료·사용됨·무효화됨이면 모두 같은 400 메시지여야 한다(11 §4.3, 추측 공격에 힌트 금지).</summary>
    private static async Task AssertInvalidCodeAsync(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(InvalidCodeMessage, problem.GetProperty("errors").GetProperty("code")[0].GetString());
    }

    private static async Task<Guid[]> GetDeviceIdsAsync(HttpClient client)
    {
        var list = await client.GetFromJsonAsync<JsonElement>(DevicesUrl);
        return list.GetProperty("items").EnumerateArray()
            .Select(item => item.GetProperty("deviceId").GetGuid())
            .ToArray();
    }

    /// <summary>시계를 조작할 수 없으므로 DB에서 사용자의 코드 만료 시각을 과거로 돌린다.</summary>
    private async Task ExpireCodesAsync(Guid userId)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var past = DateTime.UtcNow.AddMinutes(-1);

        var updated = await db.Set<AgentPairingCode>()
            .Where(c => c.UserId == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(c => c.ExpiresAt, past));

        Assert.Equal(1, updated);
    }
}
