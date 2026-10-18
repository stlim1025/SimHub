namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 플레이어 차의 순간 텔레메트리(F1 Car Telemetry 패킷의 플레이어 칸, docs/15 §3.1). 1랩 트레이스(D-45)의 표본 원천이다.
/// 페달·스티어는 게임 값 그대로(0~1, −1~1) — 트레이스 정수(0~100, −100~100)로는 <c>LapTraceRecorder</c>가 바꾼다.
/// </summary>
/// <param name="Gear">−1 = R, 0 = N, 1~8.</param>
public sealed record CarTelemetryFrame(
    string SessionRef,
    int SpeedKph,
    float Throttle,
    float Brake,
    float Steer,
    int Gear,
    int EngineRpm) : ITelemetryFrame;
