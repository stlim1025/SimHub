namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 세션 상태 프레임(F1 Session 패킷 매핑). SessionStarted 판정의 권위 소스(트랙·세션타입 보유).
/// 뒤쪽 매개변수(P7)는 기본값이 있어 기존 호출부가 그대로 컴파일된다. 링크 식별자(<c>uint</c>)는 시즌 대상 모드에서만 의미가 있다(D-29).
/// </summary>
public sealed record SessionFrame(
    string SessionRef,
    int TrackId,
    SessionType SessionType,
    int PacketFormat,
    SessionKind SessionKind = SessionKind.Unknown,
    GameMode GameMode = GameMode.Other,
    uint SeasonLinkId = 0,
    uint WeekendLinkId = 0,
    uint SessionLinkId = 0,
    int TotalLaps = 0,
    int AiDifficulty = 0,
    bool IsNetworkGame = false) : ITelemetryFrame;
