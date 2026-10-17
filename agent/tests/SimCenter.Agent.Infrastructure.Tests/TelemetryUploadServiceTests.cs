using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Core.Abstractions;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;
using SimCenter.Agent.Infrastructure.Outbox;
using SimCenter.Agent.Infrastructure.Upload;

namespace SimCenter.Agent.Infrastructure.Tests;

public sealed class TelemetryUploadServiceTests : IAsyncLifetime
{
    private const string ServerBaseUrl = "http://localhost:5284";
    private const int RecheckRounds = 3;
    private const int DeferThreshold = TelemetryUploadService.ItemDeferThreshold;

    private const string ParseFailurePrefix = "payload JSON 파싱 실패: ";

    // 서버 계약(TelemetryIngestService.RevokedDeviceReason)과 같은 문구를 일부러 리터럴로 고정한다.
    private const string RevokedDeviceReason = "연결이 해제된 장치입니다.";

    private static readonly SubmitResult Acked = new(true, null);
    private static readonly Uri HubUri = new("http://localhost:5284/hubs/telemetry");
    private static readonly DateTime OccurredAt = new(2026, 10, 17, 9, 0, 0, DateTimeKind.Utc);

    // 실제 주기(폴링 1초·키 재확인 10초·최대 백오프 30초)를 기다리지 않도록 짧은 주기를 주입한다.
    private static readonly TimeSpan FastInterval = TimeSpan.FromMilliseconds(20);
    private static readonly TimeSpan FastMaxBackoff = TimeSpan.FromMilliseconds(40);

    // 주기 재확인을 사실상 끈다 — Changed 이벤트로만 깨어나는지 확인할 때 쓴다.
    private static readonly TimeSpan NoRecheck = TimeSpan.FromHours(1);

    private static readonly TimeSpan WaitTimeout = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan WaitStep = TimeSpan.FromMilliseconds(10);

    private readonly string _outboxPath =
        Path.Combine(Path.GetTempPath(), $"simcenter-upload-tests-{Guid.NewGuid():N}.db");

    private readonly FakeCredentialStore _credentials = new();
    private readonly FakeSessionFactory _factory = new();
    private readonly UploadStatusTracker _status = new();
    private readonly ManualClock _clock = new(new DateTime(2026, 10, 17, 10, 0, 0, DateTimeKind.Utc));
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
            await WaitForOutboxCountAsync(0, "Ack 후 Outbox 항목 삭제");

            Assert.Contains(eventId, Assert.Single(_factory.Sessions).Submitted);
            Assert.Equal(UploadState.Connected, _status.State);
        });
    }

    [Fact]
    public async Task Reject_AlsoRemovesOutboxItem()
    {
        var eventId = await EnqueueAsync();
        _credentials.SetSilently("k");
        _factory.SubmitResponse = _ => new SubmitResult(false, "Duplicate");

        await RunAsync(NewService(), async () =>
        {
            await WaitForOutboxCountAsync(0, "Reject 후 Outbox 항목 삭제");

            Assert.Contains(eventId, Assert.Single(_factory.Sessions).Submitted);
            Assert.Equal(UploadState.Connected, _status.State); // 일반 Reject는 연결 상태를 바꾸지 않는다.
        });
    }

    [Fact]
    public async Task RevokedReject_KeepsItem_AndBecomesUnauthorized()
    {
        var first = await EnqueueAsync();
        var second = await EnqueueAsync();
        _credentials.SetSilently("revoked");
        _factory.SubmitResponse = key => key == "revoked" ? new SubmitResult(false, RevokedDeviceReason) : Acked;

        await RunAsync(NewService(), async () =>
        {
            await WaitForStateAsync(UploadState.Unauthorized);

            // 키 재확인이 여러 번 돌아도 해제된 장치의 키로는 더 보내지 않는다.
            await WaitForMoreLoadsAsync(RecheckRounds);
            var revoked = Assert.Single(_factory.Sessions);
            Assert.True(revoked.IsDisposed);
            Assert.Equal(new[] { first }, revoked.Submitted); // 첫 Reject에서 멈춰 두 번째 항목은 보내지 않는다.
            Assert.Equal(2, await _outbox.CountAsync()); // Reject된 항목도 Outbox에 남는다.
            Assert.Equal(UploadState.Unauthorized, _status.State);

            // 다른 키가 저장되면 다시 연결해 보관된 항목을 모두 보낸다.
            _credentials.Save("fresh");
            await WaitForOutboxCountAsync(0, "새 키로 업로드");

            Assert.Equal(UploadState.Connected, _status.State);
            Assert.Equal(2, _factory.Sessions.Count);
            Assert.Equal("fresh", _factory.Sessions[1].DeviceKey);
            Assert.Equal(new[] { first, second }, _factory.Sessions[1].Submitted);
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
            await WaitForOutboxCountAsync(0, "새 키로 업로드");

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

    [Fact]
    public async Task ServerErrorOnOneItem_DefersOnlyThatItem_AndLaterItemsGoFirst()
    {
        var poison = await EnqueueAsync();
        var second = await EnqueueAsync();
        var third = await EnqueueAsync();
        var serverFixed = false;
        _credentials.SetSilently("k");
        _factory.SubmitFailure = (_, id) => id == poison && !Volatile.Read(ref serverFixed) ? ServerError() : null;

        await RunAsync(NewService(), async () =>
        {
            await WaitForOutboxCountAsync(1, "독성 항목 뒤 항목 전송");
            var session = Assert.Single(_factory.Sessions);

            // 5번 실패한 뒤 미뤄지고, 뒤 항목이 먼저 간다.
            Assert.Equal(Enumerable.Repeat(poison, DeferThreshold).Append(second).Append(third), session.Submitted);
            Assert.Equal(1, _status.DeferredCount);
            Assert.Equal(0, _status.DeadLetterCount);
            Assert.Equal(UploadState.Connected, _status.State);

            // 시각이 되기 전에는 다시 보내지 않는다.
            await WaitForMoreLoadsAsync(RecheckRounds);
            Assert.Equal(DeferThreshold, session.Submitted.Count(id => id == poison));

            // 시각이 되면 다시 시도한다(아직 실패 → 다시 미룸).
            _clock.Advance(TelemetryUploadService.ItemRetryBaseDelay);
            await WaitUntilAsync(
                () => Task.FromResult(session.Submitted.Count(id => id == poison) == DeferThreshold + 1), "미룬 항목 재시도");
            Assert.Equal(1, await _outbox.CountAsync());

            // 서버가 고쳐지면 다음 시도에서 올라간다. 격리된 항목은 없다.
            Volatile.Write(ref serverFixed, true);
            _clock.Advance(TelemetryUploadService.ItemRetryMaxDelay);
            await WaitForOutboxCountAsync(0, "고쳐진 뒤 전송");
            await WaitUntilAsync(() => Task.FromResult(_status.DeferredCount == 0), "미룬 건수 0");
            Assert.Equal(0, await _outbox.CountDeadLettersAsync());
        });
    }

    [Fact]
    public async Task DeferredItemsFillingTheBatch_DoNotHideLaterItems()
    {
        const int SmallBatch = 2;
        var poisons = new[] { await EnqueueAsync(), await EnqueueAsync() };
        var good = await EnqueueAsync();
        _credentials.SetSilently("k");
        _factory.SubmitFailure = (_, id) => poisons.Contains(id) ? ServerError() : null;

        await RunAsync(NewService(batchSize: SmallBatch), async () =>
        {
            // 미룬 항목이 묶음 크기만큼 앞에 있어도 기록 수만큼 더 읽어 뒤 항목을 보낸다.
            await WaitForOutboxCountAsync(poisons.Length, "미룬 항목 뒤의 정상 항목 전송");

            Assert.Contains(good, Assert.Single(_factory.Sessions).Submitted);
            Assert.Equal(poisons.Length, _status.DeferredCount);
        });
    }

    [Fact]
    public async Task ServerErrorOnEveryItem_LosesNothing_AndDeliversAllAfterRecovery()
    {
        var items = new[] { await EnqueueAsync(), await EnqueueAsync(), await EnqueueAsync() };
        var serverDown = true;
        _credentials.SetSilently("k");
        _factory.SubmitFailure = (_, _) => Volatile.Read(ref serverDown) ? ServerError() : null;

        await RunAsync(NewService(), async () =>
        {
            // 서버 전체 장애: 항목마다 5번 실패해 모두 미뤄지지만 아무것도 잃거나 격리되지 않는다.
            await WaitUntilAsync(() => Task.FromResult(_status.DeferredCount == items.Length), "모든 항목 미룸");
            Assert.Equal(items.Length, await _outbox.CountAsync());
            Assert.Equal(0, await _outbox.CountDeadLettersAsync());
            Assert.Equal(0, _status.DeadLetterCount);

            // 복구되면 미룬 시각이 지난 뒤 전부 올라간다.
            Volatile.Write(ref serverDown, false);
            _clock.Advance(TelemetryUploadService.ItemRetryMaxDelay);
            await WaitForOutboxCountAsync(0, "복구 후 전부 전송");

            var session = Assert.Single(_factory.Sessions);
            Assert.All(items, id => Assert.Equal(DeferThreshold + 1, session.Submitted.Count(sent => sent == id)));
            await WaitUntilAsync(() => Task.FromResult(_status.DeferredCount == 0), "미룬 건수 0");
        });
    }

    [Fact]
    public async Task ConnectionDropDuringSubmit_IsNotCounted_AndKeepsOrder()
    {
        const int Drops = DeferThreshold * 2;
        var first = await EnqueueAsync();
        var second = await EnqueueAsync();
        var drops = 0;
        _credentials.SetSilently("k");
        _factory.SubmitFailure = (_, id) =>
            id == first && Interlocked.Increment(ref drops) <= Drops ? new IOException("연결이 끊겼습니다.") : null;

        await RunAsync(NewService(), async () =>
        {
            await WaitForOutboxCountAsync(0, "복구 후 순서대로 전송");

            // 끊김은 서버 오류가 아니다 — 기준 횟수를 넘겨도 미루지 않고, 뒤 항목을 먼저 보내지 않는다.
            var session = Assert.Single(_factory.Sessions);
            Assert.Equal(Enumerable.Repeat(first, Drops + 1).Append(second), session.Submitted);
            Assert.True(session.StartCalls > Drops); // 끊길 때마다 다시 연결했다.
            Assert.Equal(0, _status.DeferredCount);
            Assert.Equal(0, _status.DeadLetterCount);
            Assert.Equal(0, await _outbox.CountDeadLettersAsync());
        });
    }

    [Fact]
    public async Task CorruptPayload_IsDeadLetteredAtOnce_AndLaterItemsFlow()
    {
        var corrupt = Guid.NewGuid();
        await _outbox.EnqueueAsync(corrupt, OccurredAt, "{not json");
        var next = await EnqueueAsync();
        _credentials.SetSilently("k");

        await RunAsync(NewService(), async () =>
        {
            await WaitForOutboxCountAsync(0, "손상 항목 이동 후 뒤 항목 전송");
            await WaitUntilAsync(() => Task.FromResult(_status.DeadLetterCount == 1), "dead-letter 건수 표시");

            Assert.Equal(new[] { next }, Assert.Single(_factory.Sessions).Submitted); // 손상 항목은 보내지 않는다.
            var deadLetter = Assert.Single(await _outbox.GetDeadLettersAsync(10));
            Assert.Equal(corrupt, deadLetter.EventId);
            Assert.Equal("{not json", deadLetter.PayloadJson);
            Assert.StartsWith(ParseFailurePrefix, deadLetter.Reason);
            Assert.True(deadLetter.Reason.Length > ParseFailurePrefix.Length, "파서 메시지가 사유에 붙어야 한다");
            Assert.Equal(_clock.UtcNow, deadLetter.DeadLetteredAt);
        });
    }

    [Fact]
    public async Task KeyChange_ClearsDeferral_AndRetriesWithNewKeyAtOnce()
    {
        var item = await EnqueueAsync();
        _credentials.SetSilently("old");
        _factory.SubmitFailure = (key, _) => key == "old" ? ServerError() : null;

        await RunAsync(NewService(keyRecheckInterval: NoRecheck), async () =>
        {
            await WaitUntilAsync(() => Task.FromResult(_status.DeferredCount == 1), "이전 키에서 미룸");

            _credentials.Save("new");

            // 시각을 움직이지 않아도 새 키로 바로 다시 보낸다.
            await WaitForOutboxCountAsync(0, "새 키로 전송");
            Assert.Equal(new[] { item }, _factory.Sessions[1].Submitted);
            Assert.Equal(0, _status.DeferredCount);
        });
    }

    [Fact]
    public async Task ExistingDeadLetters_AreShownOnStart_EvenWhenUploadIsDisabled()
    {
        var eventId = await EnqueueAsync();
        await _outbox.MoveToDeadLetterAsync(eventId, "이전 실행에서 옮김", OccurredAt);
        var service = NewService(serverBaseUrl: "");

        await service.StartAsync(CancellationToken.None);
        await service.ExecuteTask!.WaitAsync(WaitTimeout);
        await service.StopAsync(CancellationToken.None);
        service.Dispose();

        Assert.Equal(UploadState.Disabled, _status.State);
        Assert.Equal(1, _status.DeadLetterCount);
    }

    private TelemetryUploadService NewService(
        string serverBaseUrl = ServerBaseUrl, TimeSpan? keyRecheckInterval = null, int batchSize = TelemetryUploadService.DefaultBatchSize)
        => new(
            Options.Create(new AgentOptions { ServerBaseUrl = serverBaseUrl, OutboxPath = _outboxPath }),
            _outbox,
            _credentials,
            _factory,
            _status,
            _clock,
            NullLogger<TelemetryUploadService>.Instance,
            pollInterval: FastInterval,
            keyRecheckInterval: keyRecheckInterval ?? FastInterval,
            maxBackoff: FastMaxBackoff,
            batchSize: batchSize);

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

    private Task WaitForOutboxCountAsync(int expected, string what)
        => WaitUntilAsync(async () => await _outbox.CountAsync() == expected, what);

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

    private static TelemetryHubServerException ServerError()
        => new("An unexpected error occurred invoking 'SubmitEvent' on the server.");

    /// <summary>테스트가 직접 움직이는 시계(업로드 루프 스레드가 읽는다).</summary>
    private sealed class ManualClock(DateTime start) : IClock
    {
        private long _ticks = start.Ticks;

        public DateTime UtcNow => new(Interlocked.Read(ref _ticks), DateTimeKind.Utc);

        public void Advance(TimeSpan by) => Interlocked.Add(ref _ticks, by.Ticks);
    }

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

        /// <summary>장치 키별 SubmitAsync 응답. 기본은 Ack.</summary>
        public Func<string, SubmitResult> SubmitResponse { get; set; } = _ => Acked;

        /// <summary>
        /// (장치 키, eventId)별 SubmitAsync 실패. null이면 <see cref="SubmitResponse"/>로 답한다.
        /// <see cref="TelemetryHubServerException"/>이 아닌 예외는 전송 중 연결이 끊긴 것으로 보고 연결도 끊는다.
        /// </summary>
        public Func<string, Guid, Exception?> SubmitFailure { get; set; } = (_, _) => null;

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

        /// <summary>보낸 순서대로의 eventId(실패한 시도 포함).</summary>
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
            var eventId = envelope.GetProperty("eventId").GetGuid();
            _submitted.Enqueue(eventId);

            var failure = factory.SubmitFailure(DeviceKey, eventId);
            if (failure is null)
            {
                return Task.FromResult(factory.SubmitResponse(DeviceKey));
            }

            if (failure is not TelemetryHubServerException)
            {
                _connected = false;
            }

            return Task.FromException<SubmitResult>(failure);
        }

        public ValueTask DisposeAsync()
        {
            _connected = false;
            _disposed = true;
            return ValueTask.CompletedTask;
        }
    }
}
