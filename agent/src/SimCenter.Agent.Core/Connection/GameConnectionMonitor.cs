using SimCenter.Agent.Core.Abstractions;

namespace SimCenter.Agent.Core.Connection;

/// <summary>
/// 게임(UDP) 수신 연결 상태를 추적한다. 파이프라인(UDP 스레드)이 데이터그램마다 통지하고,
/// GUI(UI 스레드)가 <see cref="GetSnapshot"/>로 폴링한다 → 스레드 안전(lock).
/// 상태 판정은 IClock 기반이라 결정론적 단위테스트가 가능하다.
/// </summary>
public sealed class GameConnectionMonitor
{
    private readonly IClock _clock;
    private readonly ConnectionThresholds _thresholds;
    private readonly object _gate = new();

    private DateTime? _listenStartedAt;
    private DateTime? _lastDatagramAt;
    private long _totalDatagrams;
    private int? _detectedPacketFormat;
    private string? _listenerError;

    public GameConnectionMonitor(IClock clock, ConnectionThresholds thresholds)
    {
        _clock = clock;
        _thresholds = thresholds;
    }

    /// <summary>리스너가 바인딩되어 수신 대기를 시작했다.</summary>
    public void MarkListening()
    {
        lock (_gate)
        {
            _listenStartedAt = _clock.UtcNow;
            _listenerError = null;
        }
    }

    /// <summary>리스너 바인딩/실행 실패(→ 즉시 Disconnected).</summary>
    public void MarkListenerFailed(string reason)
    {
        lock (_gate)
        {
            _listenerError = reason;
        }
    }

    /// <summary>데이터그램 1개 수신(파싱 성공과 무관 — "게임이 보내는 중" 신호).</summary>
    public void RecordDatagram(int? packetFormat)
    {
        lock (_gate)
        {
            _lastDatagramAt = _clock.UtcNow;
            _totalDatagrams++;
            if (packetFormat is not null)
            {
                _detectedPacketFormat = packetFormat;
            }
        }
    }

    public ConnectionSnapshot GetSnapshot()
    {
        lock (_gate)
        {
            var now = _clock.UtcNow;
            double? secondsSinceLast = _lastDatagramAt is { } last
                ? Math.Max(0, (now - last).TotalSeconds)
                : null;

            var state = Evaluate(now, secondsSinceLast);
            return new ConnectionSnapshot(
                state,
                _lastDatagramAt,
                secondsSinceLast,
                _totalDatagrams,
                _detectedPacketFormat,
                _listenerError);
        }
    }

    private ConnectionState Evaluate(DateTime now, double? secondsSinceLast)
    {
        if (_listenerError is not null)
        {
            return ConnectionState.Disconnected;
        }

        if (secondsSinceLast is null)
        {
            // 아직 한 번도 수신 못 함: 리스너 시작 직후 잠깐은 대기(🟡), 오래되면 미연결(🔴).
            var sinceStart = _listenStartedAt is { } started ? (now - started).TotalMilliseconds : double.MaxValue;
            return sinceStart < _thresholds.WaitingWithinMs ? ConnectionState.Waiting : ConnectionState.Disconnected;
        }

        var elapsedMs = secondsSinceLast.Value * 1000.0;
        if (elapsedMs < _thresholds.ConnectedWithinMs)
        {
            return ConnectionState.Connected;
        }

        return elapsedMs < _thresholds.WaitingWithinMs ? ConnectionState.Waiting : ConnectionState.Disconnected;
    }
}
