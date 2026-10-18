using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 세션 상세 F1Laps 카드 재료 조립(docs/15 §11.3·§11.4, D-53). 저장소가 읽어 온 값만으로 만드는 순수 계산 — 카드마다 빌더에 맡긴다.
/// 내 차 = 순위표의 플레이어 행(없으면 내 랩 스냅샷의 <c>lapData.carIndex</c>).
/// </summary>
public static class SessionDetailAssembler
{
    public static SessionDetailExtras Build(
        GameSession session,
        IReadOnlyList<SessionResult> results,
        IReadOnlyList<SessionLapRow> lapRows,
        IReadOnlyList<WeekendQualifyingRow> weekendQualifying)
    {
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(results);
        ArgumentNullException.ThrowIfNull(lapRows);
        ArgumentNullException.ThrowIfNull(weekendQualifying);

        var myLaps = lapRows.Select(MySessionLap.From).ToList();
        var me = results.Where(r => r.IsPlayer).OrderBy(r => r.CarIndex).FirstOrDefault();
        var playerCarIndex = me?.CarIndex ?? myLaps.Select(l => l.PlayerCarIndex).FirstOrDefault(c => c.HasValue);
        var stints = StintSpan.From(me);
        var history = SessionHistory.Parse(session.Details);

        var laps = SessionLapsBuilder.Build(playerCarIndex, me?.GridPosition, history, stints, myLaps);

        return new SessionDetailExtras(
            QualifyingPositions(session, me, weekendQualifying),
            MyBestLap(lapRows),
            LatestLapValues.Setup(myLaps),
            laps,
            LatestLapValues.EngineWear(myLaps),
            TyreStintSeriesBuilder.Build(stints, laps, myLaps),
            SessionPenaltiesBuilder.Build(session.GameCode, playerCarIndex, results, myLaps),
            LatestLapValues.Weather(myLaps));
    }

    /// <summary>예선 세션일 때만: 같은 주말 예선들의 내 순위(종류 → 시각 순). 주말이 없으면 이 세션만.</summary>
    private static List<QualifyingPositionDto> QualifyingPositions(
        GameSession session, SessionResult? me, IReadOnlyList<WeekendQualifyingRow> weekendQualifying)
    {
        if (session.SessionType != SessionType.Qualifying)
        {
            return [];
        }

        var rows = weekendQualifying.Count > 0
            ? weekendQualifying
            : [new WeekendQualifyingRow(session.Id, session.SessionKind, session.ClassifiedAt, me?.Position)];

        return rows
            .Where(r => r.MyPosition is > 0)
            .OrderBy(r => r.SessionKind)
            .ThenBy(r => r.ClassifiedAt)
            .Select(r => new QualifyingPositionDto(r.SessionId, r.SessionKind.ToString(), r.MyPosition!.Value))
            .ToList();
    }

    /// <summary>유효 랩 중 가장 빠른 랩, 유효 랩이 없으면 가장 빠른 랩(같으면 먼저 완주한 랩). 랩이 없으면 null.</summary>
    private static MyBestLapDto? MyBestLap(IReadOnlyList<SessionLapRow> lapRows)
    {
        var timed = lapRows.Where(l => l.LapTimeMs > 0).ToList();
        var pool = timed.Any(l => l.IsValid) ? timed.Where(l => l.IsValid) : timed;
        var best = pool.OrderBy(l => l.LapTimeMs).ThenBy(l => l.SetAt).FirstOrDefault();
        return best is null ? null : new MyBestLapDto(best.LapId, best.LapTimeMs);
    }
}
