namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>
/// 고정된 게임 식별(envelope의 gameCode). 세션별 판별이 필요 없는 곳(테스트 등)에서 쓴다 — 실행 중인 Agent는
/// <see cref="SimCenter.Agent.Core.Analysis.GameEditionDetector"/>가 세션마다 F1 25/F1 26을 고른다.
/// 보낸 장치는 봉투가 아니라 연결의 장치 키 인증으로 정해진다(D-26).
/// </summary>
public sealed record AgentIdentity(string GameCode) : IGameCodeSource;
