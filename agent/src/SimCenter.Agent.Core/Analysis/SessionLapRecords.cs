using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 세션 동안의 전 차량 랩 기록(Session History)과 랩별 순위(Lap Positions) 모음(D-49, docs/15 §8) — <see cref="SessionResultTracker"/>가 순위표에 싣는다.
/// Session History는 차마다 최신 목록이 이전 목록을 대체하고, Lap Positions는 여러 패킷(랩 구간)을 랩 번호로 합친다(같은 랩이면 나중 값).
/// 세션이 바뀌면 <see cref="Reset"/>. 상태 저장이라 스레드 안전하지 않다.
/// </summary>
public sealed class SessionLapRecords
{
    /// <summary>랩 번호 상한(게임은 랩을 1바이트로 센다). 넘는 랩은 버린다.</summary>
    public const int MaxLapNumber = 255;

    private readonly Dictionary<int, IReadOnlyList<LapHistoryEntry>> _historyByCar = [];
    private readonly SortedDictionary<int, IReadOnlyList<int>> _positionsByLap = [];

    public void OnSessionHistory(SessionHistoryFrame frame) => _historyByCar[frame.CarIndex] = frame.Laps;

    public void OnLapPositions(LapPositionsFrame frame)
    {
        for (var i = 0; i < frame.PositionsByLap.Count; i++)
        {
            var lapNumber = frame.FirstLapNumber + i;
            if (lapNumber is >= 1 and <= MaxLapNumber)
            {
                _positionsByLap[lapNumber] = frame.PositionsByLap[i];
            }
        }
    }

    /// <summary>그 차의 랩 기록. 받지 못했으면 null.</summary>
    public IReadOnlyList<LapHistoryEntry>? HistoryFor(int carIndex) => _historyByCar.GetValueOrDefault(carIndex);

    /// <summary>랩 번호 순 랩별 순위. 받지 못했으면 null.</summary>
    public IReadOnlyList<LapPositionsEntry>? BuildLapPositions() =>
        _positionsByLap.Count == 0
            ? null
            : _positionsByLap.Select(lap => new LapPositionsEntry(lap.Key, lap.Value)).ToArray();

    public void Reset()
    {
        _historyByCar.Clear();
        _positionsByLap.Clear();
    }
}
