namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// 업로더의 현재 <see cref="UploadState"/>를 보관하고 바뀔 때 알린다(싱글턴). 업로드 루프가 쓰고 UI가 읽는다.
/// </summary>
public sealed class UploadStatusTracker
{
    private int _state = (int)UploadState.Disabled;

    /// <summary>현재 상태. 업로더가 시작되기 전에는 <see cref="UploadState.Disabled"/>.</summary>
    public UploadState State => (UploadState)Volatile.Read(ref _state);

    /// <summary>상태가 실제로 바뀔 때만 발생한다. 업로드 루프 스레드에서 동기 실행되므로 핸들러는 가벼워야 한다.</summary>
    public event EventHandler? StateChanged;

    public void Set(UploadState state)
    {
        var previous = (UploadState)Interlocked.Exchange(ref _state, (int)state);
        if (previous != state)
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
