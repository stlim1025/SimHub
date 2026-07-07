namespace SimCenter.Agent.Core.Connection;

/// <summary>연결 상태 판정 임계값(밀리초). 마지막 수신 이후 경과로 🟢/🟡/🔴 구분.</summary>
public sealed class ConnectionThresholds
{
    /// <summary>이 시간 이내 수신이면 Connected(🟢).</summary>
    public int ConnectedWithinMs { get; set; } = 2000;

    /// <summary>이 시간 이내면 Waiting(🟡), 초과하면 Disconnected(🔴).</summary>
    public int WaitingWithinMs { get; set; } = 6000;
}
