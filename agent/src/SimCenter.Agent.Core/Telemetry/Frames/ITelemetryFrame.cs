namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 게임중립 입력 프레임의 마커. Infrastructure가 게임별 UDP 패킷(F1Game.UDP 등)에서 매핑해 공급한다.
/// Agent.Core는 이 추상 프레임만 소비하므로 특정 게임 라이브러리에 무의존이다.
/// </summary>
public interface ITelemetryFrame
{
    /// <summary>세션 고유 참조(F1: SessionUID 문자열).</summary>
    string SessionRef { get; }
}
