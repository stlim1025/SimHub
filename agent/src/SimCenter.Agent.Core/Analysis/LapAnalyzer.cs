using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 플레이어 차량의 직전 상태를 유지하며 랩/섹터 전이를 <b>엣지 트리거</b>로 감지해 도메인 이벤트를 만든다
/// (docs/06 §3). 고주파 반복 프레임에는 이벤트를 만들지 않는다. 순수·결정론적(네트워크/시간 무의존).
/// 단일 세션·단일 플레이어 상태를 갖는 <b>상태 저장</b> 클래스이므로 스레드 안전하지 않다(파이프라인이 순차 처리).
/// 차량 상태·텔레메트리 프레임은 이벤트를 만들지 않고 랩 스냅샷(<see cref="LapCarStateTracker"/>, D-44)과
/// 트레이스(<see cref="LapTraceRecorder"/>, D-45)에 쌓기만 한다 — 랩이 바뀌는 순간 LapFinished에 함께 싣는다.
/// </summary>
public sealed class LapAnalyzer : ITelemetryAnalyzer
{
    private const int SectorFirst = 0;
    private const int SectorSecond = 1;

    /// <summary>
    /// 세션에서 처음 본 랩이 이 시간(ms) 안이면 랩 시작부터 지켜본 것으로 보고 시작 값을 받는다(docs/15 §3.2).
    /// 더 지났으면 Agent가 랩 중간에 시작한 것이라 시작 값을 보내지 않는다.
    /// </summary>
    private const int FirstLapStartWindowMs = 1_000;

    private static readonly IReadOnlyList<TelemetryEvent> NoEvents = Array.Empty<TelemetryEvent>();

    private readonly LapCarStateTracker _carState = new();
    private readonly LapTraceRecorder _trace = new();

    // 세션 상태
    private string? _sessionRef;
    private SessionType _sessionType;
    private int _trackId;
    private GameMode _gameMode;
    private uint _seasonLinkId;
    private uint _weekendLinkId;
    private uint _sessionLinkId;

    // 랩 상태
    private int _lastLapNumber;         // 0 = 아직 없음
    private int _lastSector = -1;       // -1 = 아직 없음
    private bool _lapInvalidAccum;
    private bool _outOrInLapAccum;
    private int _completedSector1Ms;
    private int _completedSector2Ms;

    /// <summary>프레임 1개를 처리하고 그로 인해 발생한 도메인 이벤트(0..N)를 순서대로 반환한다.</summary>
    public IReadOnlyList<TelemetryEvent> Process(ITelemetryFrame frame)
    {
        return frame switch
        {
            SessionFrame sf => OnSession(sf),
            LapFrame lf => OnLap(lf),
            EventMarker em => OnEvent(em),
            _ => OnCarFrame(frame),
        };
    }

    /// <summary>차량 상태·텔레메트리·참가자 프레임을 스냅샷·트레이스에 쌓는다. 지금 세션이 아니면 버린다. 이벤트는 만들지 않는다.</summary>
    private IReadOnlyList<TelemetryEvent> OnCarFrame(ITelemetryFrame frame)
    {
        if (_sessionRef is null || frame.SessionRef != _sessionRef)
        {
            return NoEvents;
        }

        switch (frame)
        {
            case CarTelemetryFrame telemetry:
                _trace.Record(telemetry);
                break;
            case ExtraChannelsFrame extra:
                _trace.OnExtraChannels(extra);
                break;
            case CarStatusFrame status:
                _carState.OnStatus(status);
                break;
            case CarDamageFrame damage:
                _carState.OnDamage(damage);
                break;
            case ParticipantsFrame participants:
                _carState.OnParticipants(participants);
                break;
        }

        return NoEvents;
    }

    private IReadOnlyList<TelemetryEvent> OnSession(SessionFrame sf)
    {
        if (_sessionRef == sf.SessionRef)
        {
            // 같은 세션의 반복 Session 패킷 — 최신 값만 갱신, 이벤트 없음.
            UpdateSessionContext(sf);
            return NoEvents;
        }

        var events = new List<TelemetryEvent>(2);
        if (_sessionRef is not null)
        {
            // 세션 UID 변경 = 이전 세션 종료.
            events.Add(new SessionEnded(_sessionRef));
        }

        _sessionRef = sf.SessionRef;
        ResetLapState();   // 스냅샷까지 비운 뒤 새 세션 맥락(주행 조건 포함)을 넣는다
        UpdateSessionContext(sf);
        events.Add(new SessionStarted(sf.SessionRef, sf.TrackId, sf.SessionType));
        return events;
    }

    private IReadOnlyList<TelemetryEvent> OnLap(LapFrame lf)
    {
        // 세션 컨텍스트가 아직 없으면(Session 패킷 미수신) 무시. 스테일 세션 프레임도 무시.
        if (_sessionRef is null || lf.SessionRef != _sessionRef)
        {
            return NoEvents;
        }

        if (lf.CurrentLapNumber > _lastLapNumber)
        {
            return OnLapTransition(lf, _sessionRef);
        }

        AccumulateLapFlags(lf);
        UpdateTracePosition(lf);

        // 섹터 완료 감지(엣지): 0→1 = S1 확정, 1→2 = S2 확정. 2→0은 랩 전환에서 처리(위).
        if (lf.CurrentSector != _lastSector)
        {
            var events = new List<TelemetryEvent>(1);
            if (_lastSector == SectorFirst && lf.CurrentSector == SectorSecond)
            {
                _completedSector1Ms = lf.Sector1TimeMs;
                events.Add(new SectorCompleted(_sessionRef, lf.CurrentLapNumber, 1, lf.Sector1TimeMs));
            }
            else if (_lastSector == SectorSecond && lf.CurrentSector == 2)
            {
                _completedSector2Ms = lf.Sector2TimeMs;
                events.Add(new SectorCompleted(_sessionRef, lf.CurrentLapNumber, 2, lf.Sector2TimeMs));
            }

            _lastSector = lf.CurrentSector;
            return events;
        }

        return NoEvents;
    }

    /// <summary>
    /// 랩 전환(N → N+1): 완료 랩 확정(스냅샷·트레이스 포함) + 새 랩 시작. 세션에서 처음 본 랩은 LapFinished 없이 LapStarted만 낸다.
    /// </summary>
    private IReadOnlyList<TelemetryEvent> OnLapTransition(LapFrame lf, string sessionRef)
    {
        var events = new List<TelemetryEvent>(2);
        var observedLapStart = _lastLapNumber >= 1 || lf.CurrentLapTimeMs <= FirstLapStartWindowMs;
        if (_lastLapNumber >= 1)
        {
            events.Add(BuildLapFinished(completedLapNumber: _lastLapNumber, totalMs: lf.LastLapTimeMs));
        }

        events.Add(new LapStarted(sessionRef, lf.CurrentLapNumber));

        _lastLapNumber = lf.CurrentLapNumber;
        _lastSector = lf.CurrentSector;
        ResetLapAccumulators();
        _carState.StartLap(captureStartValues: observedLapStart);

        // 새 랩의 첫 프레임 상태를 누적 시작.
        AccumulateLapFlags(lf);
        _trace.UpdatePosition(lf.LapDistanceM, lf.CurrentLapTimeMs);
        return events;
    }

    private IReadOnlyList<TelemetryEvent> OnEvent(EventMarker em)
    {
        if (em.Kind == SessionBoundary.End && _sessionRef is not null)
        {
            var ended = new SessionEnded(_sessionRef);
            ResetSession();
            return new[] { ended };
        }

        // Start 마커는 Session 프레임이 권위 소스이므로 무시(트랙·세션타입 필요).
        return NoEvents;
    }

    private LapFinished BuildLapFinished(int completedLapNumber, int totalMs)
    {
        var s1 = _completedSector1Ms;
        var s2 = _completedSector2Ms;
        var s3 = Math.Max(0, totalMs - s1 - s2);

        var sectors = new List<LapSectorDto>(3)
        {
            new(1, s1),
            new(2, s2),
            new(3, s3),
        };

        return new LapFinished(
            SessionRef: _sessionRef!,
            LapNumber: completedLapNumber,
            LapTimeMs: totalMs,
            Sectors: sectors,
            IsValid: !_lapInvalidAccum,
            IsOutOrInLap: _outOrInLapAccum,
            TrackId: _trackId,
            SessionType: _sessionType,
            GameMode: _gameMode,
            SeasonLinkId: _seasonLinkId,
            WeekendLinkId: _weekendLinkId,
            SessionLinkId: _sessionLinkId,
            Car: _carState.BuildCar(),
            Conditions: _carState.BuildConditions(),
            Trace: _trace.Flush());
    }

    /// <summary>
    /// 지금 랩의 Lap Data만 트레이스 위치로 쓴다. 랩 번호가 더 작은 프레임(플래시백으로 이전 랩에 되돌아감)은 위치를 비워
    /// 그 동안의 텔레메트리가 지금 랩 트레이스를 더럽히지 않게 한다.
    /// </summary>
    private void UpdateTracePosition(LapFrame lf)
    {
        if (lf.CurrentLapNumber == _lastLapNumber)
        {
            _trace.UpdatePosition(lf.LapDistanceM, lf.CurrentLapTimeMs);
        }
        else
        {
            _trace.ClearPosition();
        }
    }

    /// <summary>Session 프레임이 알려 주는 세션 맥락(트랙·종류·모드·링크 식별자)을 최신 값으로 보관한다.</summary>
    private void UpdateSessionContext(SessionFrame sf)
    {
        _carState.OnSession(sf);
        _sessionType = sf.SessionType;
        _trackId = sf.TrackId;
        _gameMode = sf.GameMode;
        _seasonLinkId = sf.SeasonLinkId;
        _weekendLinkId = sf.WeekendLinkId;
        _sessionLinkId = sf.SessionLinkId;
    }

    private void AccumulateLapFlags(LapFrame lf)
    {
        if (lf.IsCurrentLapInvalid)
        {
            _lapInvalidAccum = true;
        }

        if (lf.IsOutOrInLap)
        {
            _outOrInLapAccum = true;
        }
    }

    private void ResetLapAccumulators()
    {
        _lapInvalidAccum = false;
        _outOrInLapAccum = false;
        _completedSector1Ms = 0;
        _completedSector2Ms = 0;
    }

    /// <summary>랩 상태와 함께 스냅샷·트레이스도 비운다(세션 시작·종료).</summary>
    private void ResetLapState()
    {
        _lastLapNumber = 0;
        _lastSector = -1;
        ResetLapAccumulators();
        _carState.Reset();
        _trace.Clear();
    }

    private void ResetSession()
    {
        _sessionRef = null;
        _sessionType = SessionType.Unknown;
        _trackId = 0;
        _gameMode = GameMode.Other;
        _seasonLinkId = 0;
        _weekendLinkId = 0;
        _sessionLinkId = 0;
        ResetLapState();
    }
}
