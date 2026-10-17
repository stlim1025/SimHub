using System.Text.Json;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Core.Abstractions;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;
using SimCenter.Agent.Infrastructure.Outbox;

namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// Outbox를 TelemetryHub로 배수(drain)하는 백그라운드 서비스(docs/06 §5, docs/11 §6.4, docs/13).
/// 연결된 장치 키로 업로드하고, 키가 없으면(미연결) 기다린다. 서버가 키를 거부(401)하면 무한 재시도를 멈추고
/// 다른 키가 저장될 때까지 업로드하지 않는다(Outbox는 그대로). 그 밖의 오류는 지수 백오프(최대 30초)로 재시도한다.
/// 서버가 응답(Ack/Reject)하면 Outbox에서 제거하고, 응답 없음(장애)이면 보관 후 재시도한다.
/// 단, 열린 연결 중에 장치가 해제돼 받은 Reject(<see cref="RevokedDeviceRejectReason"/>)는 401과 같이 다룬다 —
/// 그 항목을 지우지 않고 업로드를 멈춘 뒤 다른 키를 기다린다(Ruling R9).
/// 서버가 받고도 처리하지 못한 항목(<see cref="TelemetryHubServerException"/>)이 <see cref="ItemDeferThreshold"/>번 되풀이되면
/// 그 항목만 미루고 뒤 항목을 먼저 보낸다(D-35). 연결 문제는 세지 않는다(D-36). 읽을 수 없는 payload는 dead-letter로 옮긴다(D-37).
/// </summary>
public sealed class TelemetryUploadService : BackgroundService
{
    /// <summary>
    /// 서버가 "연결 해제된 장치"로 Reject할 때의 사유 문구. 백엔드 <c>TelemetryIngestService.RevokedDeviceReason</c>
    /// (계획 Global Constraints의 고정 문구)와 <b>정확히 같아야 한다</b>. 서버 문구가 바뀌면 이 Reject가 일반 Reject로
    /// 취급되어 항목이 지워지므로, 바꿀 때는 양쪽을 함께 바꾼다.
    /// </summary>
    internal const string RevokedDeviceRejectReason = "연결이 해제된 장치입니다.";

    /// <summary>같은 항목에 서버 오류가 이만큼 나면 그 항목만 미룬다(docs/13 §3.2). 그 전에는 순서를 지켜 같은 항목을 다시 보낸다.</summary>
    internal const int ItemDeferThreshold = 5;

    /// <summary>미룬 항목의 첫 재시도 간격. 다시 실패할 때마다 두 배가 된다(최대 <see cref="ItemRetryMaxDelay"/>).</summary>
    internal static readonly TimeSpan ItemRetryBaseDelay = TimeSpan.FromSeconds(30);

    /// <summary>미룬 항목의 최대 재시도 간격 — 서버가 고쳐지면 늦어도 이만큼 안에 올라간다.</summary>
    internal static readonly TimeSpan ItemRetryMaxDelay = TimeSpan.FromMinutes(5);

    /// <summary>한 번에 Outbox에서 읽는 항목 수(미뤄 둔 항목 수만큼 더 읽는다).</summary>
    internal const int DefaultBatchSize = 50;

    // RejectKeyAsync 로그에 남기는 거부 원인(키 원문은 남기지 않는다).
    private const string UnauthorizedCause = "401";
    private const string RevokedDeviceCause = "연결 해제 Reject";

    private static readonly TimeSpan DefaultPollInterval = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan DefaultMaxBackoff = TimeSpan.FromSeconds(30);

    // 다른 프로세스(예: 다른 터미널의 `pair`)가 키를 저장하면 이 프로세스에는 Changed가 오지 않으므로,
    // 미연결·401 대기 중에는 이 주기로 키를 다시 읽는다(R7).
    private static readonly TimeSpan KeyRecheckInterval = TimeSpan.FromSeconds(10);

    private const int BackoffMultiplier = 2;

    private readonly AgentOptions _options;
    private readonly TelemetryOutbox _outbox;
    private readonly IDeviceCredentialStore _credentials;
    private readonly ITelemetryHubSessionFactory _sessionFactory;
    private readonly UploadStatusTracker _status;
    private readonly IClock _clock;
    private readonly ILogger<TelemetryUploadService> _logger;
    private readonly TimeSpan _pollInterval;
    private readonly TimeSpan _keyRecheckInterval;
    private readonly TimeSpan _maxBackoff;
    private readonly int _batchSize;

    // Changed 알림(최대 1개 보관). 대기 중인 루프를 바로 깨운다.
    private readonly SemaphoreSlim _keyChangedSignal = new(0, 1);
    private readonly object _signalGate = new();

    // 아래 필드는 업로드 루프 스레드만 읽고 쓴다.
    private readonly ServerFailureTracker _serverFailures = new(ItemDeferThreshold, ItemRetryBaseDelay, ItemRetryMaxDelay);
    private ITelemetryHubSession? _session;
    private string? _sessionKey;
    private string? _rejectedKey;
    private bool _unpairedWarned;

    public TelemetryUploadService(
        IOptions<AgentOptions> options,
        TelemetryOutbox outbox,
        IDeviceCredentialStore credentials,
        ITelemetryHubSessionFactory sessionFactory,
        UploadStatusTracker status,
        IClock clock,
        ILogger<TelemetryUploadService> logger)
        : this(options, outbox, credentials, sessionFactory, status, clock, logger,
            DefaultPollInterval, KeyRecheckInterval, DefaultMaxBackoff, DefaultBatchSize)
    {
    }

    /// <summary>테스트용 — 폴링·키 재확인 주기와 최대 백오프를 짧게, 묶음 크기를 작게 주입한다.</summary>
    internal TelemetryUploadService(
        IOptions<AgentOptions> options,
        TelemetryOutbox outbox,
        IDeviceCredentialStore credentials,
        ITelemetryHubSessionFactory sessionFactory,
        UploadStatusTracker status,
        IClock clock,
        ILogger<TelemetryUploadService> logger,
        TimeSpan pollInterval,
        TimeSpan keyRecheckInterval,
        TimeSpan maxBackoff,
        int batchSize)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(pollInterval, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(keyRecheckInterval, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfLessThan(maxBackoff, pollInterval);
        ArgumentOutOfRangeException.ThrowIfLessThan(batchSize, 1);

        _options = options.Value;
        _outbox = outbox ?? throw new ArgumentNullException(nameof(outbox));
        _credentials = credentials ?? throw new ArgumentNullException(nameof(credentials));
        _sessionFactory = sessionFactory ?? throw new ArgumentNullException(nameof(sessionFactory));
        _status = status ?? throw new ArgumentNullException(nameof(status));
        _clock = clock ?? throw new ArgumentNullException(nameof(clock));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _pollInterval = pollInterval;
        _keyRecheckInterval = keyRecheckInterval;
        _maxBackoff = maxBackoff;
        _batchSize = batchSize;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // 이전 실행에서 옮긴 항목도 보이게 업로드가 꺼져 있어도 먼저 읽는다.
        await RefreshDeadLetterCountAsync(stoppingToken);

        var hubUri = ResolveHubUri();
        if (hubUri is null)
        {
            _status.Set(UploadState.Disabled);
            return;
        }

        _credentials.Changed += OnCredentialsChanged;
        try
        {
            await RunAsync(hubUri, stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // 종료 중 — 정상.
        }
        finally
        {
            _credentials.Changed -= OnCredentialsChanged;
            await DisposeSessionAsync();
        }
    }

    public override void Dispose()
    {
        _keyChangedSignal.Dispose();
        base.Dispose();
    }

    private Uri? ResolveHubUri()
    {
        if (string.IsNullOrWhiteSpace(_options.ServerBaseUrl))
        {
            _logger.LogWarning("ServerBaseUrl 미설정 — 업로드 비활성(이벤트는 Outbox에 계속 적재됨).");
            return null;
        }

        try
        {
            return AgentEndpoints.TelemetryHubUri(_options.ServerBaseUrl);
        }
        catch (ArgumentException ex)
        {
            _logger.LogError(ex, "ServerBaseUrl 형식 오류 — 업로드 비활성. ServerBaseUrl={ServerBaseUrl}", _options.ServerBaseUrl);
            return null;
        }
    }

    private async Task RunAsync(Uri hubUri, CancellationToken ct)
    {
        var backoff = _pollInterval;

        while (!ct.IsCancellationRequested)
        {
            var key = await AcquireUsableKeyAsync(ct);
            if (key is null)
            {
                continue;
            }

            try
            {
                var session = await EnsureConnectedAsync(hubUri, key, ct);
                var outcome = await DrainAsync(session, ct);
                if (outcome == DrainOutcome.ServerError)
                {
                    // 연결은 살아 있지만 서버가 항목을 처리하지 못했다 — 서버가 아플 수 있으니 몰아 보내지 않고 백오프로 쉰다(docs/13 §3.2).
                    await Task.Delay(backoff, ct);
                    backoff = NextBackoff(backoff);
                    continue;
                }

                backoff = _pollInterval;

                if (outcome == DrainOutcome.DeviceRevoked)
                {
                    await RejectKeyAsync(key, RevokedDeviceCause);
                }
                else if (outcome == DrainOutcome.Idle)
                {
                    await Task.Delay(_pollInterval, ct);
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex) when (UnauthorizedDetector.IsUnauthorized(ex))
            {
                await RejectKeyAsync(key, UnauthorizedCause);
            }
            catch (Exception ex)
            {
                // 연결 실패·전송 중 끊김 — 항목의 서버 오류 기록에는 손대지 않고 같은 항목을 다시 보낸다(D-36).
                _status.Set(_session?.IsConnected == true ? UploadState.Connected : UploadState.Connecting);
                _logger.LogWarning(ex, "업로드 실패 — {Seconds}s 후 재시도", backoff.TotalSeconds);
                await Task.Delay(backoff, ct);
                backoff = NextBackoff(backoff);
            }
        }
    }

    /// <summary>
    /// 업로드에 쓸 키를 돌려준다. 키가 없거나 서버가 거부한 키면 상태를 바꾸고
    /// 키 변경(Changed 또는 주기 재확인)을 기다린 뒤 null을 돌려준다(호출자는 다시 시도).
    /// </summary>
    private async Task<string?> AcquireUsableKeyAsync(CancellationToken ct)
    {
        var key = _credentials.Load();
        if (string.IsNullOrWhiteSpace(key))
        {
            await DisposeSessionAsync();
            if (!_unpairedWarned)
            {
                _logger.LogWarning("계정 미연결 — pair <코드>로 연결하세요");
                _unpairedWarned = true;
            }

            _status.Set(UploadState.Unpaired);
            await WaitForKeyChangeAsync(ct);
            return null;
        }

        _unpairedWarned = false;

        if (string.Equals(key, _rejectedKey, StringComparison.Ordinal))
        {
            _status.Set(UploadState.Unauthorized);
            await WaitForKeyChangeAsync(ct);
            return null;
        }

        _rejectedKey = null;
        return key;
    }

    /// <summary>키에 맞는 세션을 준비하고, 끊겨 있으면 연결한다. 키가 바뀌었으면 기존 세션을 버리고 새로 만든다.</summary>
    private async Task<ITelemetryHubSession> EnsureConnectedAsync(Uri hubUri, string key, CancellationToken ct)
    {
        if (_session is not null && !string.Equals(_sessionKey, key, StringComparison.Ordinal))
        {
            _logger.LogInformation("장치 키가 바뀌어 TelemetryHub에 다시 연결합니다.");
            await DisposeSessionAsync();
        }

        if (_session is null)
        {
            _session = _sessionFactory.Create(hubUri, key);
            _sessionKey = key;
        }

        if (!_session.IsConnected)
        {
            _status.Set(UploadState.Connecting);
            await _session.StartAsync(ct);
            if (_session.IsConnected)
            {
                _logger.LogInformation("TelemetryHub 연결됨: {Url}", hubUri);
            }
        }

        _status.Set(_session.IsConnected ? UploadState.Connected : UploadState.Connecting);
        return _session;
    }

    /// <summary>
    /// Outbox 항목을 한 묶음 보낸다. 미뤄 둔 항목은 다시 보낼 시각까지 건너뛴다(docs/13 §3.2).
    /// 서버 응답(Ack/Reject)이 오면 Ack/Reject 무관하게 Outbox에서 제거하고, 서버 오류면 그 항목의 실패를 기록하고 멈춘다(호출자가 백오프).
    /// 연결 문제 예외는 그대로 올라가 같은 항목을 다시 보낸다. 연결 해제 Reject는 그 항목을 남기고 즉시 멈춘다.
    /// </summary>
    private async Task<DrainOutcome> DrainAsync(ITelemetryHubSession session, CancellationToken ct)
    {
        // 미뤄 둔 항목이 묶음을 다 차지해 새 항목이 조회되지 않는 일이 없도록 기록 수만큼 더 읽는다.
        var pending = await _outbox.GetPendingAsync(_batchSize + _serverFailures.TrackedCount, ct);
        var handledAny = false;

        foreach (var item in pending)
        {
            if (_serverFailures.IsDeferred(item.EventId, _clock.UtcNow))
            {
                continue;
            }

            handledAny = true;
            var outcome = await SendItemAsync(session, item, ct);
            if (outcome == ItemOutcome.DeviceRevoked)
            {
                return DrainOutcome.DeviceRevoked;
            }

            if (outcome == ItemOutcome.ServerError)
            {
                return DrainOutcome.ServerError;
            }
        }

        // 보낼 항목이 없거나 전부 미뤄 둔 항목이면 폴링 주기만큼 쉬었다가 다시 읽는다(새 항목·재시도 시각 확인).
        return handledAny ? DrainOutcome.Sent : DrainOutcome.Idle;
    }

    /// <summary>항목 하나를 보낸다. payload를 읽을 수 없으면 보내지 않고 dead-letter로 옮긴다.</summary>
    private async Task<ItemOutcome> SendItemAsync(ITelemetryHubSession session, OutboxItem item, CancellationToken ct)
    {
        if (!TryReadEnvelope(item, out var envelope, out var readError))
        {
            await MoveToDeadLetterAsync(item, readError, ct);
            return ItemOutcome.Handled;
        }

        SubmitResult result;
        try
        {
            result = await session.SubmitAsync(envelope, ct);
        }
        catch (TelemetryHubServerException ex)
        {
            RecordServerFailure(item, ex);
            return ItemOutcome.ServerError;
        }

        if (IsDeviceRevoked(result))
        {
            // 장치 키가 더는 유효하지 않다 — 이 항목과 남은 항목은 다른 키로 다시 연결한 뒤 보낸다.
            _logger.LogWarning("서버가 연결 해제된 장치로 Reject했습니다 eventId={EventId} — Outbox에 보관합니다.", item.EventId);
            return ItemOutcome.DeviceRevoked;
        }

        await _outbox.DeleteAsync(item.EventId, ct);
        ForgetServerFailure(item.EventId);

        if (!result.Acknowledged)
        {
            _logger.LogWarning("서버 Reject eventId={EventId} reason={Reason}", item.EventId, result.RejectReason);
        }

        return ItemOutcome.Handled;
    }

    /// <summary>payload를 봉투로 읽는다. 손상돼 JSON이 아니면 false와 사유를 돌려준다(다시 읽어도 바뀌지 않는다).</summary>
    private static bool TryReadEnvelope(OutboxItem item, out JsonElement envelope, out string error)
    {
        try
        {
            using var document = JsonDocument.Parse(item.PayloadJson);
            envelope = document.RootElement.Clone();
            error = string.Empty;
            return true;
        }
        catch (JsonException ex)
        {
            envelope = default;
            error = $"payload JSON 파싱 실패: {ex.Message}";
            return false;
        }
    }

    private async Task MoveToDeadLetterAsync(OutboxItem item, string reason, CancellationToken ct)
    {
        bool moved;
        try
        {
            moved = await _outbox.MoveToDeadLetterAsync(item.EventId, reason, _clock.UtcNow, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // 위로 올라가면 연결 문제처럼 기록되므로 여기서 원인을 남긴다. 항목은 Outbox에 그대로 있어 다음 시도에서 다시 옮긴다.
            _logger.LogError(ex, "Outbox 항목을 dead-letter로 옮기지 못했습니다 eventId={EventId}", item.EventId);
            throw;
        }

        if (moved)
        {
            _logger.LogError(
                "읽을 수 없는 Outbox 항목을 dead-letter로 옮겼습니다 eventId={EventId} reason={Reason} — 뒤 항목을 계속 보냅니다.",
                item.EventId, reason);
        }

        await RefreshDeadLetterCountAsync(ct);
    }

    /// <summary>dead-letter 건수를 다시 읽어 상태에 반영한다. 표시용이라 실패해도 업로드는 계속한다.</summary>
    private async Task RefreshDeadLetterCountAsync(CancellationToken ct)
    {
        try
        {
            _status.SetDeadLetterCount(await _outbox.CountDeadLettersAsync(ct));
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "dead-letter 건수를 읽지 못했습니다");
        }
    }

    /// <summary>서버 오류 1회를 기록한다. 기준 횟수에 이르면 그 항목은 미뤄지고 뒤 항목이 먼저 간다.</summary>
    private void RecordServerFailure(OutboxItem item, TelemetryHubServerException ex)
    {
        // 서버 문구만 남긴다(스택은 같은 내용이 반복될 뿐이다).
        var failure = _serverFailures.RecordFailure(item.EventId, _clock.UtcNow);
        if (failure.RetryAt is { } retryAt)
        {
            _logger.LogWarning(
                "서버가 이벤트를 {Failures}번 처리하지 못했습니다 eventId={EventId} reason={Reason} — {RetryAt:O}까지 미루고 뒤 항목을 먼저 보냅니다.",
                failure.Failures, item.EventId, ex.Message, retryAt);
        }
        else
        {
            _logger.LogWarning(
                "서버가 이벤트를 처리하지 못했습니다({Failures}/{Threshold}) eventId={EventId} reason={Reason} — 같은 항목을 다시 보냅니다.",
                failure.Failures, ItemDeferThreshold, item.EventId, ex.Message);
        }

        _status.SetDeferredCount(_serverFailures.DeferredCount);
    }

    private void ForgetServerFailure(Guid eventId)
    {
        _serverFailures.Forget(eventId);
        _status.SetDeferredCount(_serverFailures.DeferredCount);
    }

    private static bool IsDeviceRevoked(SubmitResult result)
        => !result.Acknowledged && string.Equals(result.RejectReason, RevokedDeviceRejectReason, StringComparison.Ordinal);

    /// <summary>
    /// 401 또는 연결 해제 Reject — 세션을 버리고 이 키로는 다시 시도하지 않는다. Outbox는 건드리지 않는다.
    /// </summary>
    /// <param name="key">거부된 장치 키(로그에 남기지 않는다).</param>
    /// <param name="cause">로그용 거부 원인.</param>
    private async Task RejectKeyAsync(string key, string cause)
    {
        _logger.LogWarning(
            "TelemetryHub가 장치 키를 거부했습니다({Cause:l}) — 다시 연결이 필요합니다. 새 키가 저장될 때까지 업로드를 멈춥니다.",
            cause);
        await DisposeSessionAsync();
        _rejectedKey = key;
        _status.Set(UploadState.Unauthorized);
    }

    private async Task WaitForKeyChangeAsync(CancellationToken ct)
    {
        // 시간 초과(false)여도 상관없다 — 호출자가 키를 다시 읽는다.
        await _keyChangedSignal.WaitAsync(_keyRecheckInterval, ct);
    }

    private void OnCredentialsChanged(object? sender, EventArgs e)
    {
        // 확인과 해제를 묶어 최대치(1)를 넘기지 않는다. 여러 번 바뀌어도 한 번 깨우면 충분하다.
        lock (_signalGate)
        {
            if (_keyChangedSignal.CurrentCount == 0)
            {
                _keyChangedSignal.Release();
            }
        }
    }

    /// <summary>
    /// 세션을 버린다(키 변경·미연결·거부·종료). 서버 오류 기록도 그 키에 묶인 것이라 함께 비운다 —
    /// 키 A에서의 실패가 키 B로 이어지지 않게 한다(docs/13 §3.2). 연결 끊김은 세션을 버리지 않으므로 기록이 남는다.
    /// </summary>
    private async Task DisposeSessionAsync()
    {
        _serverFailures.Clear();
        _status.SetDeferredCount(0);

        var session = _session;
        _session = null;
        _sessionKey = null;
        if (session is null)
        {
            return;
        }

        try
        {
            await session.DisposeAsync();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "TelemetryHub 세션 정리 실패");
        }
    }

    private TimeSpan NextBackoff(TimeSpan current)
        => TimeSpan.FromTicks(Math.Min(_maxBackoff.Ticks, current.Ticks * BackoffMultiplier));

    /// <summary>한 번의 배수 결과.</summary>
    private enum DrainOutcome
    {
        /// <summary>보낼 항목이 없었거나 전부 미뤄 둔 항목이었다(폴링 주기만큼 쉰다).</summary>
        Idle,

        /// <summary>하나 이상 처리했다(바로 다음 묶음을 시도한다).</summary>
        Sent,

        /// <summary>서버가 항목을 처리하지 못했다(백오프로 쉰다).</summary>
        ServerError,

        /// <summary>서버가 연결 해제된 장치로 Reject했다(키 거부로 전환한다).</summary>
        DeviceRevoked,
    }

    /// <summary>항목 하나의 처리 결과.</summary>
    private enum ItemOutcome
    {
        /// <summary>서버가 답했거나(Ack/Reject) dead-letter로 옮겼다 — 다음 항목으로 간다.</summary>
        Handled,

        /// <summary>서버 오류 — 기록하고 묶음을 멈춘다.</summary>
        ServerError,

        /// <summary>연결 해제 Reject — 항목을 남기고 멈춘다.</summary>
        DeviceRevoked,
    }
}
