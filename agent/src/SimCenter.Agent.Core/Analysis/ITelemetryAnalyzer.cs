using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 프레임을 받아 도메인 이벤트를 만드는 분석기(<see cref="LapAnalyzer"/>, <see cref="SessionResultTracker"/>).
/// 구현은 모두 <b>상태 저장·스레드 안전하지 않다</b> — 파이프라인이 프레임을 순차로 먹인다.
/// 분석기끼리는 상태를 공유하지 않으므로 호출 순서에 의존하지 않는다(12 §5.5 배선).
/// </summary>
public interface ITelemetryAnalyzer
{
    /// <summary>프레임 1개를 처리하고 그로 인해 발생한 도메인 이벤트(0..N)를 순서대로 반환한다.</summary>
    IReadOnlyList<TelemetryEvent> Process(ITelemetryFrame frame);
}
