using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;
using SimCenter.Agent.Infrastructure.Pairing;

namespace SimCenter.Agent.Infrastructure.Tests;

public sealed class AgentPairingClientTests
{
    private const string ServerBaseUrl = "http://localhost:5284";
    private const string Code = "K7F2-9QXM";
    private const string DeviceName = "SIM-RIG-01";
    private const string DeviceKey = "dGVzdC1kZXZpY2Uta2V5LTAxMjM0NTY3ODlhYmNkZWY";
    private const string InvalidCodeMessage = "유효하지 않거나 만료된 코드입니다.";
    private const string TooManyRequestsMessage = "요청이 너무 많습니다. 잠시 후 다시 시도하세요.";

    private readonly InMemoryCredentialStore _store = new();

    [Fact]
    public async Task Pair_200_SavesKeyAndSucceeds()
    {
        var deviceId = Guid.NewGuid();
        var handler = new StubHandler(_ => Json(HttpStatusCode.OK, $$"""{"deviceId":"{{deviceId}}","deviceKey":"{{DeviceKey}}"}"""));

        var outcome = await NewClient(handler).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.True(outcome.Succeeded);
        Assert.Equal(DeviceKey, _store.Load());
        Assert.DoesNotContain(DeviceKey, outcome.Message);

        var request = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("/api/v1/agent/pair", request.Uri.AbsolutePath);
        using var body = JsonDocument.Parse(request.Body);
        Assert.Equal(Code, body.RootElement.GetProperty("code").GetString());
        Assert.Equal(DeviceName, body.RootElement.GetProperty("deviceName").GetString());
    }

    [Fact]
    public async Task Pair_400_DoesNotSave_ReturnsInvalidCodeMessage()
    {
        var handler = new StubHandler(_ => Json(
            HttpStatusCode.BadRequest,
            $$$"""{"status":400,"errors":{"code":["{{{InvalidCodeMessage}}}"]}}"""));

        var outcome = await NewClient(handler).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Equal(InvalidCodeMessage, outcome.Message);
        Assert.Null(_store.Load());
        Assert.Equal(0, _store.SaveCount);
    }

    [Fact]
    public async Task Pair_429_ReturnsTooManyRequestsMessage()
    {
        var handler = new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.TooManyRequests));

        var outcome = await NewClient(handler).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Equal(TooManyRequestsMessage, outcome.Message);
        Assert.Null(_store.Load());
    }

    [Fact]
    public async Task Pair_NetworkError_ReturnsUnreachableMessage()
    {
        var handler = new StubHandler(_ => throw new HttpRequestException("connection refused"));

        var outcome = await NewClient(handler).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.StartsWith("서버에 연결할 수 없습니다", outcome.Message);
        Assert.Null(_store.Load());
    }

    [Fact]
    public async Task Pair_RequestTimeout_ReturnsUnreachableMessage()
    {
        // HttpClient.Timeout 만료는 호출자 취소가 아닌 TaskCanceledException으로 나타난다.
        var handler = new StubHandler(_ => throw new TaskCanceledException("timeout"));

        var outcome = await NewClient(handler).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.StartsWith("서버에 연결할 수 없습니다", outcome.Message);
    }

    [Fact]
    public async Task Pair_CancelledByCaller_Throws()
    {
        using var cts = new CancellationTokenSource();
        var handler = new StubHandler(_ =>
        {
            cts.Cancel();
            throw new OperationCanceledException(cts.Token);
        });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => NewClient(handler).PairAsync(Code, DeviceName, cts.Token));

        Assert.Null(_store.Load());
    }

    [Fact]
    public async Task Pair_ServerError_ReturnsStatusMessage_DoesNotSave()
    {
        var handler = new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError));

        var outcome = await NewClient(handler).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Contains("500", outcome.Message);
        Assert.Null(_store.Load());
    }

    [Theory]
    [InlineData("""{"deviceId":"x"}""")]
    [InlineData("""{"deviceId":"x","deviceKey":""}""")]
    [InlineData("not json")]
    public async Task Pair_200_WithUnusableBody_DoesNotSave(string body)
    {
        var handler = new StubHandler(_ => Json(HttpStatusCode.OK, body));

        var outcome = await NewClient(handler).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Equal(0, _store.SaveCount);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("localhost:5284")]
    [InlineData("ftp://localhost:5284")]
    public async Task Pair_InvalidServerBaseUrl_Fails_WithoutRequest(string serverBaseUrl)
    {
        var handler = new StubHandler(_ => throw new InvalidOperationException("요청을 보내면 안 된다."));

        var outcome = await NewClient(handler, serverBaseUrl).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Contains("ServerBaseUrl", outcome.Message);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task Pair_BlankCode_Fails_WithoutRequest()
    {
        var handler = new StubHandler(_ => throw new InvalidOperationException("요청을 보내면 안 된다."));

        var outcome = await NewClient(handler).PairAsync("  ", DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Empty(handler.Requests);
    }

    [Theory]
    [MemberData(nameof(SaveFailures))]
    public async Task Pair_SaveFails_ReturnsFailure_WithoutLeakingKey(Exception saveFailure)
    {
        _store.SaveFailure = saveFailure;
        var handler = new StubHandler(_ => Json(HttpStatusCode.OK, $$"""{"deviceId":"x","deviceKey":"{{DeviceKey}}"}"""));

        var outcome = await NewClient(handler).PairAsync(Code, DeviceName, CancellationToken.None);

        Assert.False(outcome.Succeeded);
        Assert.Contains("저장", outcome.Message);
        Assert.DoesNotContain(DeviceKey, outcome.Message);
    }

    public static TheoryData<Exception> SaveFailures() => new()
    {
        new IOException("disk full"),
        new UnauthorizedAccessException("denied"),
        new CryptographicException("dpapi"),
    };

    private AgentPairingClient NewClient(StubHandler handler, string serverBaseUrl = ServerBaseUrl)
        => new(
            new HttpClient(handler),
            _store,
            Options.Create(new AgentOptions { ServerBaseUrl = serverBaseUrl }),
            NullLogger<AgentPairingClient>.Instance);

    private static HttpResponseMessage Json(HttpStatusCode status, string body)
        => new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    /// <summary>요청을 기록하고 미리 정한 응답(또는 예외)을 돌려주는 가짜 핸들러.</summary>
    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public List<RecordedRequest> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null ? string.Empty : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add(new RecordedRequest(request.Method, request.RequestUri!, body));
            return respond(request);
        }
    }

    private sealed record RecordedRequest(HttpMethod Method, Uri Uri, string Body);

    private sealed class InMemoryCredentialStore : IDeviceCredentialStore
    {
        private string? _key;

        public event EventHandler? Changed;

        public int SaveCount { get; private set; }

        public Exception? SaveFailure { get; set; }

        public string? Load() => _key;

        public void Save(string deviceKey)
        {
            if (SaveFailure is not null)
            {
                throw SaveFailure;
            }

            _key = deviceKey;
            SaveCount++;
            Changed?.Invoke(this, EventArgs.Empty);
        }

        public void Clear()
        {
            _key = null;
            Changed?.Invoke(this, EventArgs.Empty);
        }
    }
}
