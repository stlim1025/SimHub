namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 차 1대의 세션 랩 기록(F1 Session History 패킷, 차마다 돌아가며 온다 — D-49 docs/15 §8). 받을 때마다 그 차의 목록을 통째로 대체한다.
/// 플레이어 차면 랩 스냅샷 <c>car.details.sessionHistory</c>, 모든 차는 <c>SessionClassified</c>의 <c>lapHistory</c> 원천이다.
/// </summary>
public sealed record SessionHistoryFrame(
    string SessionRef,
    int CarIndex,
    bool IsPlayer,
    IReadOnlyList<LapHistoryEntry> Laps) : ITelemetryFrame;
