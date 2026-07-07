namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>세션 상태 프레임(F1 Session 패킷 매핑). SessionStarted 판정의 권위 소스(트랙·세션타입 보유).</summary>
public sealed record SessionFrame(
    string SessionRef,
    int TrackId,
    SessionType SessionType,
    int PacketFormat) : ITelemetryFrame;
