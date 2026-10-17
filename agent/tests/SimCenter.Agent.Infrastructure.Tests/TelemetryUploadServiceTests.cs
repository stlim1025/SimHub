using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;
using SimCenter.Agent.Infrastructure.Outbox;
using SimCenter.Agent.Infrastructure.Upload;

namespace SimCenter.Agent.Infrastructure.Tests;

public sealed class TelemetryUploadServiceTests : IAsyncLifetime
{
    private const string ServerBaseUrl = "http://localhost:5284";
    private const int RecheckRounds = 3;
    private static readonly Uri HubUri = new("http://localhost:5284/hubs/telemetry");
    private static readonly DateTime OccurredAt = new(2026, 10, 17, 9, 0, 0, DateTimeKind.Utc);

    // 실제 주기(폴링 1초·키 재확인 10초)를 기다리지 않도록 짧은 주기를 주입한다.
    private static readonly TimeSpan FastInterval = TimeSpan.FromMilliseconds(20);

    // 주기 재확인을 사실상 끈다 — Changed 이벤트로만 깨어나는지 확인할 때 쓴다.
    private static readonly TimeSpan NoRecheck = TimeSpan.FromHours(1);

    private static readonly TimeSpan WaitTimeout = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan WaitStep = TimeSpan.FromMilliseconds(10);

    private readonly string _outboxPath =
        Path.Combine(Path.GetTempPath(), $"simcenter-upload-tests-{Guid.NewGuid():N}.db");

    private readonly FakeCredentialStore _credentials = new();
    private readonly FakeSessionFactory _factory = new();
    private readonly UploadStatusTracker _status = new();
    private readonly TelemetryOutbox _outbox;

    public TelemetryUploadServiceTests()
    {
        _outbox = new TelemetryOutbox(Options.Create(new AgentOptions { OutboxPath = _outboxPath }));
    }

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync()
    {
        await _outbox.DisposeAsync();
        SqliteConnection.ClearAllPools();

        // 일부러 엄격하게 지운다 — 업로더 종료(취소) 중 Outbox 연결이 새면 파일이 잠겨 여기서 실패한다(회귀 검출).
        File.Delete(_outboxPath);
    }

    [Fact]
    public async Task EmptyServerBaseUrl_StaysDisabled_NeverConnects()
    {
        _credentials.SetSilently("k");
        _status.Set(UploadState.Connecting); // 초기값과 구분되게 다른 상태에서 시작한다.
        var service = NewService(serverBaseUrl: "");

        await service.StartAsync(CancellationToken.None);
        await service.ExecuteTask!.WaitAsync(WaitTimeout); // 비활성이면 루프 없이 바로 끝난다.
        await service.StopAsync(CancellationToken.None);
        service.Dispose();

        Assert.Equal(UploadState.Disabled, _status.State);
        Assert.Empty(_factory.Sessions);
    }

    [Fact]
    public async Task NoKey_StaysUnpaired_ThenConnectsAfterKeySaved()
    {
        FakeSession? session = null;

        await RunAsync(NewService(keyRecheckInterval: NoRecheck), async () =>
        {
            await WaitForStateAsync(UploadState.Unpaired);
            Assert.Empty(_factory.Sessions);

            _credentials.Save("k");

            await WaitForStateAsync(UploadState.Connected);
            session = Assert.Single(_factory.Sessions);
            Assert.Equal(HubUri, session.HubUri);
            Assert.Equal("k", session.DeviceKey);
        });

        Assert.True(session!.IsDisposed); // 종료 시 세션을 정리한다.
    }

    [Fact]
    public async Task Ack_RemovesOutboxItem()
    {
        var eventId = await EnqueueAsync();
        _credentials.SetSilently("k");

        await RunAsync(NewService(), async () =>
        {
            await WaitUntilAsync(async () => await _outbox.CountAsync() == 0, "Ack 후 Outbox 항목 삭제");

            Assert.Contains(eventId, Assert.Single(_factory.Sessions).Submitted);
            Assert.Equal(UploadState.Connected, _status.State);
        });
    }

    [Fact]
    public async Task Reject_AlsoRemovesOutboxItem()
    {
        var eventId = await EnqueueAsync();
        _credentials.SetSilently("k");
        _factory.SubmitResponse = new SubmitResult(false, "Duplicate");

        await RunAsync(NewService(), async () =>
        {
            await WaitUntilAsync(async () => await _outbox.CountAsync() == 0, "Reject 후 Outbox 항목 삭제");

            Assert.Contains(eventId, Assert.Single(_factory.Sessions).Submitted);
        });
    }

    [Fact]
    public async Task Unauthorized_StopsUploading_AndKeepsOutboxItems()
    {
        var eventId = await EnqueueAsync();
        _credentials.SetSilently("revoked");
        _factory.StartFailure = key => key == "revoked" ? Http(HttpStatusCode.Unauthorized) : null;

        await RunAsync(NewService(), async () =>
        {
            await WaitForStateAsync(UploadState.Unauthorized);

            // 키 재확인이 여러 번 돌아도 거부된 키로는 다시 연결하지 않는다.
            await WaitForMoreLoadsAsync(RecheckRounds);
            var rejected = Assert.Single(_factory.Sessions);
            Assert.True(rejected.IsDisposed);
            Assert.Equal(1, rejected.StartCalls);
            Assert.Equal(1, await _outbox.CountAsync());
            Assert.Equal(UploadState.Unauthorized, _status.State);

            // 같은 키를 다시 저장해도(Changed) 재시도하지 않는다.
            _credentials.Save("revoked");
            await WaitForMoreLoadsAsync(1);
            Assert.Single(_factory.Sessions);

            // 다른 키가 저장되면 다시 연결해 보관된 항목을 보낸다.
            _credentials.Save("fresh");
            await WaitUntilAsync(async () => await _outbox.CountAsync() == 0, "새 키로 업로드");

            Assert.Equal(UploadState.Connected, _status.State);
            Assert.Equal(2, _factory.Sessions.Count);
            Assert.Equal("fresh", _factory.Sessions[1].DeviceKey);
            Assert.Contains(eventId, _factory.Sessions[1].Submitted);
        });
    }

    [Fact]
    public async Task KeySavedByAnotherProcess_IsPickedUpByPeriodicRecheck()
    {
        await RunAsync(NewService(), async () =>
        {
            await WaitForStateAsync(UploadState.Unpaired);

            // 다른 터미널의 `pair`가 저장 — 이 프로세스에는 Changed가 오지 않는다(R7).
            _credentials.SetSilently("k");

            await WaitForStateAsync(UploadState.Connected);
            Assert.Equal("k", Assert.Single(_factory.Sessions).DeviceKey);
        });
    }

    [Fact]
    public async Task RejectedKeyReplacedByAnotherProcess_ResumesViaPeriodicRecheck()
    {
        _credentials.SetSilently("revoked");
        _factory.StartFailure = key => key == "revoked" ? Http(HttpStatusCode.Unauthorized) : null;

        await RunAsync(NewService(), async () =>
        {
            await WaitForStateAsync(UploadState.Unauthorized);

            _credentials.SetSilently("fresh");

            await WaitForStateAsync(UploadState.Connected);
            Assert.Equal("fresh", _factory.Sessions[^1].DeviceKey);
        });
    }

    [Fact]
    public async Task KeyCleared_WhileConnected_DisposesSessionAndBecomesUnpaired()
    {
        _credentials.SetSilently("k");

        await RunAsync(NewService(keyRecheckInterval: NoRecheck), async () =>
        {
            await WaitForStateAsync(UploadState.Connected);

            _credentials.Clear();

            await WaitForStateAsync(UploadState.Unpaired);
            Assert.True(Assert.Single(_factory.Sessions).IsDisposed);
        });
    }

    [Fact]
    public async Task KeyReplaced_WhileConnected_ReconnectsWithNewKey()
    {
        _credentials.SetSilently("old");

        await RunAsync(NewService(keyRecheckInterval: NoRecheck), async () =>
        {
            await WaitForStateAsync(UploadState.Connected);

            _credentials.Save("new");

            await WaitUntilAsync(
                () => Task.FromResult(_factory.Sessions.Count == 2 && _status.State == UploadState.Connected),
                "새 키로 재연결");
            Assert.True(_factory.Sessions[0].IsDisposed);
            Assert.Equal("new", _factory.Sessions[1].DeviceKey);
        });
    }

    [Fact]
    public async Task TransientError_RetriesWithBackoff_ThenConnects()
    {
        var attempts = 0;
        _credentials.SetSilently("k");
        _factory.StartFailure = _ =>
            Interlocked.Increment(ref attempts) == 1 ? Http(HttpStatusCode.ServiceUnavailable) : null;

        await RunAsync(NewService(), async () =>
        {
            await WaitForStateAsync(UploadState.Connected);

            Assert.True(Assert.Single(_factory.Sessions).StartCalls >= 2);
        });
    }

    private TelemetryUploadService NewService(string serverBaseUrl = ServerBaseUrl, TimeSpan? keyRecheckInterval = null)
        => new(
            Options.Create(new AgentOptions { ServerBaseUrl = serverBaseUrl, OutboxPath = _outboxPath }),
            _outbox,
            _credentials,
            _factory,
            _status,
            NullLogger<TelemetryUploadService>.Instance,
            pollInterval: FastInterval,
            keyRecheckInterval: keyRecheckInterval ?? FastInterval);

    private static async Task RunAsync(TelemetryUploadService service, Func<Task> scenario)
    {
        await service.StartAsync(CancellationToken.None);
        try
        {
            await scenario();
        }
        finally
        {
            await service.StopAsync(CancellationToken.None);
            service.Dispose();
        }
    }

    private async Task<Guid> EnqueueAsync()
    {
        var eventId = Guid.NewGuid();
        await _outbox.EnqueueAsync(eventId, OccurredAt, $$"""{"eventId":"{{eventId}}","gameCode":"F1_25"}""");
        return eventId;
    }

    private Task WaitForStateAsync(UploadState expected)
        => WaitUntilAsync(() => Task.FromResult(_status.State == expected), $"상태 {expected}");

    private Task WaitForMoreLoadsAsync(int rounds)
    {
        var target = _credentials.LoadCount + rounds;
        return WaitUntilAsync(() => Task.FromResult(_credentials.LoadCount >= target), $"키 재확인 {rounds}회");
    }

    private static async Task WaitUntilAsync(Func<Task<bool>> condition, string what)
    {
        var elapsed = Stopwatch.StartNew();
        while (!await condition())
        {
            if (elapsed.Elapsed > WaitTimeout)
            {
                Assert.Fail($"시간 초과: {what}");
            }

            await Task.Delay(WaitStep);
        }
    }

    private static HttpRequestException Http(HttpStatusCode status)
        => new("Response status code does not indicate success.", inner: null, statusCode: status);

    /// <summary>메모리 키 저장소. <see cref="SetSilently"/>는 다른 프로세스가 파일을 바꾼 상황(Changed 없음)을 흉내 낸다.</summary>
    private sealed class FakeCredentialStore : IDeviceCredentialStore
    {
        private readonly object _gate = new();
        private string? _key;
        private int _loadCount;

        public event EventHandler? Changed;

        public int LoadCount => Volatile.Read(ref _loadCount);

        public string? Load()
        {
            Interlocked.Increment(ref _loadCount);
            lock (_gate)
            {
                return _key;
            }
        }

        public void Save(string deviceKey)
        {
            SetSilently(deviceKey);
            Changed?.Invoke(this, EventArgs.Empty);
        }

        public void Clear()
        {
            SetSilently(null);
            Changed?.Invoke(this, EventArgs.Empty);
        }

        public void SetSilently(string? deviceKey)
        {
            lock (_gate)
            {
                _key = deviceKey;
            }
        }
    }

    private sealed class FakeSessionFactory : ITelemetryHubSessionFactory
    {
        private readonly ConcurrentQueue<FakeSession> _sessions = new();

        /// <summary>장치 키별 StartAsync 실패(예외). null이면 연결 성공.</summary>
        public Func<string, Exception?> StartFailure { get; set; } = _ => null;

        public SubmitResult SubmitResponse { get; set; } = new(true, null);

        public IReadOnlyList<FakeSession> Sessions => _sessions.ToArray();

        public ITelemetryHubSession Create(Uri hubUri, string deviceKey)
        {
            var session = new FakeSession(hubUri, deviceKey, this);
            _sessions.Enqueue(session);
            return session;
        }
    }

    private sealed class FakeSession(Uri hubUri, string deviceKey, FakeSessionFactory factory) : ITelemetryHubSession
    {
        private readonly ConcurrentQueue<Guid> _submitted = new();
        private volatile bool _connected;
        private volatile bool _disposed;
        private int _startCalls;

        public Uri HubUri { get; } = hubUri;

        public string DeviceKey { get; } = deviceKey;

        public bool IsConnected => _connected;

        public bool IsDisposed => _disposed;

        public int StartCalls => Volatile.Read(ref _startCalls);

        public IReadOnlyCollection<Guid> Submitted => _submitted.ToArray();

        public Task StartAsync(CancellationToken ct)
        {
            Interlocked.Increment(ref _startCalls);
            var failure = factory.StartFailure(DeviceKey);
            if (failure is not null)
            {
                return Task.FromException(failure);
            }

            _connected = true;
            return Task.CompletedTask;
        }

        public Task<SubmitResult> SubmitAsync(JsonElement envelope, CancellationToken ct)
        {
            _submitted.Enqueue(envelope.GetProperty("eventId").GetGuid());
            return Task.FromResult(factory.SubmitResponse);
        }

        public ValueTask DisposeAsync()
        {
            _connected = false;
            _disposed = true;
            return ValueTask.CompletedTask;
        }
    }
}
