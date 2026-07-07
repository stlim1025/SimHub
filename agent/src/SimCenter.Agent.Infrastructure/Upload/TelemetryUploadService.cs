using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Outbox;

namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// Outbox를 TelemetryHub로 배수(drain)하는 백그라운드 서비스(docs/06 §5, 05 §5).
/// 자동 재접속 + 지수 백오프. 서버가 응답(Ack/Reject)하면 Outbox에서 제거하고, 응답 없음(장애)이면 보관 후 재시도.
/// </summary>
public sealed class TelemetryUploadService : BackgroundService
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan MaxBackoff = TimeSpan.FromSeconds(30);
    private const int BatchSize = 50;

    private readonly AgentOptions _options;
    private readonly TelemetryOutbox _outbox;
    private readonly ILogger<TelemetryUploadService> _logger;
    private HubConnection? _connection;

    public TelemetryUploadService(IOptions<AgentOptions> options, TelemetryOutbox outbox, ILogger<TelemetryUploadService> logger)
    {
        _options = options.Value;
        _outbox = outbox;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (string.IsNullOrWhiteSpace(_options.BackendUrl))
        {
            _logger.LogWarning("BackendUrl 미설정 — 업로드 비활성(이벤트는 Outbox에 계속 적재됨).");
            return;
        }

        _connection = BuildConnection();
        var backoff = PollInterval;

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (_connection.State == HubConnectionState.Disconnected)
                {
                    await _connection.StartAsync(stoppingToken);
                    _logger.LogInformation("TelemetryHub 연결됨: {Url}", _options.BackendUrl);
                }

                var sentAny = await DrainAsync(stoppingToken);
                backoff = PollInterval;

                if (!sentAny)
                {
                    await Task.Delay(PollInterval, stoppingToken);
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "업로드 실패 — {Seconds}s 후 재시도", backoff.TotalSeconds);
                await DelaySafe(backoff, stoppingToken);
                backoff = TimeSpan.FromSeconds(Math.Min(MaxBackoff.TotalSeconds, backoff.TotalSeconds * 2));
            }
        }

        if (_connection is not null)
        {
            await _connection.DisposeAsync();
        }
    }

    /// <returns>하나 이상 전송하면 true(연속 배수 유도).</returns>
    private async Task<bool> DrainAsync(CancellationToken cancellationToken)
    {
        var pending = await _outbox.GetPendingAsync(BatchSize, cancellationToken);
        if (pending.Count == 0)
        {
            return false;
        }

        foreach (var item in pending)
        {
            using var document = JsonDocument.Parse(item.PayloadJson);

            // 서버 응답(반환값)이 오면 Ack/Reject 무관하게 Outbox에서 제거. 예외(장애)면 보관되어 재시도.
            var ack = await _connection!.InvokeAsync<SubmitAck>("SubmitEvent", document.RootElement.Clone(), cancellationToken);
            await _outbox.DeleteAsync(item.EventId, cancellationToken);

            if (!ack.Acknowledged)
            {
                _logger.LogWarning("서버 Reject eventId={EventId} reason={Reason}", item.EventId, ack.RejectReason);
            }
        }

        return true;
    }

    private HubConnection BuildConnection()
    {
        return new HubConnectionBuilder()
            .WithUrl(_options.BackendUrl, options =>
            {
                if (!string.IsNullOrWhiteSpace(_options.AgentCredential))
                {
                    options.Headers.Add("X-Agent-Key", _options.AgentCredential);
                }
            })
            .WithAutomaticReconnect()
            .AddJsonProtocol(json =>
            {
                json.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
                json.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
                json.PayloadSerializerOptions.Converters.Add(new JsonStringEnumConverter());
            })
            .Build();
    }

    private static async Task DelaySafe(TimeSpan delay, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(delay, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            // 종료 중 — 무시.
        }
    }

    /// <summary>서버 SubmitEvent 반환값(IngestResult). camelCase로 매핑된다.</summary>
    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
