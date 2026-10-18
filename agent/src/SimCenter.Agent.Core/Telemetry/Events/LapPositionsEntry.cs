namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>
/// 랩 1개의 순위 — <c>SessionClassified.lapPositions[]</c>(D-49, docs/15 §8). <paramref name="Positions"/>[carIndex] = 그 랩의 순위, 0 = 기록 없음
/// (빈 그리드 칸 포함 — <c>results[].carIndex</c>로 맞춰 읽는다).
/// </summary>
public sealed record LapPositionsEntry(int LapNumber, IReadOnlyList<int> Positions);
