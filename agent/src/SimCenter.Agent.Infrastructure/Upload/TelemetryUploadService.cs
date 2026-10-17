using System.Text.Json;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;
using SimCenter.Agent.Infrastructure.Outbox;

namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// Outbox를 TelemetryHub로 배수(drain)하는 백그라운드 서비스(docs/06 §5, docs/11 §6.4).
/// 연결된 장치 키로 업로드하고, 키가 없으면(미연결) 기다린다. 서버가 키를 거부(401)하면 무한 재시도를 멈추고
/// 다른 키가 저장될 때까지 업로드하지 않는다(Outbox는 그대로). 그 밖의 오류는 지수 백오프(최대 30초)로 재시도한다.
/// 서버가 응답(Ack/Reject)하면 Outbox에서 제거하고, 응답 없음(장애)이면 보관 후 재시도한다.
/// </summary>
public sealed class TelemetryUploadService : BackgroundService
{
    private static readonly TimeSpan DefaultPollInterval = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan MaxBackoff = TimeSpan.FromSeconds(30);

    // 다른 프로세스(예: 다른 터미널의 `pair`)가 키를 저장하면 이 프로세스에는 Changed가 오지 않으므로,
    // 미연결·401 대기 중에는 이 주기로 키를 다시 읽는다(R7).
    private static readonly TimeSpan KeyRecheckInterval = TimeSpan.FromSeconds(10);

    private const int BatchSize = 50;
    private const int BackoffMultiplier = 2;

    private readonly AgentOptions _options;
    private readonly TelemetryOutbox _outbox;
    private readonly IDeviceCredentialStore _credentials;
    private readonly ITelemetryHubSessionFactory _sessionFactory;
    private readonly UploadStatusTracker _status;
    private readonly ILogger<TelemetryUploadService> _logger;
    private readonly TimeSpan _pollInterval;
    private readonly TimeSpan _keyRecheckInterval;

    // Changed 알림(최대 1개 보관). 대기 중인 루프를 바로 깨운다.
    private readonly SemaphoreSlim _keyChangedSignal = new(0, 1);
    private readonly object _signalGate = new();

    // 아래 필드는 업로드 루프 스레드만 읽고 쓴다.
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
        ILogger<TelemetryUploadService> logger)
        : this(options, outbox, credentials, sessionFactory, status, logger, DefaultPollInterval, KeyRecheckInterval)
    {
    }

    /// <summary>테스트용 — 폴링·키 재확인 주기를 짧게 주입한다.</summary>
    internal TelemetryUploadService(
        IOptions<AgentOptions> options,
        TelemetryOutbox outbox,
        IDeviceCredentialStore credentials,
        ITelemetryHubSessionFactory sessionFactory,
        UploadStatusTracker status,
        ILogger<TelemetryUploadService> logger,
        TimeSpan pollInterval,
        TimeSpan keyRecheckInterval)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(pollInterval, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(keyRecheckInterval, TimeSpan.Zero);

        _options = options.Value;
        _outbox = outbox ?? throw new ArgumentNullException(nameof(outbox));
        _credentials = credentials ?? throw new ArgumentNullException(nameof(credentials));
        _sessionFactory = sessionFactory ?? throw new ArgumentNullException(nameof(sessionFactory));
        _status = status ?? throw new ArgumentNullException(nameof(status));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _pollInterval = pollInterval;
        _keyRecheckInterval = keyRecheckInterval;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
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
                var sentAny = await DrainAsync(session, ct);
                backoff = _pollInterval;

                if (!sentAny)
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
                await RejectKeyAsync(key);
            }
            catch (Exception ex)
            {
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

    /// <returns>하나 이상 전송하면 true(연속 배수 유도).</returns>
    private async Task<bool> DrainAsync(ITelemetryHubSession session, CancellationToken ct)
    {
        var pending = await _outbox.GetPendingAsync(BatchSize, ct);
        if (pending.Count == 0)
        {
            return false;
        }

        foreach (var item in pending)
        {
            using var document = JsonDocument.Parse(item.PayloadJson);

            // 서버 응답(반환값)이 오면 Ack/Reject 무관하게 Outbox에서 제거. 예외(장애)면 보관되어 재시도.
            var result = await session.SubmitAsync(document.RootElement.Clone(), ct);
            await _outbox.DeleteAsync(item.EventId, ct);

            if (!result.Acknowledged)
            {
                _logger.LogWarning("서버 Reject eventId={EventId} reason={Reason}", item.EventId, result.RejectReason);
            }
        }

        return true;
    }

    /// <summary>401 — 세션을 버리고 이 키로는 다시 시도하지 않는다. Outbox는 건드리지 않는다.</summary>
    private async Task RejectKeyAsync(string key)
    {
        _logger.LogWarning("TelemetryHub가 장치 키를 거부했습니다(401) — 다시 연결이 필요합니다. 새 키가 저장될 때까지 업로드를 멈춥니다.");
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

    private async Task DisposeSessionAsync()
    {
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

    private static TimeSpan NextBackoff(TimeSpan current)
        => TimeSpan.FromTicks(Math.Min(MaxBackoff.Ticks, current.Ticks * BackoffMultiplier));
}
