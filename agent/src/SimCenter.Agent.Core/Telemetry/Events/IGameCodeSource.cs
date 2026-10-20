namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>지금 보내는 이벤트 봉투의 게임 코드(envelope의 gameCode) 공급원.</summary>
public interface IGameCodeSource
{
    string GameCode { get; }
}
