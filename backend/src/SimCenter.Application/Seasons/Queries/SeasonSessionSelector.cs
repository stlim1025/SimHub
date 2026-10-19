using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// Standings 계산 대상으로 선별된 결과(12 §7.3).
/// </summary>
/// <param name="CountedRows">계산 대상 세션의 모든 결과 행(입력 순서 유지). 같은 주말·같은 세션 종류의 옛 중복 세션은 빠진다.</param>
/// <param name="MainRaceSessionByWeekend">주말 Id → 본 레이스 세션 Id. 레이스가 없는 주말은 키가 없다.</param>
public sealed record SeasonSelection(
    IReadOnlyList<SeasonResultRow> CountedRows,
    IReadOnlyDictionary<Guid, Guid> MainRaceSessionByWeekend);

/// <summary>
/// 시즌의 결과 행에서 계산 대상 세션과 주말별 본 레이스를 고른다(D-31). 순수 함수 — 상태 없음.
/// <list type="bullet">
/// <item>같은 <c>(WeekendId, SessionKind)</c>(<see cref="SessionKind.Unknown"/> 제외)는 <c>ClassifiedAt</c>이 가장 늦은 세션 1건만 남긴다
/// (링크 식별자가 바뀌어 같은 세션이 두 번 저장돼도 점수가 이중으로 더해지지 않게). 시각이 같으면 Id가 큰 쪽이다(결정적).</item>
/// <item>본 레이스 = 남은 세션 중 <see cref="SessionType.Race"/>이고 <c>ClassifiedAt</c>이 가장 늦은 세션. 스프린트 주말
/// (<see cref="SessionPositions.IsSprintWeekend"/>)의 <see cref="SessionKind.Race"/>(스프린트)는 후보가 아니다 — 본 레이스 전이면 그 주말에 본 레이스가 없다.
/// 슛아웃 없이 Race만 기록된 주말은 스프린트인지 알 수 없어 그 Race가 본 레이스다.</item>
/// </list>
/// </summary>
public static class SeasonSessionSelector
{
    public static SeasonSelection Select(IReadOnlyList<SeasonResultRow> rows)
    {
        ArgumentNullException.ThrowIfNull(rows);

        // 한 세션의 모든 행은 세션 속성(주말·종류·시각)이 같으므로 첫 행을 대표로 쓴다.
        var sessions = rows.GroupBy(r => r.SessionId).Select(g => g.First()).ToList();

        var keptSessions = KeepLatestPerKind(sessions);
        var keptIds = keptSessions.Select(s => s.SessionId).ToHashSet();

        var countedRows = rows.Where(r => keptIds.Contains(r.SessionId)).ToList();
        return new SeasonSelection(countedRows, MainRaceByWeekend(keptSessions));
    }

    private static List<SeasonResultRow> KeepLatestPerKind(IReadOnlyList<SeasonResultRow> sessions)
    {
        var kept = sessions.Where(s => s.SessionKind == SessionKind.Unknown).ToList();

        var knownKinds = sessions
            .Where(s => s.SessionKind != SessionKind.Unknown)
            .GroupBy(s => (s.WeekendId, s.SessionKind));
        foreach (var group in knownKinds)
        {
            kept.Add(Latest(group));
        }

        return kept;
    }

    private static Dictionary<Guid, Guid> MainRaceByWeekend(IEnumerable<SeasonResultRow> keptSessions)
    {
        var mainRaces = new Dictionary<Guid, Guid>();
        foreach (var weekend in keptSessions.GroupBy(s => s.WeekendId))
        {
            // 스프린트 주말(슛아웃·Race2가 있음)의 Race는 스프린트다 — 본 레이스 후보에서 뺀다(본 레이스 전이면 본 레이스 없음).
            var sprintWeekend = SessionPositions.IsSprintWeekend(weekend.Select(s => s.SessionKind));
            var races = weekend
                .Where(s => s.SessionType == SessionType.Race && !(sprintWeekend && s.SessionKind == SessionKind.Race))
                .ToList();
            if (races.Count > 0)
            {
                mainRaces[weekend.Key] = Latest(races).SessionId;
            }
        }

        return mainRaces;
    }

    private static SeasonResultRow Latest(IEnumerable<SeasonResultRow> sessions)
        => sessions.OrderByDescending(s => s.ClassifiedAt).ThenByDescending(s => s.SessionId).First();
}
