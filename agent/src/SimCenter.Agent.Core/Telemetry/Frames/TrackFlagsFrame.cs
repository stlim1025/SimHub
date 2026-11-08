namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 트랙 깃발 상태(F1 Session 패킷의 마셜 구역 깃발을 섹터로 묶은 값). <paramref name="YellowSectors"/> = 옐로 플래그가 나온 섹터 번호(1~3, 오름차순, 없으면 빈 목록).
/// 랩 스냅샷에는 바뀐 순간만 이벤트로 남는다(<see cref="Analysis.LapDetailsTracker.YellowFlagCode"/>).
/// </summary>
public sealed record TrackFlagsFrame(string SessionRef, IReadOnlyList<int> YellowSectors) : ITelemetryFrame;
