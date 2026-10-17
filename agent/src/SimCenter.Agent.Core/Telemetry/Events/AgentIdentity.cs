namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>
/// 이 Agent가 보내는 이벤트의 게임 식별(envelope의 gameCode). 설정에서 주입.
/// 보낸 장치는 봉투가 아니라 연결의 장치 키 인증으로 정해진다(D-26).
/// </summary>
public sealed record AgentIdentity(string GameCode);
