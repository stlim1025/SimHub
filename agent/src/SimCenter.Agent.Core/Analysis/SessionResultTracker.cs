using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 세션의 최종 순위표를 <see cref="SessionClassified"/> 1건으로 만든다(D-28, 12 §5.3).
/// 세션 맥락(<see cref="SessionFrame"/>)과 참가자(<see cref="ParticipantsFrame"/>)를 carIndex로 순위표(<see cref="ClassificationFrame"/>)에 결합한다.
/// <see cref="LapAnalyzer"/>와 상태를 공유하지 않는다 — 그래서 <c>SessionEnded</c>(세션 종료 마커)로 리셋되지 않는다
/// (종료 마커 뒤에 최종 순위표가 올 수 있다). 상태 저장이므로 스레드 안전하지 않다(파이프라인이 순차 처리).
/// </summary>
public sealed class SessionResultTracker : ITelemetryAnalyzer
{
    private SessionFrame? _context;
    private IReadOnlyDictionary<int, ParticipantInfo> _participants = new Dictionary<int, ParticipantInfo>();
    private string? _lastSentSessionRef;

    /// <summary>프레임 1개를 처리하고 그로 인해 발생한 도메인 이벤트(0..N)를 순서대로 반환한다.</summary>
    public IReadOnlyList<TelemetryEvent> Process(ITelemetryFrame frame)
    {
        return frame switch
        {
            SessionFrame sf => OnSession(sf),
            ParticipantsFrame pf => OnParticipants(pf),
            ClassificationFrame cf => OnClassification(cf),
            _ => Array.Empty<TelemetryEvent>(),
        };
    }

    private IReadOnlyList<TelemetryEvent> OnSession(SessionFrame sf)
    {
        // Session 패킷은 초당 2회 온다 — 같은 세션이면 맥락만 갱신하고 참가자는 지키며, 세션이 바뀔 때만 비운다.
        if (_context?.SessionRef != sf.SessionRef)
        {
            _participants = new Dictionary<int, ParticipantInfo>();
        }

        _context = sf;
        return Array.Empty<TelemetryEvent>();
    }

    private IReadOnlyList<TelemetryEvent> OnParticipants(ParticipantsFrame pf)
    {
        if (_context is null || _context.SessionRef != pf.SessionRef)
        {
            return Array.Empty<TelemetryEvent>();
        }

        // 최신 목록이 이전 목록을 통째로 대체한다. carIndex가 겹치면 뒤의 것이 이긴다(예외 없이).
        var byCar = new Dictionary<int, ParticipantInfo>(pf.Participants.Count);
        foreach (var participant in pf.Participants)
        {
            byCar[participant.CarIndex] = participant;
        }

        _participants = byCar;
        return Array.Empty<TelemetryEvent>();
    }

    private IReadOnlyList<TelemetryEvent> OnClassification(ClassificationFrame cf)
    {
        var context = _context;
        if (context is null
            || context.SessionRef != cf.SessionRef
            || context.SessionType == SessionType.TimeTrial   // D-30: Time Trial은 Laps·Leaderboard 담당
            || cf.SessionRef == _lastSentSessionRef           // 같은 세션은 한 번만 보낸다
            || cf.Rows.Count == 0)                        // 빈 순위표는 백엔드가 항상 거부한다 — 보내지도, 기억하지도 않는다
        {
            return Array.Empty<TelemetryEvent>();
        }

        var results = new List<ClassifiedResult>(cf.Rows.Count);
        foreach (var row in cf.Rows)
        {
            results.Add(ToResult(row, cf.PlayerCarIndex));
        }

        _lastSentSessionRef = cf.SessionRef;
        return new TelemetryEvent[]
        {
            new SessionClassified(
                SessionRef: cf.SessionRef,
                TrackId: context.TrackId,
                SessionType: context.SessionType,
                SessionKind: context.SessionKind,
                GameMode: context.GameMode,
                SeasonLinkId: context.SeasonLinkId,
                WeekendLinkId: context.WeekendLinkId,
                SessionLinkId: context.SessionLinkId,
                TotalLaps: context.TotalLaps,
                AiDifficulty: context.AiDifficulty,
                IsNetworkGame: context.IsNetworkGame,
                Results: results),
        };
    }

    private ClassifiedResult ToResult(ClassificationRow row, int playerCarIndex)
    {
        // 참가자 정보를 못 받은 차는 신원 필드를 null, AI 여부를 false로 보낸다(백엔드가 "Car {n}"으로 대체 표시).
        _participants.TryGetValue(row.CarIndex, out var participant);

        return new ClassifiedResult(
            CarIndex: row.CarIndex,
            IsPlayer: row.CarIndex == playerCarIndex,
            Position: row.Position,
            GridPosition: row.GridPosition,
            NumLaps: row.NumLaps,
            Points: row.Points,
            NumPitStops: row.NumPitStops,
            NumPenalties: row.NumPenalties,
            ResultStatus: row.ResultStatus,
            BestLapTimeMs: row.BestLapTimeMs,
            TotalRaceTimeMs: row.TotalRaceTimeMs,
            PenaltiesTimeMs: row.PenaltiesTimeMs,
            DriverName: participant?.Name,
            GameDriverId: participant?.GameDriverId,
            TeamId: participant?.TeamId,
            RaceNumber: participant?.RaceNumber,
            IsAiControlled: participant?.IsAiControlled ?? false,
            TyreStints: row.TyreStints);
    }
}
