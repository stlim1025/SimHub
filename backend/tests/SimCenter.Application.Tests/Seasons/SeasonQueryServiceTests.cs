using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons;

public class SeasonQueryServiceTests
{
    private const string GameCode = "F1_25";
    private static readonly Guid UserId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private static readonly Guid OtherUserId = Guid.Parse("00000000-0000-0000-0000-0000000000a2");

    private readonly FakeSeasonQueries _repo = new();
    private readonly FakeSeasonOrder _order = new();
    private readonly FakeTracks _tracks = new();
    private readonly SeasonQueryService _sut;

    public SeasonQueryServiceTests()
    {
        _sut = new SeasonQueryService(_repo, _order, _tracks);
    }

    // ---- 입력 구성 ----

    private Season AddSeason(int number, DateTime? last = null, Guid? userId = null, GameMode mode = GameMode.DriverCareer)
    {
        var season = new Season
        {
            Id = Id(number),
            UserId = userId ?? UserId,
            GameCode = GameCode,
            SeasonLinkId = number,
            GameMode = mode,
            FirstSessionAt = At(1),
            LastSessionAt = last ?? At(100),
        };
        _repo.Seasons.Add(season);
        return season;
    }

    private void AddWeekend(int weekend, int season, string track, double firstHours)
        => _repo.Weekends.Add(new WeekendRow(Id(weekend), Id(season), track, At(firstHours)));

    /// <summary>시즌 1: 주말 2개(일부러 뒤집어 넣음), 둘째 주말은 스프린트 + 같은 스프린트의 옛 중복 + 본 레이스.</summary>
    private void ArrangeCareerSeason()
    {
        AddSeason(1);
        AddWeekend(weekend: 22, season: 1, "Jeddah", firstHours: 19);
        AddWeekend(weekend: 21, season: 1, "Bahrain", firstHours: 1);

        // 주말 1(Bahrain): 연습 · 예선 · 레이스
        _repo.Rows.AddRange(
        [
            Row(session: 1, weekend: 21, "driver:9", 1, 0, SessionType.Practice, SessionKind.Practice1, 1, "VERSTAPPEN", 0, 2),
            Row(session: 1, weekend: 21, "player", 4, 0, SessionType.Practice, SessionKind.Practice1, 1, "S. LIM", 3, 1, isPlayer: true, isAi: false),
            Row(session: 2, weekend: 21, "driver:9", 1, 0, SessionType.Qualifying, SessionKind.Qualifying1, 2, "VERSTAPPEN", 0, 2),
            Row(session: 2, weekend: 21, "player", 6, 0, SessionType.Qualifying, SessionKind.Qualifying1, 2, "S. LIM", 3, 1, isPlayer: true, isAi: false),
            Row(session: 3, weekend: 21, "driver:9", 1, 25, SessionType.Race, SessionKind.Race, 3, "VERSTAPPEN", 0, 2),
            Row(session: 3, weekend: 21, "driver:1", 2, 18, SessionType.Race, SessionKind.Race, 3, "NORRIS", 1, 8),
            Row(session: 3, weekend: 21, "player", 4, 12, SessionType.Race, SessionKind.Race, 3, "S. LIM", 3, 1, isPlayer: true, isAi: false),
        ]);

        // 주말 2(Jeddah): 스프린트(옛 중복 s6 포함) + 본 레이스
        _repo.Rows.AddRange(
        [
            Row(session: 6, weekend: 22, "player", 9, 3, SessionType.Race, SessionKind.Race, 19, "S. LIM", 3, 1, isPlayer: true, isAi: false),
            Row(session: 4, weekend: 22, "driver:1", 1, 8, SessionType.Race, SessionKind.Race, 20, "NORRIS", 1, 8),
            Row(session: 4, weekend: 22, "driver:9", 2, 7, SessionType.Race, SessionKind.Race, 20, "VERSTAPPEN", 0, 2),
            Row(session: 4, weekend: 22, "player", 3, 6, SessionType.Race, SessionKind.Race, 20, "S. LIM", 3, 1, isPlayer: true, isAi: false),
            Row(session: 5, weekend: 22, "driver:9", 1, 25, SessionType.Race, SessionKind.Race2, 24, "VERSTAPPEN", 0, 2),
            Row(session: 5, weekend: 22, "driver:1", 2, 18, SessionType.Race, SessionKind.Race2, 24, "NORRIS", 1, 8),
            Row(session: 5, weekend: 22, "player", 5, 10, SessionType.Race, SessionKind.Race2, 24, "S. LIM", 3, 1, isPlayer: true, isAi: false),
        ]);
    }

    // ---- 시즌 목록 ----

    [Fact]
    public async Task GetSeasons_MapsSummary_WithMyPositionAndLeader()
    {
        var season = AddSeason(1, last: At(50), mode: GameMode.GrandPrix);
        AddWeekend(weekend: 11, season: 1, "Bahrain", firstHours: 1);
        AddWeekend(weekend: 12, season: 1, "Jeddah", firstHours: 20);
        _repo.Rows.AddRange(
        [
            Row(session: 1, weekend: 11, "driver:9", 1, 25, name: "VERSTAPPEN", hours: 10),
            Row(session: 1, weekend: 11, "driver:5", 3, 15, name: "NORRIS", hours: 10),
            Row(session: 1, weekend: 11, "player", 2, 18, name: "S. LIM", isPlayer: true, isAi: false, hours: 10),
            Row(session: 2, weekend: 12, "driver:9", 1, 25, name: "VERSTAPPEN", hours: 20),
            Row(session: 2, weekend: 12, "driver:5", 2, 20, name: "NORRIS", hours: 20),
            Row(session: 2, weekend: 12, "player", 3, 15, name: "S. LIM", isPlayer: true, isAi: false, hours: 20),
        ]);

        var page = await _sut.GetMySeasonsAsync(UserId, 1, 20);

        var dto = Assert.Single(page.Items);
        Assert.Equal(season.Id, dto.SeasonId);
        Assert.Equal(GameCode, dto.GameCode);
        Assert.Equal("GrandPrix", dto.GameMode);
        Assert.Equal(season.FirstSessionAt, dto.FirstSessionAt);
        Assert.Equal(season.LastSessionAt, dto.LastSessionAt);
        Assert.Equal(2, dto.RoundCount);
        Assert.Equal(3, dto.MyPosition);     // VERSTAPPEN 50, NORRIS 35, 나 33
        Assert.Equal(33, dto.MyPoints);
        Assert.Equal("VERSTAPPEN", dto.LeaderName);
        Assert.Equal(50, dto.LeaderPoints);
    }

    [Fact]
    public async Task GetSeasons_PassesGameCodeFilterToRepository()
    {
        await _sut.GetMySeasonsAsync(UserId, 1, 20, "F1_26");

        Assert.Equal("F1_26", _repo.LastGameCode);
    }

    [Fact]
    public async Task GetSeasons_PlayerAbsent_MyFieldsNull()
    {
        AddSeason(1);
        AddWeekend(weekend: 11, season: 1, "Bahrain", firstHours: 1);
        _repo.Rows.Add(Row(session: 1, weekend: 11, "driver:9", 1, 25, name: "VERSTAPPEN", hours: 10));

        var page = await _sut.GetMySeasonsAsync(UserId, 1, 20);

        var dto = Assert.Single(page.Items);
        Assert.Null(dto.MyPosition);
        Assert.Null(dto.MyPoints);
        Assert.Equal("VERSTAPPEN", dto.LeaderName);
    }

    [Fact]
    public async Task GetSeasons_NoResults_LeaderNull()
    {
        AddSeason(1);
        AddWeekend(weekend: 11, season: 1, "Bahrain", firstHours: 1);

        var page = await _sut.GetMySeasonsAsync(UserId, 1, 20);

        var dto = Assert.Single(page.Items);
        Assert.Equal(1, dto.RoundCount);
        Assert.Null(dto.LeaderName);
        Assert.Null(dto.LeaderPoints);
        Assert.Null(dto.MyPosition);
        Assert.Null(dto.MyPoints);
    }

    [Fact]
    public async Task GetSeasons_NoSeasons_ReturnsEmptyPageWithoutReadingRows()
    {
        var page = await _sut.GetMySeasonsAsync(UserId, 1, 20);

        Assert.Empty(page.Items);
        Assert.Equal(0, page.Total);
        Assert.Equal(0, _repo.ResultRowsCalls);
        Assert.Equal(0, _repo.WeekendRowsCalls);
    }

    [Fact]
    public async Task GetSeasons_ManySeasons_LoadsResultRowsOnce()
    {
        foreach (var (season, weekend, leader, hours) in new[] { (1, 11, "ALPHA", 10d), (2, 12, "BRAVO", 20d), (3, 13, "CHARLIE", 30d) })
        {
            AddSeason(season, last: At(hours));
            AddWeekend(weekend, season, $"Track {season}", firstHours: hours);
            _repo.Rows.Add(Row(session: season, weekend, $"driver:{season}", 1, 25, name: leader, hours: hours, season: season));
        }

        var page = await _sut.GetMySeasonsAsync(UserId, 1, 20);

        Assert.Equal(1, _repo.ResultRowsCalls);
        Assert.True(_repo.LastScoringRowsOnly);
        Assert.Equal(1, _repo.WeekendRowsCalls);
        Assert.Equal(3, _repo.LastResultSeasonIds!.Count);
        // LastSessionAt 내림차순(저장소 순서 그대로), 시즌마다 자기 행으로 선두를 계산한다.
        Assert.Equal(new[] { "CHARLIE", "BRAVO", "ALPHA" }, page.Items.Select(i => i.LeaderName));
        Assert.All(page.Items, i => Assert.Equal(1, i.RoundCount));
    }

    [Theory]
    [InlineData(0, 0, 1, 20, 0)]
    [InlineData(-3, -1, 1, 20, 0)]
    [InlineData(1, 50, 1, 20, 0)]
    [InlineData(3, 50, 3, 20, 40)]
    [InlineData(2, 7, 2, 7, 7)]
    public async Task GetSeasons_ClampsPaging(int page, int pageSize, int expectedPage, int expectedSize, int expectedSkip)
    {
        var result = await _sut.GetMySeasonsAsync(UserId, page, pageSize);

        Assert.Equal(expectedPage, result.Page);
        Assert.Equal(expectedSize, result.PageSize);
        Assert.Equal(expectedSkip, _repo.LastSkip);
        Assert.Equal(expectedSize, _repo.LastTake);
        Assert.Equal(UserId, _repo.LastUserId);
    }

    [Fact]
    public async Task GetSeasons_HugePage_DoesNotOverflowSkip()
    {
        var result = await _sut.GetMySeasonsAsync(UserId, int.MaxValue, 20);

        Assert.Equal(int.MaxValue, result.Page);
        Assert.True(_repo.LastSkip >= 0);
    }

    [Fact]
    public async Task GetSeasons_OnlyOwnSeasons()
    {
        AddSeason(1);
        AddSeason(2, userId: OtherUserId);

        var page = await _sut.GetMySeasonsAsync(UserId, 1, 20);

        Assert.Equal(1, page.Total);
        Assert.Equal(Id(1), Assert.Single(page.Items).SeasonId);
    }

    // ---- 시즌 상세 ----

    [Fact]
    public async Task GetSeason_BuildsRoundsAndStandings()
    {
        ArrangeCareerSeason();

        var detail = await _sut.GetMySeasonAsync(UserId, Id(1));

        // 라운드는 FirstSessionAt 순서로 번호를 매긴다(저장소가 뒤집어 돌려줘도).
        Assert.Collection(detail.Rounds,
            r =>
            {
                Assert.Equal((1, Id(21), "Bahrain"), (r.Round, r.WeekendId, r.TrackName));
                Assert.Equal(At(1), r.FirstSessionAt);
                Assert.Equal("VERSTAPPEN", r.WinnerName);
                Assert.Equal(12, r.MyPoints);
            },
            r =>
            {
                Assert.Equal((2, Id(22), "Jeddah"), (r.Round, r.WeekendId, r.TrackName));
                Assert.Equal("VERSTAPPEN", r.WinnerName);   // 본 레이스(Race2)의 우승자 — 스프린트 우승자(NORRIS)가 아님
                Assert.Equal(16, r.MyPoints);               // 스프린트 6 + 본 레이스 10. 옛 중복 스프린트의 3점은 빠진다
            });

        var drivers = detail.Standings.Drivers;
        Assert.Equal(new[] { "driver:9", "driver:1", "player" }, drivers.Select(d => d.DriverKey));
        Assert.Equal(new[] { 57, 44, 28 }, drivers.Select(d => d.Points));
        Assert.Equal(new[] { 1, 2, 3 }, drivers.Select(d => d.Position));

        var leader = drivers[0];
        Assert.Equal("VERSTAPPEN", leader.Name);
        Assert.Equal("Red Bull Racing", leader.TeamName);
        Assert.Equal("#3671C6", leader.TeamColor);
        Assert.Equal((2, 2), (leader.Wins, leader.Podiums));   // 스프린트 2위는 포디움이 아니다
        Assert.Collection(leader.Cells,
            c => Assert.Equal((1, 1, "Finished", 25), (c.Round, c.Position, c.ResultStatus, c.Points)),
            c => Assert.Equal((2, 1, "Finished", 32), (c.Round, c.Position, c.ResultStatus, c.Points)));

        var me = drivers[2];
        Assert.True(me.IsPlayer);
        Assert.False(me.IsAiControlled);
        Assert.Equal("Ferrari", me.TeamName);
        Assert.Equal(new[] { 4, 5 }, me.Cells.Select(c => c.Position ?? 0));

        Assert.Equal(
            new[] { (1, 2, "Red Bull Racing", 57, 2), (2, 8, "McLaren", 44, 0), (3, 1, "Ferrari", 28, 0) },
            detail.Standings.Constructors.Select(c => (c.Position, c.TeamId, c.TeamName, c.Points, c.Wins)));
        Assert.Equal("#FF8000", detail.Standings.Constructors[1].TeamColor);
    }

    [Fact]
    public async Task GetSeason_Header_MatchesStandings()
    {
        ArrangeCareerSeason();

        var detail = await _sut.GetMySeasonAsync(UserId, Id(1));

        Assert.Equal(Id(1), detail.Season.SeasonId);
        Assert.Equal(2, detail.Season.RoundCount);
        Assert.Equal(3, detail.Season.MyPosition);
        Assert.Equal(28, detail.Season.MyPoints);
        Assert.Equal("VERSTAPPEN", detail.Season.LeaderName);
        Assert.Equal(57, detail.Season.LeaderPoints);
    }

    [Fact]
    public async Task GetSeason_SessionChips_ListAllSavedSessions_ByClassifiedAt()
    {
        ArrangeCareerSeason();

        var detail = await _sut.GetMySeasonAsync(UserId, Id(1));

        Assert.Equal(
            new[] { (Id(1), "Practice", "Practice1", 4), (Id(2), "Qualifying", "Qualifying1", 6), (Id(3), "Race", "Race", 4) },
            detail.Rounds[0].Sessions.Select(s => (s.SessionId, s.SessionType, s.SessionKind, s.MyPosition ?? 0)));
        // 둘째 주말: 옛 중복 스프린트(6)도 칩에는 남는다. ClassifiedAt 오름차순.
        Assert.Equal(new[] { Id(6), Id(4), Id(5) }, detail.Rounds[1].Sessions.Select(s => s.SessionId));
        Assert.All(detail.Rounds[1].Sessions, s => Assert.Equal("Finished", s.MyResultStatus));
    }

    [Fact]
    public async Task GetSeason_UsesAllRows_NotOnlyScoringRows()
    {
        ArrangeCareerSeason();

        await _sut.GetMySeasonAsync(UserId, Id(1));

        Assert.Equal(1, _repo.ResultRowsCalls);
        Assert.False(_repo.LastScoringRowsOnly);
        Assert.Equal(1, _repo.WeekendRowsCalls);
        Assert.Equal(new[] { Id(1) }, _repo.LastResultSeasonIds);
    }

    [Fact]
    public async Task GetSeason_NoPlayerInRound_MyFieldsNull_AndNoMainRace_WinnerNull()
    {
        AddSeason(1);
        AddWeekend(weekend: 11, season: 1, "Bahrain", firstHours: 1);
        AddWeekend(weekend: 12, season: 1, "Jeddah", firstHours: 20);
        _repo.Rows.AddRange(
        [
            Row(session: 1, weekend: 11, "driver:9", 1, 25, name: "VERSTAPPEN", hours: 10),
            Row(session: 2, weekend: 12, "driver:9", 1, 0, SessionType.Qualifying, SessionKind.Qualifying1, 20, "VERSTAPPEN"),
        ]);

        var detail = await _sut.GetMySeasonAsync(UserId, Id(1));

        Assert.Null(detail.Rounds[0].MyPoints);
        Assert.Null(detail.Rounds[0].Sessions.Single().MyPosition);
        Assert.Null(detail.Rounds[0].Sessions.Single().MyResultStatus);
        Assert.Null(detail.Rounds[1].WinnerName);
        // 예선만 있는 주말도 칸은 비어 있는 채로 나온다.
        var cells = detail.Standings.Drivers.Single().Cells;
        Assert.Equal(new[] { 1, 2 }, cells.Select(c => c.Round));
        Assert.Null(cells[1].Position);
        Assert.Null(cells[1].ResultStatus);
    }

    [Fact]
    public async Task GetSeason_NoResults_ReturnsEmptyStandings_AndRoundsWithoutSessions()
    {
        AddSeason(1);
        AddWeekend(weekend: 11, season: 1, "Bahrain", firstHours: 1);

        var detail = await _sut.GetMySeasonAsync(UserId, Id(1));

        var round = Assert.Single(detail.Rounds);
        Assert.Equal(1, round.Round);
        Assert.Null(round.WinnerName);
        Assert.Null(round.MyPoints);
        Assert.Empty(round.Sessions);
        Assert.Empty(detail.Standings.Drivers);
        Assert.Empty(detail.Standings.Constructors);
    }

    [Fact]
    public async Task GetSeason_NotMine_ThrowsNotFound()
    {
        AddSeason(1, userId: OtherUserId);

        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMySeasonAsync(UserId, Id(1)));

        Assert.Equal(0, _repo.WeekendRowsCalls);
        Assert.Equal(0, _repo.ResultRowsCalls);
    }

    [Fact]
    public async Task GetSeason_Unknown_ThrowsNotFound()
    {
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMySeasonAsync(UserId, Guid.NewGuid()));
    }

    // ---- 시즌 탭·헤더(docs/15 §12, D-54) ----

    [Fact]
    public async Task GetSeasons_MapsSeasonNumberAndMyDriverName()
    {
        ArrangeCareerSeason();
        _order.Rows.AddRange(
        [
            new(Id(9), GameCode, GameMode.DriverCareer, At(-50)),
            new(Id(1), GameCode, GameMode.DriverCareer, At(1)),
        ]);

        var page = await _sut.GetMySeasonsAsync(UserId, 1, 20);

        var dto = Assert.Single(page.Items);
        Assert.Equal((2, "S. LIM"), (dto.SeasonNumber, dto.MyDriverName));
        Assert.Equal(1, _order.Calls);
    }

    [Fact]
    public async Task GetSeason_Calendar_ListsAllCalendarTracks_WithMyRoundValues()
    {
        ArrangeCareerSeason();
        _order.Rows.Add(new(Id(1), GameCode, GameMode.DriverCareer, At(1)));
        _tracks.Tracks.AddRange(
        [
            new Track { Id = Id(201), GameCode = GameCode, Name = "Bahrain", CountryCode = "BH", DisplayOrder = 1 },
            new Track { Id = Id(202), GameCode = GameCode, Name = "Jeddah", CountryCode = "SA", DisplayOrder = 2 },
            new Track { Id = Id(203), GameCode = GameCode, Name = "Suzuka", CountryCode = "JP", DisplayOrder = 3 },
        ]);
        _repo.Weekends.Clear();
        _repo.Weekends.Add(new WeekendRow(Id(22), Id(1), "Jeddah", At(19), 2, TrackId: Id(202)));
        _repo.Weekends.Add(new WeekendRow(Id(21), Id(1), "Bahrain", At(1), 1, TrackId: Id(201)));

        var detail = await _sut.GetMySeasonAsync(UserId, Id(1));

        Assert.Equal(1, detail.Season.SeasonNumber);
        Assert.Equal(new[] { "Bahrain", "Jeddah", "Suzuka" }, detail.Calendar.Select(r => r.TrackName));
        var bahrain = detail.Calendar[0];
        Assert.Equal((Id(3), 4, 12, 6), (bahrain.RaceSessionId!.Value, bahrain.RacePosition, bahrain.Points, bahrain.QualiPosition));
        var jeddah = detail.Calendar[1];
        Assert.Equal((Id(5), 5, 16), (jeddah.RaceSessionId!.Value, jeddah.RacePosition, jeddah.Points));  // 옛 중복 스프린트 제외
        var suzuka = detail.Calendar[2];
        Assert.Null(suzuka.WeekendId);
        Assert.Equal("Ferrari", suzuka.MyTeamName);   // 달리지 않은 라운드 = 시즌 팀
        Assert.Equal(1, _tracks.Calls);
    }

    // ---- Fake ----

    private sealed class FakeSeasonOrder : ISessionDetailQueryRepository
    {
        public List<SimCenter.Application.Seasons.Queries.Detail.SeasonOrderRow> Rows { get; } = new();
        public int Calls { get; private set; }

        public Task<IReadOnlyList<SimCenter.Application.Seasons.Queries.Detail.SessionLapRow>> GetMySessionLapsAsync(
            Guid userId, string gameCode, Guid trackId, string sessionKey, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<WeekendQualifyingRow>> GetMyWeekendQualifyingAsync(
            Guid userId, Guid raceWeekendId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<bool> IsMySprintWeekendAsync(Guid userId, Guid raceWeekendId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<SimCenter.Application.Seasons.Queries.Detail.SeasonOrderRow>> GetMySeasonOrderAsync(
            Guid userId, CancellationToken cancellationToken = default)
        {
            Calls++;
            return Task.FromResult<IReadOnlyList<SimCenter.Application.Seasons.Queries.Detail.SeasonOrderRow>>(Rows);
        }
    }

    private sealed class FakeTracks : ITrackRepository
    {
        public List<Track> Tracks { get; } = new();
        public int Calls { get; private set; }

        public Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<Track?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<Track>> GetAllAsync(CancellationToken cancellationToken = default)
        {
            Calls++;
            return Task.FromResult<IReadOnlyList<Track>>(Tracks);
        }
    }

    private sealed class FakeSeasonQueries : ISeasonQueryRepository
    {
        public List<Season> Seasons { get; } = new();
        public List<WeekendRow> Weekends { get; } = new();
        public List<SeasonResultRow> Rows { get; } = new();

        public int ResultRowsCalls { get; private set; }
        public int WeekendRowsCalls { get; private set; }
        public bool? LastScoringRowsOnly { get; private set; }
        public IReadOnlyCollection<Guid>? LastResultSeasonIds { get; private set; }
        public Guid? LastUserId { get; private set; }
        public int? LastSkip { get; private set; }
        public int? LastTake { get; private set; }
        public string? LastGameCode { get; private set; }

        public Task<(IReadOnlyList<Season> Items, int Total)> GetMyPageAsync(Guid userId, int skip, int take, string? gameCode = null, CancellationToken cancellationToken = default)
        {
            LastUserId = userId;
            LastSkip = skip;
            LastTake = take;
            LastGameCode = gameCode;

            var mine = Seasons.Where(s => s.UserId == userId).ToList();
            IReadOnlyList<Season> items = mine
                .OrderByDescending(s => s.LastSessionAt)
                .ThenByDescending(s => s.Id)
                .Skip(skip)
                .Take(take)
                .ToList();
            return Task.FromResult((items, mine.Count));
        }

        public Task<Season?> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
            => Task.FromResult(Seasons.FirstOrDefault(s => s.UserId == userId && s.Id == seasonId));

        public Task<IReadOnlyList<WeekendRow>> GetWeekendRowsAsync(IReadOnlyCollection<Guid> seasonIds, CancellationToken cancellationToken = default)
        {
            WeekendRowsCalls++;
            return Task.FromResult<IReadOnlyList<WeekendRow>>(Weekends.Where(w => seasonIds.Contains(w.SeasonId)).ToList());
        }

        public Task<IReadOnlyList<SeasonResultRow>> GetResultRowsAsync(IReadOnlyCollection<Guid> seasonIds, bool scoringRowsOnly, CancellationToken cancellationToken = default)
        {
            ResultRowsCalls++;
            LastScoringRowsOnly = scoringRowsOnly;
            LastResultSeasonIds = seasonIds;

            var rows = Rows.Where(r => seasonIds.Contains(r.SeasonId));
            if (scoringRowsOnly)
            {
                rows = rows.Where(r => r.SessionType == SessionType.Race || r.Points > 0);
            }

            return Task.FromResult<IReadOnlyList<SeasonResultRow>>(rows.ToList());
        }
    }
}
