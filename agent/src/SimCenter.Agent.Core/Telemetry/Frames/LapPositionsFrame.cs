namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 랩별 순위표(F1 Lap Positions 패킷, D-49 docs/15 §8). <paramref name="PositionsByLap"/>[i] = 랩 <c>FirstLapNumber + i</c>의
/// carIndex별 순위(0 = 기록 없음). 긴 레이스는 여러 패킷으로 나눠 오므로 분석기가 랩 번호로 합친다.
/// </summary>
public sealed record LapPositionsFrame(
    string SessionRef,
    int FirstLapNumber,
    IReadOnlyList<IReadOnlyList<int>> PositionsByLap) : ITelemetryFrame;
