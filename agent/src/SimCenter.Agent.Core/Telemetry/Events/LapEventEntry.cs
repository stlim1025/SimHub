namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>
/// 랩 동안 받은 게임 이벤트 1건 — <c>car.details.events[]</c>(D-49, docs/15 §8). <paramref name="LapTimeMs"/> = 받은 순간 플레이어 랩의 경과 시간(랩 시작 기준).
/// </summary>
public sealed record LapEventEntry(
    string Code,
    int LapTimeMs,
    IReadOnlyDictionary<string, object?> Details);
