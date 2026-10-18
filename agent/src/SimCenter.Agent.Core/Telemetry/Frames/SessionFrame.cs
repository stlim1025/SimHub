namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 세션 상태 프레임(F1 Session 패킷 매핑). SessionStarted 판정의 권위 소스(트랙·세션타입 보유).
/// 뒤쪽 매개변수(P7)는 기본값이 있어 기존 호출부가 그대로 컴파일된다. 링크 식별자(<c>uint</c>)는 시즌 대상 모드에서만 의미가 있다(D-29).
/// 날씨·기온·트랙 길이·비 예보(docs/15 §3.1)는 랩 스냅샷의 <c>conditions</c>(D-44) 원천이다 — null = 모름(받지 못함).
/// </summary>
/// <param name="RainForecastPercent">현재 세션 종류 예보 중 앞으로 가장 이른 샘플의 비 확률(규칙은 매퍼, docs/15 §3.1).</param>
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
    bool IsNetworkGame = false,
    Weather? Weather = null,
    int? AirTemperatureC = null,
    int? TrackTemperatureC = null,
    int? TrackLengthM = null,
    int? RainForecastPercent = null) : ITelemetryFrame;
