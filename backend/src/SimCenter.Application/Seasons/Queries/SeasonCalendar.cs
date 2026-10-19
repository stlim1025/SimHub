using SimCenter.Application.Common;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Import;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>게임 캘린더의 트랙 1개(<c>Track.DisplayOrder</c> = 캘린더 순서, D-43).</summary>
public sealed record CalendarTrack(Guid TrackId, string Name, string? CountryCode, int DisplayOrder);

/// <summary>
/// 시즌 탭 표(F1Laps 시즌 페이지, docs/15 §12·D-55). 순수 계산 — 상태 없음.
/// 캘린더 트랙마다 한 줄(그 트랙의 첫 주말을 붙임) + 캘린더 밖 트랙·같은 트랙 두 번째 주말은
/// 직전에 달린 줄 바로 뒤(없으면 맨 앞)에 시간 순으로 끼운다. 라운드 = 표 안 순번.
/// </summary>
public static class SeasonCalendar
{
    /// <summary>게임의 캘린더 트랙(DisplayOrder 1..캘린더 크기) 순서대로. 캘린더를 모르는 게임은 빈 목록.</summary>
    public static IReadOnlyList<CalendarTrack> CalendarOf(IEnumerable<Track> tracks, string gameCode)
    {
        ArgumentNullException.ThrowIfNull(tracks);

        var size = CalendarSize(gameCode);
        return tracks
            .Where(t => t.GameCode == gameCode && t.DisplayOrder >= 1 && t.DisplayOrder <= size)
            .GroupBy(t => t.DisplayOrder)
            .Select(g => g.OrderBy(t => t.Id).First())
            .OrderBy(t => t.DisplayOrder)
            .Select(t => new CalendarTrack(t.Id, t.Name, t.CountryCode, t.DisplayOrder))
            .ToList();
    }

    public static IReadOnlyList<SeasonCalendarRoundDto> Build(
        string gameCode,
        IReadOnlyList<CalendarTrack> calendar,
        IReadOnlyList<WeekendRow> weekends,
        SeasonSelection selection,
        int? seasonTeamId)
    {
        ArgumentNullException.ThrowIfNull(calendar);
        ArgumentNullException.ThrowIfNull(weekends);
        ArgumentNullException.ThrowIfNull(selection);

        var slots = PlaceWeekends(calendar, weekends);
        // 계산 대상 세션만 본다(옛 중복 세션 제외, D-31).
        var countedByWeekend = selection.CountedRows.ToLookup(r => r.WeekendId);

        return slots
            .Select((slot, index) => ToDto(index + 1, slot, gameCode, seasonTeamId, selection,
                slot.Weekend is { } w ? countedByWeekend[w.WeekendId] : []))
            .ToList();
    }

    private static int CalendarSize(string gameCode) => gameCode == GameCodes.F1_25 ? ImportCalendar.RoundCount : 0;

    // ---- 자리 배치 ----

    private sealed record Slot(Guid TrackId, string TrackName, string? CountryCode, WeekendRow? Weekend);

    private static List<Slot> PlaceWeekends(IReadOnlyList<CalendarTrack> calendar, IReadOnlyList<WeekendRow> weekends)
    {
        var ordered = weekends.OrderBy(w => w.FirstSessionAt).ThenBy(w => w.WeekendId).ToList();
        var calendarTrackIds = calendar.Select(c => c.TrackId).ToHashSet();
        var firstByTrack = ordered
            .Where(w => calendarTrackIds.Contains(w.TrackId))
            .GroupBy(w => w.TrackId)
            .ToDictionary(g => g.Key, g => g.First());

        var slots = calendar
            .Select(c => new Slot(c.TrackId, c.Name, c.CountryCode, firstByTrack.GetValueOrDefault(c.TrackId)))
            .ToList();

        var placed = firstByTrack.Values.Select(w => w.WeekendId).ToHashSet();
        foreach (var extra in ordered.Where(w => !placed.Contains(w.WeekendId)))
        {
            var after = slots.FindLastIndex(s => s.Weekend is { } w && w.FirstSessionAt <= extra.FirstSessionAt);
            slots.Insert(after + 1, new Slot(extra.TrackId, extra.TrackName, extra.CountryCode, extra));
        }

        return slots;
    }

    // ---- 한 줄 ----

    private static SeasonCalendarRoundDto ToDto(
        int round,
        Slot slot,
        string gameCode,
        int? seasonTeamId,
        SeasonSelection selection,
        IEnumerable<SeasonResultRow> countedRows)
    {
        var counted = countedRows.ToList();
        var mine = counted.Where(r => r.IsPlayer).ToList();

        // 스프린트 주말에 본 레이스(Race2) 전이면 선별 규칙이 본 레이스를 고르지 않는다 → 레이스 칸은 비고 스프린트 칸만 찬다.
        Guid? raceSessionId = slot.Weekend is { } w && selection.MainRaceSessionByWeekend.TryGetValue(w.WeekendId, out var id) ? id : null;
        var sprintWeekend = SessionPositions.IsSprintWeekend(counted.Select(r => r.SessionKind));

        var myRace = mine.Where(r => r.SessionId == raceSessionId).OrderBy(r => r.CarIndex).FirstOrDefault();
        var myRaces = mine.Where(r => r.SessionType == SessionType.Race).ToList();
        var myQuali = mine
            .Where(r => r.SessionType == SessionType.Qualifying && r.SessionKind.IsGrandPrixQualifying())
            .OrderByDescending(r => r.ClassifiedAt).ThenByDescending(r => r.SessionId).ThenBy(r => r.CarIndex)
            .FirstOrDefault();
        var raceHead = raceSessionId is { } race ? counted.FirstOrDefault(r => r.SessionId == race) : null;
        // 스프린트 주말의 Race(본 레이스가 아닌 것) = 스프린트.
        var mySprint = sprintWeekend
            ? mine.Where(r => r.SessionKind == SessionKind.Race && r.SessionId != raceSessionId)
                .OrderByDescending(r => r.ClassifiedAt).ThenBy(r => r.CarIndex).FirstOrDefault()
            : null;

        var teamId = myRace?.TeamId
            ?? mine.OrderByDescending(r => r.ClassifiedAt).FirstOrDefault(r => r.TeamId is not null)?.TeamId
            ?? seasonTeamId;
        var team = teamId is { } t ? TeamCatalog.Resolve(gameCode, t) : null;

        return new SeasonCalendarRoundDto(
            round,
            slot.TrackId,
            slot.TrackName,
            slot.CountryCode,
            slot.Weekend?.WeekendId,
            raceSessionId,
            // 옛 중복 세션(선별에서 빠진 것)이 아니라 계산 대상 세션 중 첫 세션.
            counted.OrderBy(r => r.ClassifiedAt).ThenBy(r => r.SessionId).FirstOrDefault()?.SessionId,
            team?.Name,
            team?.Color,
            SessionPositions.Known(myRace?.Position),
            myRaces.Count == 0 ? null : PointTotals.ToInt(myRaces.Sum(r => (long)r.Points)),
            SessionPositions.Known(myQuali?.Position),
            KnownDifficulty(raceHead?.AiDifficulty),
            KnownDifficulty(myQuali?.AiDifficulty),
            SessionPositions.Known(mySprint?.Position),
            sprintWeekend,
            WeekendSessions(counted, sprintWeekend));
    }

    /// <summary>그 주말 세션(계산 대상) 표시 순서대로 + 내 순위.</summary>
    private static List<SeasonCalendarSessionDto> WeekendSessions(IEnumerable<SeasonResultRow> counted, bool sprintWeekend)
        => counted
            .GroupBy(r => r.SessionId)
            .Select(g => g.ToList())
            .OrderBy(s => SessionPositions.WeekendOrder(s[0].SessionKind, sprintWeekend))
            .ThenBy(s => s[0].ClassifiedAt)
            .ThenBy(s => s[0].SessionId)
            .Select(s => new SeasonCalendarSessionDto(
                s[0].SessionId,
                s[0].SessionKind.ToString(),
                SessionPositions.Known(s.Where(r => r.IsPlayer).OrderBy(r => r.CarIndex).FirstOrDefault()?.Position)))
            .ToList();

    /// <summary>AI 난이도 0 = 모름(가져온 세션 등) → null.</summary>
    private static int? KnownDifficulty(int? value) => value is > 0 ? value : null;
}
