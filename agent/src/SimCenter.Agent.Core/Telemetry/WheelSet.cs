namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 바퀴 4개 값(타이어 마모·손상, 브레이크 손상 등, docs/15 §3.1). 게임 배열 순서와 무관하게 <b>이름</b>으로 담는다 —
/// F1 UDP 배열 순서는 RL·RR·FL·FR이므로 Infrastructure 매퍼가 이름으로 옮긴다. wire JSON은 <c>{ frontLeft, frontRight, rearLeft, rearRight }</c>.
/// </summary>
public sealed record WheelSet<T>(T FrontLeft, T FrontRight, T RearLeft, T RearRight)
    where T : struct;
