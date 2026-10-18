using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 랩 스냅샷 <c>car.details</c> 수집기(D-49, docs/15 §8). <see cref="LapAnalyzer"/>가 상세 묶음·게임 이벤트·플레이어 Session History를 먹이고,
/// 랩이 바뀌는 순간 <see cref="Build"/>로 <c>details</c>를 만든 뒤 <see cref="StartLap"/>을 부른다.
/// 묶음(<c>setup</c>·<c>damage</c>·<c>status</c> …)은 랩을 넘어 최신 값을 유지하고(셋업·타이어 세트·타임 트라이얼은 랩마다 오지 않는다),
/// 이벤트는 랩마다 비운다. 세션이 바뀌면 <see cref="Reset"/>으로 모두 잊는다. 상태 저장이라 스레드 안전하지 않다(분석기와 같다).
/// </summary>
public sealed class LapDetailsTracker
{
    /// <summary>랩 1개에 싣는 이벤트 상한 — 추월·충돌이 많은 랩에서도 봉투가 커지지 않게. 넘는 이벤트는 버리고 개수만 센다.</summary>
    public const int MaxEventsPerLap = 200;

    /// <summary><c>details</c> 안에서 이벤트 목록 키.</summary>
    public const string EventsKey = "events";

    /// <summary>한도를 넘어 버린 이벤트 수 키(0이면 싣지 않는다).</summary>
    public const string DroppedEventsKey = "droppedEvents";

    /// <summary>플레이어의 이 랩 Session History 항목 키.</summary>
    public const string SessionHistoryKey = "sessionHistory";

    private readonly Dictionary<string, IReadOnlyDictionary<string, object?>> _sections = new(StringComparer.Ordinal);
    private readonly List<LapEventEntry> _events = [];
    private int _droppedEvents;
    private IReadOnlyList<LapHistoryEntry>? _playerHistory;

    /// <summary>묶음의 최신 값을 보관한다(같은 이름이면 대체).</summary>
    public void OnSection(CarDetailsFrame frame) => _sections[frame.Section] = frame.Values;

    /// <summary>이벤트를 이번 랩 목록에 더한다. <paramref name="lapTimeMs"/> = 지금 랩 경과 시간(음수면 0).</summary>
    public void OnEvent(GameEventFrame frame, int lapTimeMs)
    {
        if (_events.Count >= MaxEventsPerLap)
        {
            _droppedEvents++;
            return;
        }

        _events.Add(new LapEventEntry(frame.Code, Math.Max(0, lapTimeMs), frame.Details));
    }

    /// <summary>플레이어 차의 Session History만 보관한다(다른 차는 <see cref="SessionResultTracker"/>가 쓴다).</summary>
    public void OnSessionHistory(SessionHistoryFrame frame)
    {
        if (frame.IsPlayer)
        {
            _playerHistory = frame.Laps;
        }
    }

    /// <summary>새 랩 — 이벤트만 비운다.</summary>
    public void StartLap()
    {
        _events.Clear();
        _droppedEvents = 0;
    }

    /// <summary>세션이 바뀌면 모두 잊는다.</summary>
    public void Reset()
    {
        _sections.Clear();
        _playerHistory = null;
        StartLap();
    }

    /// <summary>
    /// 완료 랩 <paramref name="lapNumber"/>의 <c>details</c>. 묶음·이벤트·기록을 하나도 받지 못했으면 null. 값은 <see cref="DetailValues"/>로 다듬은 새 사전이다.
    /// 이벤트 목록은 받은 것이 없어도 빈 목록으로 싣는다(= 이 랩에 이벤트 없음). Session History는 그 랩 칸이 있을 때만 싣는다
    /// (게임은 랩이 끝난 직후에야 그 랩의 마지막 섹터를 채우므로 값이 0일 수 있다 — 세션 전체 기록은 <c>SessionClassified.lapHistory</c>).
    /// </summary>
    public IReadOnlyDictionary<string, object?>? Build(int lapNumber)
    {
        if (_sections.Count == 0 && _events.Count == 0 && _droppedEvents == 0 && _playerHistory is null)
        {
            return null;
        }

        var details = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var (section, values) in _sections)
        {
            details[section] = DetailValues.Sanitize(values);
        }

        details[EventsKey] = _events.Select(entry => entry with { Details = DetailValues.Sanitize(entry.Details) }).ToArray();
        if (_droppedEvents > 0)
        {
            details[DroppedEventsKey] = _droppedEvents;
        }

        if (_playerHistory?.FirstOrDefault(entry => entry.LapNumber == lapNumber) is { } lap)
        {
            details[SessionHistoryKey] = lap;
        }

        return details;
    }
}
