using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons;

public class SessionQueryServiceTests
{
    private const string GameCode = "F1_25";
    private static readonly Guid UserId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private static readonly Guid OtherUserId = Guid.Parse("00000000-0000-0000-0000-0000000000a2");

    private readonly FakeSessionQueries _sessions = new();
    private readonly FakeWeekendQueries _seasons = new();
    private readonly SessionQueryService _sut;

    public SessionQueryServiceTests()
    {
        _sut = new SessionQueryService(_sessions, _seasons);
    }

    // ---- 입력 구성 ----

    private static SessionSummaryRow SummaryRow(int? myBestLapTimeMs = 105_321, int id = 1) => new(
        SessionId: Id(id), ClassifiedAt: At(5), TrackName: "Spa",
        SessionType: SessionType.Race, SessionKind: SessionKind.Race2, GameMode: GameMode.DriverCareer,
        SeasonId: Id(900), CarCount: 22,
        MyPosition: 4, MyGridPosition: 6, MyResultStatus: ResultStatus.Finished,
        MyBestLapTimeMs: myBestLapTimeMs, MyPoints: 12);

    private static SessionResult Result(
        int carIndex,
        int position,
        int bestLapTimeMs = 0,
        int totalRaceTimeMs = 0,
        string? name = "DRIVER",
        int? teamId = 8,
        bool isPlayer = false,
        bool isDeleted = false,
        IEnumerable<SessionResultTyreStint>? stints = null)
        => new()
        {
            Id = Id(1000 + carIndex),
            GameSessionId = Id(1),
            CarIndex = carIndex,
            Position = position,
            GridPosition = position + 1,
            NumLaps = 15,
            Points = 10,
            NumPitStops = 1,
            NumPenalties = 2,
            ResultStatus = ResultStatus.Finished,
            BestLapTimeMs = bestLapTimeMs,
            TotalRaceTimeMs = totalRaceTimeMs,
            PenaltiesTimeMs = 5_000,
            DriverKey = isPlayer ? "player" : $"driver:{carIndex}",
            DriverName = name,
            TeamId = teamId,
            RaceNumber = 4,
            IsAiControlled = !isPlayer,
            IsPlayer = isPlayer,
            IsDeleted = isDeleted,
            TyreStints = stints?.ToList() ?? new List<SessionResultTyreStint>(),
        };

    private static SessionResultTyreStint Stint(int number, int endLap, TyreCompound visual, string? actual, bool isDeleted = false)
        => new() { Id = Id(2000 + number), StintNumber = number, EndLap = endLap, VisualCompound = visual, ActualCompound = actual, IsDeleted = isDeleted };

    private GameSession AddSession(Guid? userId = null, Guid? seasonId = null, Guid? weekendId = null, params SessionResult[] results)
    {
        var session = new GameSession
        {
            Id = Id(1),
            UserId = userId ?? UserId,
            AgentDeviceId = Id(50),
            SeasonId = seasonId,
            RaceWeekendId = weekendId,
            GameCode = GameCode,
            SessionKey = "link:1:2:3",
            SessionRef = "1",
            TrackId = Id(60),
            Track = new Track { Id = Id(60), GameCode = GameCode, GameTrackId = 10, Name = "Spa" },
            SessionType = SessionType.Race,
            SessionKind = SessionKind.Race,
            GameMode = GameMode.DriverCareer,
            TotalLaps = 15,
            AiDifficulty = 85,
            IsNetworkGame = false,
            ClassifiedAt = At(5),
            Results = results.ToList(),
        };
        _sessions.Detail = session;
        return session;
    }

    // ---- 목록 ----

    [Fact]
    public async Task GetSessions_PassesFilterAndPaging()
    {
        _sessions.Page = ([SummaryRow()], 31);

        var page = await _sut.GetMySessionsAsync(UserId, SessionType.Race, page: 2, pageSize: 15);

        Assert.Equal(UserId, _sessions.LastUserId);
        Assert.Equal(SessionType.Race, _sessions.LastSessionType);
        Assert.Equal(15, _sessions.LastSkip);
        Assert.Equal(15, _sessions.LastTake);
        Assert.Equal((2, 15, 31), (page.Page, page.PageSize, page.Total));
    }

    [Fact]
    public async Task GetSessions_MapsSummary()
    {
        _sessions.Page = ([SummaryRow()], 1);

        var page = await _sut.GetMySessionsAsync(UserId, null, 1, 15);

        var dto = Assert.Single(page.Items);
        Assert.Equal(Id(1), dto.SessionId);
        Assert.Equal(At(5), dto.ClassifiedAt);
        Assert.Equal("Spa", dto.TrackName);
        Assert.Equal(("Race", "Race2", "DriverCareer"), (dto.SessionType, dto.SessionKind, dto.GameMode));
        Assert.Equal(Id(900), dto.SeasonId);
        Assert.Equal(22, dto.CarCount);
        Assert.Equal((4, 6, "Finished"), (dto.MyPosition, dto.MyGridPosition, dto.MyResultStatus));
        Assert.Equal(105_321, dto.MyBestLapTimeMs);
        Assert.Equal(12, dto.MyPoints);
        Assert.Null(_sessions.LastSessionType);
    }

    [Fact]
    public async Task GetSessions_ZeroBestLap_IsNull()
    {
        _sessions.Page = ([SummaryRow(myBestLapTimeMs: 0)], 1);

        var page = await _sut.GetMySessionsAsync(UserId, null, 1, 15);

        Assert.Null(Assert.Single(page.Items).MyBestLapTimeMs);
    }

    [Fact]
    public async Task GetSessions_NoPlayerRow_MyFieldsStayNull()
    {
        _sessions.Page = ([SummaryRow() with
        {
            SeasonId = null, MyPosition = null, MyGridPosition = null, MyResultStatus = null, MyBestLapTimeMs = null, MyPoints = null,
        }], 1);

        var page = await _sut.GetMySessionsAsync(UserId, null, 1, 15);

        var dto = Assert.Single(page.Items);
        Assert.Null(dto.SeasonId);
        Assert.Null(dto.MyPosition);
        Assert.Null(dto.MyGridPosition);
        Assert.Null(dto.MyResultStatus);
        Assert.Null(dto.MyBestLapTimeMs);
        Assert.Null(dto.MyPoints);
    }

    [Theory]
    [InlineData(0, 0, 1, 20, 0)]
    [InlineData(-2, -5, 1, 20, 0)]
    [InlineData(1, 500, 1, 100, 0)]
    [InlineData(3, 100, 3, 100, 200)]
    [InlineData(2, 15, 2, 15, 15)]
    public async Task GetSessions_ClampsPaging(int page, int pageSize, int expectedPage, int expectedSize, int expectedSkip)
    {
        var result = await _sut.GetMySessionsAsync(UserId, null, page, pageSize);

        Assert.Equal((expectedPage, expectedSize), (result.Page, result.PageSize));
        Assert.Equal(expectedSkip, _sessions.LastSkip);
        Assert.Equal(expectedSize, _sessions.LastTake);
    }

    [Fact]
    public async Task GetSessions_HugePage_DoesNotOverflowSkip()
    {
        await _sut.GetMySessionsAsync(UserId, null, int.MaxValue, 100);

        Assert.True(_sessions.LastSkip >= 0);
    }

    // ---- 상세 ----

    [Fact]
    public async Task GetSession_MapsResults_FastestLapNullsAndFallbackName()
    {
        AddSession(
            results:
            [
                Result(carIndex: 5, position: 2, bestLapTimeMs: 90_000, totalRaceTimeMs: 1_600_000, name: "BRAVO"),
                Result(carIndex: 3, position: 1, bestLapTimeMs: 0, totalRaceTimeMs: 0, name: null, teamId: null),
                Result(carIndex: 1, position: 2, bestLapTimeMs: 89_000, totalRaceTimeMs: 1_599_000, name: "ALPHA", isPlayer: true,
                    stints:
                    [
                        Stint(2, endLap: 15, TyreCompound.Hard, "C2"),
                        Stint(1, endLap: 7, TyreCompound.Medium, "C3"),
                        Stint(3, endLap: 15, TyreCompound.Soft, "C4", isDeleted: true),
                    ]),
                Result(carIndex: 9, position: 4, name: "GONE", isDeleted: true),
            ]);

        var detail = await _sut.GetMySessionAsync(UserId, Id(1));

        // Position 오름차순, 같으면 CarIndex 오름차순. 삭제된 행은 빠진다.
        Assert.Equal(new[] { 3, 1, 5 }, detail.Results.Select(r => r.CarIndex));
        Assert.Equal(new[] { 1, 2, 2 }, detail.Results.Select(r => r.Position));

        var noData = detail.Results[0];
        Assert.Equal("Car 4", noData.Name);                 // DriverName null → "Car {carIndex+1}"
        Assert.Null(noData.BestLapTimeMs);                  // 0 → null
        Assert.False(noData.IsFastestLap);
        Assert.Null(noData.TotalRaceTimeMs);                // 0 → null
        Assert.Null(noData.TeamId);
        Assert.Equal("Unknown Team", noData.TeamName);
        Assert.Equal("#9CA3AF", noData.TeamColor);

        var fastest = detail.Results[1];
        Assert.True(fastest.IsFastestLap);
        Assert.Equal(89_000, fastest.BestLapTimeMs);
        Assert.Equal(1_599_000, fastest.TotalRaceTimeMs);
        Assert.Equal("ALPHA", fastest.Name);
        Assert.True(fastest.IsPlayer);
        Assert.False(fastest.IsAiControlled);
        Assert.Equal((8, "McLaren", "#FF8000"), (fastest.TeamId, fastest.TeamName, fastest.TeamColor));
        Assert.Equal(
            new (int, string, string?)[] { (7, "Medium", "C3"), (15, "Hard", "C2") },
            fastest.TyreStints.Select(s => (s.EndLap, s.VisualCompound, s.ActualCompound)));

        var slower = detail.Results[2];
        Assert.False(slower.IsFastestLap);
        Assert.Empty(slower.TyreStints);
    }

    [Fact]
    public async Task GetSession_MapsRowValues()
    {
        AddSession(results: [Result(carIndex: 0, position: 1, bestLapTimeMs: 104_987, totalRaceTimeMs: 1_598_765, name: "NORRIS")]);

        var row = Assert.Single((await _sut.GetMySessionAsync(UserId, Id(1))).Results);

        Assert.Equal(("NORRIS", 4, 2, 15), (row.Name, row.RaceNumber, row.GridPosition, row.NumLaps));
        Assert.Equal((5_000, 2, 1, 10, "Finished"), (row.PenaltiesTimeMs, row.NumPenalties, row.NumPitStops, row.Points, row.ResultStatus));
    }

    [Fact]
    public async Task GetSession_FastestLapTie_MarksAllTiedRows()
    {
        AddSession(
            results:
            [
                Result(carIndex: 0, position: 1, bestLapTimeMs: 90_000),
                Result(carIndex: 1, position: 2, bestLapTimeMs: 90_000),
                Result(carIndex: 2, position: 3, bestLapTimeMs: 91_000),
            ]);

        var detail = await _sut.GetMySessionAsync(UserId, Id(1));

        Assert.Equal(new[] { true, true, false }, detail.Results.Select(r => r.IsFastestLap));
    }

    [Fact]
    public async Task GetSession_NoBestLaps_NoFastestLap()
    {
        AddSession(results: [Result(carIndex: 0, position: 1), Result(carIndex: 1, position: 2)]);

        var detail = await _sut.GetMySessionAsync(UserId, Id(1));

        Assert.All(detail.Results, r => Assert.False(r.IsFastestLap));
    }

    [Fact]
    public async Task GetSession_Header_UsesPlayerRowAndNullRules()
    {
        AddSession(
            results:
            [
                Result(carIndex: 0, position: 1, bestLapTimeMs: 90_000),
                Result(carIndex: 2, position: 4, bestLapTimeMs: 0, isPlayer: true),
            ]);

        var header = (await _sut.GetMySessionAsync(UserId, Id(1))).Session;

        Assert.Equal(Id(1), header.SessionId);
        Assert.Equal(At(5), header.ClassifiedAt);
        Assert.Equal("Spa", header.TrackName);
        Assert.Equal(("Race", "Race", "DriverCareer"), (header.SessionType, header.SessionKind, header.GameMode));
        Assert.Equal(2, header.CarCount);
        Assert.Equal((4, 5, "Finished", 10), (header.MyPosition, header.MyGridPosition, header.MyResultStatus, header.MyPoints));
        Assert.Null(header.MyBestLapTimeMs);                // 내 베스트 랩 0 → null
        Assert.Equal((15, 85, false), (header.TotalLaps, header.AiDifficulty, header.IsNetworkGame));
        Assert.Null(header.SeasonId);
        Assert.Null(header.Round);
    }

    [Fact]
    public async Task GetSession_NoPlayerRow_MyFieldsNull()
    {
        AddSession(results: [Result(carIndex: 0, position: 1)]);

        var header = (await _sut.GetMySessionAsync(UserId, Id(1))).Session;

        Assert.Null(header.MyPosition);
        Assert.Null(header.MyGridPosition);
        Assert.Null(header.MyResultStatus);
        Assert.Null(header.MyBestLapTimeMs);
        Assert.Null(header.MyPoints);
    }

    [Fact]
    public async Task GetSession_InSeason_HasRoundMatchingSeason()
    {
        // 저장소가 뒤집어 돌려주어도 FirstSessionAt 순서(라운드 번호 계산)를 따른다. 이 세션의 주말은 두 번째 라운드다.
        _seasons.Weekends.AddRange(
        [
            new WeekendRow(Id(33), Id(900), "Monza", At(30)),
            new WeekendRow(Id(22), Id(900), "Spa", At(20)),
            new WeekendRow(Id(11), Id(900), "Bahrain", At(10)),
        ]);
        AddSession(seasonId: Id(900), weekendId: Id(22), results: [Result(carIndex: 0, position: 1)]);

        var header = (await _sut.GetMySessionAsync(UserId, Id(1))).Session;

        Assert.Equal(Id(900), header.SeasonId);
        Assert.Equal(2, header.Round);
        Assert.Equal(new[] { Id(900) }, _seasons.LastSeasonIds);
        Assert.Equal(1, _seasons.WeekendRowsCalls);
    }

    [Fact]
    public async Task GetSession_NotInSeason_RoundNull_AndNoWeekendLookup()
    {
        AddSession(results: [Result(carIndex: 0, position: 1)]);

        var header = (await _sut.GetMySessionAsync(UserId, Id(1))).Session;

        Assert.Null(header.Round);
        Assert.Equal(0, _seasons.WeekendRowsCalls);
    }

    [Fact]
    public async Task GetSession_WeekendMissingFromSeasonRows_RoundNull()
    {
        _seasons.Weekends.Add(new WeekendRow(Id(11), Id(900), "Bahrain", At(10)));
        AddSession(seasonId: Id(900), weekendId: Id(77), results: [Result(carIndex: 0, position: 1)]);

        var header = (await _sut.GetMySessionAsync(UserId, Id(1))).Session;

        Assert.Equal(Id(900), header.SeasonId);
        Assert.Null(header.Round);
    }

    [Fact]
    public async Task GetSession_NotMine_ThrowsNotFound()
    {
        AddSession(userId: OtherUserId, results: [Result(carIndex: 0, position: 1)]);

        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMySessionAsync(UserId, Id(1)));
    }

    [Fact]
    public async Task GetSession_Unknown_ThrowsNotFound()
    {
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMySessionAsync(UserId, Guid.NewGuid()));
    }

    // ---- Fake ----

    private sealed class FakeSessionQueries : IGameSessionQueryRepository
    {
        public (IReadOnlyList<SessionSummaryRow> Items, int Total) Page { get; set; } = ([], 0);
        public GameSession? Detail { get; set; }

        public Guid? LastUserId { get; private set; }
        public SessionType? LastSessionType { get; private set; }
        public int? LastSkip { get; private set; }
        public int? LastTake { get; private set; }

        public Task<(IReadOnlyList<SessionSummaryRow> Items, int Total)> GetMyPageAsync(
            Guid userId, SessionType? sessionType, int skip, int take, CancellationToken cancellationToken = default)
        {
            LastUserId = userId;
            LastSessionType = sessionType;
            LastSkip = skip;
            LastTake = take;
            return Task.FromResult(Page);
        }

        public Task<GameSession?> GetMineDetailAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
            => Task.FromResult(Detail is { } d && d.UserId == userId && d.Id == sessionId ? d : null);
    }

    /// <summary>세션 서비스가 쓰는 주말 조회만 구현한다.</summary>
    private sealed class FakeWeekendQueries : ISeasonQueryRepository
    {
        public List<WeekendRow> Weekends { get; } = new();
        public int WeekendRowsCalls { get; private set; }
        public IReadOnlyCollection<Guid>? LastSeasonIds { get; private set; }

        public Task<IReadOnlyList<WeekendRow>> GetWeekendRowsAsync(IReadOnlyCollection<Guid> seasonIds, CancellationToken cancellationToken = default)
        {
            WeekendRowsCalls++;
            LastSeasonIds = seasonIds;
            return Task.FromResult<IReadOnlyList<WeekendRow>>(Weekends.Where(w => seasonIds.Contains(w.SeasonId)).ToList());
        }

        public Task<(IReadOnlyList<Season> Items, int Total)> GetMyPageAsync(Guid userId, int skip, int take, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<Season?> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<SeasonResultRow>> GetResultRowsAsync(IReadOnlyCollection<Guid> seasonIds, bool scoringRowsOnly, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();
    }
}
