using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 플레이어 차량의 직전 상태를 유지하며 랩/섹터 전이를 <b>엣지 트리거</b>로 감지해 도메인 이벤트를 만든다
/// (docs/06 §3). 고주파 반복 프레임에는 이벤트를 만들지 않는다. 순수·결정론적(네트워크/시간 무의존).
/// 단일 세션·단일 플레이어 상태를 갖는 <b>상태 저장</b> 클래스이므로 스레드 안전하지 않다(파이프라인이 순차 처리).
/// </summary>
public sealed class LapAnalyzer
{
    private const int SectorFirst = 0;
    private const int SectorSecond = 1;

    // 세션 상태
    private string? _sessionRef;
    private SessionType _sessionType;
    private int _trackId;

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
            _ => Array.Empty<TelemetryEvent>(),
        };
    }

    private IReadOnlyList<TelemetryEvent> OnSession(SessionFrame sf)
    {
        if (_sessionRef == sf.SessionRef)
        {
            // 같은 세션의 반복 Session 패킷 — 최신 값만 갱신, 이벤트 없음.
            _sessionType = sf.SessionType;
            _trackId = sf.TrackId;
            return Array.Empty<TelemetryEvent>();
        }

        var events = new List<TelemetryEvent>(2);
        if (_sessionRef is not null)
        {
            // 세션 UID 변경 = 이전 세션 종료.
            events.Add(new SessionEnded(_sessionRef));
        }

        _sessionRef = sf.SessionRef;
        _sessionType = sf.SessionType;
        _trackId = sf.TrackId;
        ResetLapState();
        events.Add(new SessionStarted(sf.SessionRef, sf.TrackId, sf.SessionType));
        return events;
    }

    private IReadOnlyList<TelemetryEvent> OnLap(LapFrame lf)
    {
        // 세션 컨텍스트가 아직 없으면(Session 패킷 미수신) 무시. 스테일 세션 프레임도 무시.
        if (_sessionRef is null || lf.SessionRef != _sessionRef)
        {
            return Array.Empty<TelemetryEvent>();
        }

        // 랩 전환(N → N+1): 완료 랩 확정 + 새 랩 시작.
        if (lf.CurrentLapNumber > _lastLapNumber)
        {
            var events = new List<TelemetryEvent>(2);

            if (_lastLapNumber >= 1)
            {
                events.Add(BuildLapFinished(completedLapNumber: _lastLapNumber, totalMs: lf.LastLapTimeMs));
            }

            events.Add(new LapStarted(_sessionRef, lf.CurrentLapNumber));

            _lastLapNumber = lf.CurrentLapNumber;
            _lastSector = lf.CurrentSector;
            ResetLapAccumulators();

            // 새 랩의 첫 프레임 상태를 누적 시작.
            AccumulateLapFlags(lf);
            return events;
        }

        AccumulateLapFlags(lf);

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

        return Array.Empty<TelemetryEvent>();
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
        return Array.Empty<TelemetryEvent>();
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
            SessionType: _sessionType);
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

    private void ResetLapState()
    {
        _lastLapNumber = 0;
        _lastSector = -1;
        ResetLapAccumulators();
    }

    private void ResetSession()
    {
        _sessionRef = null;
        _sessionType = SessionType.Unknown;
        _trackId = 0;
        ResetLapState();
    }
}
