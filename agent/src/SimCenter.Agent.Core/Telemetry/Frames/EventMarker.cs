namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>세션 경계 마커(F1 Event 패킷 SSTA/SEND 매핑).</summary>
public sealed record EventMarker(string SessionRef, SessionBoundary Kind) : ITelemetryFrame;

public enum SessionBoundary
{
    Start = 0,
    End = 1,
}
