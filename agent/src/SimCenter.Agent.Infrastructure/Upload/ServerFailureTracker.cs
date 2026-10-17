namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>서버 오류 기록 1건: 지금까지의 실패 횟수와, 미뤄졌다면 다시 보낼 수 있는 시각(UTC).</summary>
internal readonly record struct ServerFailure(int Failures, DateTime? RetryAt);

/// <summary>
/// 서버 오류(<see cref="TelemetryHubServerException"/>)가 난 Outbox 항목별 실패 횟수와 다음 시도 시각(docs/13 §3.2, D-35).
/// 실패가 기준 횟수에 이르면 그 항목만 기본 지연부터 두 배씩(최대 지연까지) 미뤄 뒤 항목이 먼저 가게 한다.
/// 항목을 버리거나 격리하지 않는다 — 서버 예외는 서버 쪽 문제라 고쳐지면 다시 보낸 항목이 성공한다.
/// 업로드 루프 스레드만 쓰므로 잠그지 않는다. 시각은 호출자가 <c>IClock</c>으로 넘긴다.
/// </summary>
internal sealed class ServerFailureTracker
{
    // long 시프트가 넘치지 않는 지수 상한. 이보다 크면 언제나 최대 지연이다.
    private const int MaxShift = 62;

    private readonly Dictionary<Guid, ServerFailure> _failures = new();
    private readonly int _deferThreshold;
    private readonly TimeSpan _baseDelay;
    private readonly TimeSpan _maxDelay;

    public ServerFailureTracker(int deferThreshold, TimeSpan baseDelay, TimeSpan maxDelay)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(deferThreshold, 1);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(baseDelay, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfLessThan(maxDelay, baseDelay);

        _deferThreshold = deferThreshold;
        _baseDelay = baseDelay;
        _maxDelay = maxDelay;
    }

    /// <summary>서버 오류 기록이 있는 항목 수(미뤄지지 않은 항목 포함).</summary>
    public int TrackedCount => _failures.Count;

    /// <summary>실패가 기준 횟수에 이르러 미뤄진 항목 수(다시 보낼 시각이 지났어도 서버가 답하기 전까지 센다).</summary>
    public int DeferredCount => _failures.Values.Count(failure => failure.RetryAt is not null);

    /// <summary>
    /// 지금은 보내지 말고 건너뛸 항목인가. 남은 시간이 최대 지연보다 길면 벽시계가 뒤로 간 것이므로 미루지 않는다
    /// (시계를 되돌려도 "늦어도 최대 지연 안에 다시 보낸다"를 지킨다).
    /// </summary>
    public bool IsDeferred(Guid eventId, DateTime now)
        => _failures.TryGetValue(eventId, out var failure)
           && failure.RetryAt is { } retryAt
           && now < retryAt
           && retryAt - now <= _maxDelay;

    /// <summary>서버 오류 1회를 기록하고, 기준 횟수 이상이면 다음 시도 시각을 정한다.</summary>
    public ServerFailure RecordFailure(Guid eventId, DateTime now)
    {
        var failures = (_failures.TryGetValue(eventId, out var previous) ? previous.Failures : 0) + 1;
        var failure = new ServerFailure(failures, failures >= _deferThreshold ? now + DelayFor(failures) : null);
        _failures[eventId] = failure;
        return failure;
    }

    /// <summary>서버가 그 항목에 답했다(Ack/Reject) — 기록을 지운다.</summary>
    public void Forget(Guid eventId) => _failures.Remove(eventId);

    /// <summary>모든 기록을 지운다(장치 키가 바뀌거나 거부됐을 때).</summary>
    public void Clear() => _failures.Clear();

    private TimeSpan DelayFor(int failures)
    {
        var shift = failures - _deferThreshold;

        // baseDelay × 2^shift가 maxDelay를 넘는지 곱하기 전에 확인한다(넘침 방지).
        if (shift >= MaxShift || _baseDelay.Ticks > _maxDelay.Ticks >> shift)
        {
            return _maxDelay;
        }

        return TimeSpan.FromTicks(_baseDelay.Ticks << shift);
    }
}
