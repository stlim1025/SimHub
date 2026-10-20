using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons;

/// <summary>시즌 탭 캘린더 표(docs/15 §12): 캘린더 전부 + 캘린더 밖 주말 끼우기 + 라운드별 내 값.</summary>
public class SeasonCalendarTests
{
    private const string GameCode = "F1_25";
    private const int Ferrari = 1;
    private const int McLaren = 8;

    private static readonly IReadOnlyList<CalendarTrack> Calendar =
    [
        new(Id(101), "Melbourne", "AU", 1),
        new(Id(102), "Shanghai", "CN", 2),
        new(Id(103), "Suzuka", "JP", 3),
    ];

    private static WeekendRow Weekend(int weekend, int track, string name, double hours, int order)
        => new(Id(weekend), Id(1), name, At(hours), order, TrackId: Id(track), CountryCode: "XX");

    private static IReadOnlyList<SeasonCalendarRoundDto> Build(
        IReadOnlyList<WeekendRow> weekends, IReadOnlyList<SeasonResultRow> rows, int? seasonTeamId = Ferrari)
        => SeasonCalendar.Build(GameCode, Calendar, weekends, SeasonSessionSelector.Select(rows), seasonTeamId);

    [Fact]
    public void CalendarOf_KeepsGameCalendarTracksInDisplayOrder()
    {
        var tracks = new[]
        {
            new Track { Id = Id(2), GameCode = GameCode, Name = "B", DisplayOrder = 2 },
            new Track { Id = Id(1), GameCode = GameCode, Name = "A", DisplayOrder = 1, CountryCode = "AU" },
            new Track { Id = Id(25), GameCode = GameCode, Name = "Reverse", DisplayOrder = 25 },
            new Track { Id = Id(3), GameCode = "OTHER", Name = "C", DisplayOrder = 3 },
            new Track { Id = Id(4), GameCode = GameCode, Name = "Unordered", DisplayOrder = 0 },
        };

        var calendar = SeasonCalendar.CalendarOf(tracks, GameCode);

        Assert.Equal(new[] { ("A", "AU", 1), ("B", (string?)null, 2) }, calendar.Select(c => (c.Name, c.CountryCode, c.DisplayOrder)));
    }

    /// <summary>시드 트랙 일부(게임 m_trackId·F1 25 캘린더 순서) — 2026 캘린더 순서 확인용.</summary>
    private static Track[] SeededTracks() =>
    [
        new Track { Id = Id(300), GameCode = GameCode, GameTrackId = 30, Name = "Miami", DisplayOrder = 6 },
        new Track { Id = Id(327), GameCode = GameCode, GameTrackId = 27, Name = "Imola", DisplayOrder = 7 },
        new Track { Id = Id(305), GameCode = GameCode, GameTrackId = 5, Name = "Monaco", DisplayOrder = 8 },
        new Track { Id = Id(306), GameCode = GameCode, GameTrackId = 6, Name = "Montreal", DisplayOrder = 10 },
        new Track { Id = Id(311), GameCode = GameCode, GameTrackId = 11, Name = "Monza", DisplayOrder = 16 },
        new Track { Id = Id(320), GameCode = GameCode, GameTrackId = 20, Name = "Baku", DisplayOrder = 17 },
        new Track { Id = Id(342), GameCode = GameCode, GameTrackId = 42, Name = "Madrid (Madring)", DisplayOrder = 28 },
    ];

    [Fact]
    public void CalendarOf_Season2026_UsesThe2026Order_WithMadridAndWithoutImola()
    {
        var calendar = SeasonCalendar.CalendarOf(SeededTracks(), GameCode, season2026: true);

        Assert.Equal(
            new[] { "Miami", "Montreal", "Monaco", "Monza", "Madrid (Madring)", "Baku" },
            calendar.Select(c => c.Name));
        Assert.Equal(new[] { 1, 2, 3, 4, 5, 6 }, calendar.Select(c => c.DisplayOrder));
    }

    [Fact]
    public void CalendarOf_Default_KeepsF125Order()
    {
        var calendar = SeasonCalendar.CalendarOf(SeededTracks(), GameCode);

        Assert.Equal(new[] { "Miami", "Imola", "Monaco", "Montreal", "Monza", "Baku" }, calendar.Select(c => c.Name));
    }

    [Theory]
    [InlineData(220, true)]
    [InlineData(230, true)]
    [InlineData(476, true)]
    [InlineData(486, true)]
    [InlineData(1, false)]
    [InlineData(185, false)]
    public void IsSeason2026_DetectsSeasonPackTeams(int teamId, bool expected)
    {
        var rows = new[] { Row(1, 1, "a", 1, 25, teamId: teamId) };

        Assert.Equal(expected, SeasonCalendar.IsSeason2026(GameCode, rows));
    }

    [Fact]
    public void WithCalendarOrder_RenumbersWeekendsByCalendar_OutsideTracksGetZero()
    {
        var calendar = SeasonCalendar.CalendarOf(SeededTracks(), GameCode, season2026: true);
        var weekends = new[]
        {
            new WeekendRow(Id(1), Id(9), "Montreal", At(1), DisplayOrder: 10, CalendarRounds: true, TrackId: Id(306)),
            new WeekendRow(Id(2), Id(9), "Imola", At(2), DisplayOrder: 7, CalendarRounds: true, TrackId: Id(327)),
        };

        var renumbered = SeasonCalendar.WithCalendarOrder(weekends, calendar);

        Assert.Equal(new[] { 2, 0 }, renumbered.Select(w => w.DisplayOrder));
    }

    [Fact]
    public void Build_UndrivenRounds_ShowSeasonTeamOnly()
    {
        var rounds = Build([], []);

        Assert.Equal(new[] { 1, 2, 3 }, rounds.Select(r => r.Round));
        Assert.Equal(new[] { "Melbourne", "Shanghai", "Suzuka" }, rounds.Select(r => r.TrackName));
        var first = rounds[0];
        Assert.Equal((Id(101), "AU"), (first.TrackId, first.CountryCode));
        Assert.Equal(("Ferrari", "#E8002D"), (first.MyTeamName, first.MyTeamColor));
        Assert.Null(first.WeekendId);
        Assert.Null(first.RaceSessionId);
        Assert.Null(first.FirstSessionId);
        Assert.Null(first.RacePosition);
        Assert.Null(first.Points);
        Assert.Null(first.QualiPosition);
        Assert.Null(first.RaceAiDifficulty);
        Assert.Null(first.QualiAiDifficulty);
    }

    [Fact]
    public void Build_NoSeasonTeam_TeamNull()
    {
        var rounds = Build([], [], seasonTeamId: null);

        Assert.All(rounds, r => Assert.Null(r.MyTeamName));
    }

    [Fact]
    public void Build_DrivenRound_MapsRaceQualiPointsAndDifficulty()
    {
        WeekendRow[] weekends = [Weekend(21, 102, "Shanghai", 1, 2)];
        SeasonResultRow[] rows =
        [
            Row(1, 21, "player", 7, 0, SessionType.Practice, SessionKind.Practice1, 1, isPlayer: true, isAi: false) with { AiDifficulty = 90 },
            Row(2, 21, "player", 9, 0, SessionType.Qualifying, SessionKind.SprintShootout1, 2, isPlayer: true, isAi: false) with { AiDifficulty = 99 },
            Row(3, 21, "player", 4, 5, SessionType.Race, SessionKind.Race, 3, isPlayer: true, isAi: false, teamId: McLaren) with { AiDifficulty = 101 },
            Row(4, 21, "player", 6, 0, SessionType.Qualifying, SessionKind.Qualifying1, 4, isPlayer: true, isAi: false) with { AiDifficulty = 102 },
            Row(5, 21, "player", 3, 0, SessionType.Qualifying, SessionKind.Qualifying2, 5, isPlayer: true, isAi: false) with { AiDifficulty = 103 },
            Row(6, 21, "driver:9", 1, 25, SessionType.Race, SessionKind.Race2, 6) with { AiDifficulty = 104 },
            Row(6, 21, "player", 2, 18, SessionType.Race, SessionKind.Race2, 6, isPlayer: true, isAi: false, teamId: McLaren, carIndex: 1) with { AiDifficulty = 104 },
        ];

        var round = Build(weekends, rows)[1];

        Assert.Equal(Id(21), round.WeekendId);
        Assert.Equal(Id(6), round.RaceSessionId);      // 본 레이스(Race2), 스프린트 아님
        Assert.Equal(Id(1), round.FirstSessionId);
        Assert.Equal(2, round.RacePosition);
        Assert.Equal(23, round.Points);                 // 스프린트 5 + 본 레이스 18
        Assert.Equal(3, round.QualiPosition);           // 마지막 예선(Q2), 슛아웃 제외
        Assert.Equal((104, 103), (round.RaceAiDifficulty, round.QualiAiDifficulty));
        Assert.Equal("McLaren", round.MyTeamName);      // 그 라운드의 내 팀
    }

    [Fact]
    public void Build_SprintWeekend_SprintPositionAndSessionsInWeekendOrder()
    {
        WeekendRow[] weekends = [Weekend(21, 102, "Shanghai", 1, 2)];
        SeasonResultRow[] rows =
        [
            Row(1, 21, "player", 7, 0, SessionType.Practice, SessionKind.Practice1, 1, isPlayer: true, isAi: false),
            // 시각이 뒤섞여도 표시 순서는 연습 → 슛아웃 → 스프린트 → 예선 → 레이스.
            Row(4, 21, "player", 0, 0, SessionType.Qualifying, SessionKind.Qualifying1, 2, isPlayer: true, isAi: false),
            Row(2, 21, "player", 9, 0, SessionType.Qualifying, SessionKind.SprintShootout1, 3, isPlayer: true, isAi: false),
            Row(3, 21, "player", 4, 5, SessionType.Race, SessionKind.Race, 4, isPlayer: true, isAi: false),
            Row(6, 21, "player", 2, 18, SessionType.Race, SessionKind.Race2, 6, isPlayer: true, isAi: false),
        ];

        var round = Build(weekends, rows)[1];

        Assert.True(round.IsSprintWeekend);
        Assert.Equal(4, round.SprintPosition);
        Assert.Equal(2, round.RacePosition);
        Assert.Null(round.QualiPosition);               // 순위 0 = 모름
        Assert.Equal(
            new[] { (Id(1), "Practice1", (int?)7), (Id(2), "SprintShootout1", 9), (Id(3), "Race", 4), (Id(4), "Qualifying1", null), (Id(6), "Race2", 2) },
            round.Sessions.Select(s => (s.SessionId, s.SessionKind, s.MyPosition)));
    }

    [Fact]
    public void Build_SprintWeekendBeforeMainRace_SprintInSprintColumn_RaceEmpty()
    {
        // 슛아웃 → 스프린트(Race)까지만 달렸고 본 레이스(Race2)는 아직이다.
        WeekendRow[] weekends = [Weekend(21, 102, "Shanghai", 1, 2)];
        SeasonResultRow[] rows =
        [
            Row(2, 21, "player", 6, 0, SessionType.Qualifying, SessionKind.SprintShootout3, 2, isPlayer: true, isAi: false),
            Row(3, 21, "player", 1, 8, SessionType.Race, SessionKind.Race, 3, isPlayer: true, isAi: false),
        ];

        var round = Build(weekends, rows)[1];

        Assert.True(round.IsSprintWeekend);
        Assert.Equal(1, round.SprintPosition);
        Assert.Null(round.RacePosition);
        Assert.Null(round.RaceSessionId);
        Assert.Equal(8, round.Points);                  // 스프린트 점수는 그대로 더한다
        Assert.Equal(new[] { Id(2), Id(3) }, round.Sessions.Select(s => s.SessionId));
    }

    [Fact]
    public void Build_NormalWeekend_NoSprint()
    {
        WeekendRow[] weekends = [Weekend(21, 101, "Melbourne", 1, 1)];
        SeasonResultRow[] rows =
        [
            Row(2, 21, "player", 3, 15, SessionType.Race, SessionKind.Race, 2, isPlayer: true, isAi: false),
            Row(1, 21, "player", 5, 0, SessionType.Qualifying, SessionKind.ShortQualifying, 1, isPlayer: true, isAi: false),
        ];

        var round = Build(weekends, rows)[0];

        Assert.False(round.IsSprintWeekend);
        Assert.Null(round.SprintPosition);
        Assert.Equal(3, round.RacePosition);
        Assert.Equal(new[] { Id(1), Id(2) }, round.Sessions.Select(s => s.SessionId));
        Assert.Empty(Build([], [])[0].Sessions);
    }

    [Fact]
    public void Build_QualifyingOnlyRound_FirstSessionLink_AndUnknownDifficultyNull()
    {
        WeekendRow[] weekends = [Weekend(21, 101, "Melbourne", 1, 1)];
        SeasonResultRow[] rows =
        [
            Row(2, 21, "player", 5, 0, SessionType.Qualifying, SessionKind.ShortQualifying, 2, isPlayer: true, isAi: false),
            Row(1, 21, "player", 8, 0, SessionType.Practice, SessionKind.Practice1, 1, isPlayer: true, isAi: false),
        ];

        var round = Build(weekends, rows)[0];

        Assert.Null(round.RaceSessionId);
        Assert.Equal(Id(1), round.FirstSessionId);
        Assert.Null(round.RacePosition);
        Assert.Null(round.Points);
        Assert.Equal(5, round.QualiPosition);
        Assert.Null(round.QualiAiDifficulty);           // 0 = 모름
    }

    [Fact]
    public void Build_FirstSession_SkipsSupersededDuplicate()
    {
        WeekendRow[] weekends = [Weekend(21, 101, "Melbourne", 1, 1)];
        SeasonResultRow[] rows =
        [
            Row(1, 21, "player", 9, 0, SessionType.Practice, SessionKind.Practice1, 1, isPlayer: true, isAi: false),
            Row(2, 21, "player", 8, 0, SessionType.Practice, SessionKind.Practice1, 2, isPlayer: true, isAi: false),
            Row(3, 21, "player", 7, 0, SessionType.Practice, SessionKind.Practice2, 3, isPlayer: true, isAi: false),
        ];

        Assert.Equal(Id(2), Build(weekends, rows)[0].FirstSessionId);   // 옛 중복 P1(1)은 빠진다
    }

    [Fact]
    public void Build_OffCalendarWeekend_InsertedByTime()
    {
        WeekendRow[] weekends =
        [
            Weekend(21, 101, "Melbourne", 1, 1),
            Weekend(23, 103, "Suzuka", 30, 3),
            Weekend(22, 128, "Madrid (Madring)", 20, 28),
        ];

        var rounds = Build(weekends, []);

        // 직전에 달린 라운드(Melbourne) 바로 뒤.
        Assert.Equal(new[] { "Melbourne", "Madrid (Madring)", "Shanghai", "Suzuka" }, rounds.Select(r => r.TrackName));
        Assert.Equal(new[] { 1, 2, 3, 4 }, rounds.Select(r => r.Round));
        Assert.Equal((Id(128), "XX", Id(22)), (rounds[1].TrackId, rounds[1].CountryCode, rounds[1].WeekendId));
    }

    [Fact]
    public void Build_OffCalendarWeekendBeforeAnyDriven_GoesFirst_AndDuplicateTrackIsExtra()
    {
        WeekendRow[] weekends =
        [
            Weekend(22, 102, "Shanghai", 10, 2),
            Weekend(21, 128, "Madrid (Madring)", 1, 28),
            Weekend(23, 102, "Shanghai", 40, 2),
        ];

        var rounds = Build(weekends, []);

        Assert.Equal(new[] { "Madrid (Madring)", "Melbourne", "Shanghai", "Shanghai", "Suzuka" }, rounds.Select(r => r.TrackName));
        Assert.Equal(Id(22), rounds[2].WeekendId);      // 같은 트랙 첫 주말이 캘린더 자리
        Assert.Equal(Id(23), rounds[3].WeekendId);      // 둘째 주말은 직전에 달린 라운드 뒤
    }
}
