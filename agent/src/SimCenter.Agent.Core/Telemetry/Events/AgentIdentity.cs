namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>이 Agent가 담당하는 좌석·게임 식별(envelope의 rigCode/gameCode). 설정에서 주입.</summary>
public sealed record AgentIdentity(string RigCode, string GameCode);
