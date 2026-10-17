namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// 업로더의 현재 <see cref="UploadState"/>와 올리지 못한 항목 건수를 보관하고 바뀔 때 알린다(싱글턴). 업로드 루프가 쓰고 UI가 읽는다.
/// </summary>
public sealed class UploadStatusTracker
{
    private int _state = (int)UploadState.Disabled;
    private int _deferredCount;
    private int _deadLetterCount;

    /// <summary>현재 상태. 업로더가 시작되기 전에는 <see cref="UploadState.Disabled"/>.</summary>
    public UploadState State => (UploadState)Volatile.Read(ref _state);

    /// <summary>서버 오류가 되풀이돼 미뤄 둔 항목 수 — 자동으로 다시 보낸다(docs/13 §3.2).</summary>
    public int DeferredCount => Volatile.Read(ref _deferredCount);

    /// <summary>읽을 수 없어 dead-letter로 옮겨 보관한 항목 수(docs/13 §3.4).</summary>
    public int DeadLetterCount => Volatile.Read(ref _deadLetterCount);

    /// <summary>
    /// 상태나 건수가 실제로 바뀔 때만 발생한다. 업로드 루프 스레드에서 동기 실행되므로 핸들러는 가벼워야 한다.
    /// </summary>
    public event EventHandler? StateChanged;

    public void Set(UploadState state) => Update(ref _state, (int)state);

    public void SetDeferredCount(int count)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        Update(ref _deferredCount, count);
    }

    public void SetDeadLetterCount(int count)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        Update(ref _deadLetterCount, count);
    }

    private void Update(ref int field, int value)
    {
        if (Interlocked.Exchange(ref field, value) != value)
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
