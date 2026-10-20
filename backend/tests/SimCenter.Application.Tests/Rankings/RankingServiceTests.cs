using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;
using SimCenter.Application.Tests.Laps;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Rankings;

public class RankingServiceTests
{
    private const string GameCode = "F1_25";
    private static readonly DateTime Now = new(2026, 7, 15, 3, 0, 0, DateTimeKind.Utc);
    private static readonly Guid TrackId = Guid.Parse("00000000-0000-0000-0000-0000000000c7");
    private static readonly Guid UserId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");

    private readonly FakeLapRepository _laps = new();
    private readonly FakeLapQueryRepository _lapQueries = new();
    private readonly FakeTrackRepository _tracks = new();
    private readonly RankingService _sut;

    public RankingServiceTests()
    {
        _tracks.Items.Add(new Track { Id = TrackId, GameCode = GameCode, GameTrackId = 7, Name = "Silverstone" });
        _sut = CreateSut("Asia/Seoul", Now);
    }

    private RankingService CreateSut(string timeZoneId, DateTime now)
        => new(_laps, _lapQueries, _tracks, new FakeTimeZoneProvider(timeZoneId), new FakeClock(now));

    [Fact]
    public async Task GetRankingAsync_AssignsSequentialRanks_AndMapsSnapshot()
    {
        _laps.RankingRows =
        [
            new RankingLapRow(Guid.NewGuid(), "홍길동", 83452, Now, ShowOnLeaderboard: true),
            new RankingLapRow(Guid.NewGuid(), "김레이", 84010, Now, ShowOnLeaderboard: true),
        ];

        var snapshot = await _sut.GetRankingAsync(TrackId, GameCode, RankingPeriod.Monthly, date: null);

        Assert.Equal(TrackId, snapshot.TrackId);
        Assert.Equal("Silverstone", snapshot.TrackName);
        Assert.Equal("monthly", snapshot.Period);
        Assert.Equal("2026-07", snapshot.PeriodKey);
        Assert.Collection(snapshot.Entries,
            e => { Assert.Equal(1, e.Rank); Assert.Equal("홍길동", e.DisplayName); Assert.Equal(83452, e.BestLapTimeMs); },
            e => { Assert.Equal(2, e.Rank); Assert.Equal("김레이", e.DisplayName); Assert.Equal(84010, e.BestLapTimeMs); });

        // Time Trial·랭킹적격 필터가 리포지토리로 전달됐는지.
        Assert.Equal(SessionType.TimeTrial, _laps.LastSessionType);
        Assert.Equal(10, _laps.LastTop);
    }

    [Fact]
    public async Task GetRankingAsync_HiddenUser_ShowsAnonymousName_KeepingRankAndTime()
    {
        _laps.RankingRows =
        [
            new RankingLapRow(Guid.NewGuid(), "홍길동", 83452, Now, ShowOnLeaderboard: false),
            new RankingLapRow(Guid.NewGuid(), "김레이", 84010, Now, ShowOnLeaderboard: true),
        ];

        var snapshot = await _sut.GetRankingAsync(TrackId, GameCode, RankingPeriod.Monthly, date: null);

        Assert.Collection(snapshot.Entries,
            e =>
            {
                Assert.Equal(1, e.Rank);
                Assert.Equal(RankingPrivacy.AnonymousDisplayName, e.DisplayName);
                Assert.Equal(83452, e.BestLapTimeMs);
            },
            e => Assert.Equal("김레이", e.DisplayName));
        Assert.Equal("익명 드라이버", RankingPrivacy.AnonymousDisplayName);
    }

    [Fact]
    public async Task GetRankingAsync_UsesConfiguredTimeZone()
    {
        // Now = 2026-07-31T16:00:00Z: 서울(UTC+9)은 이미 8월 1일, UTC는 아직 7월 31일.
        var boundaryNow = new DateTime(2026, 7, 31, 16, 0, 0, DateTimeKind.Utc);

        var seoul = await CreateSut("Asia/Seoul", boundaryNow)
            .GetRankingAsync(TrackId, GameCode, RankingPeriod.Monthly, date: null);
        var utc = await CreateSut("UTC", boundaryNow)
            .GetRankingAsync(TrackId, GameCode, RankingPeriod.Monthly, date: null);

        Assert.Equal("2026-08", seoul.PeriodKey);
        Assert.Equal("2026-07", utc.PeriodKey);
    }

    [Fact]
    public async Task GetRankingAsync_UnknownTrack_Throws()
    {
        await Assert.ThrowsAsync<NotFoundException>(
            () => _sut.GetRankingAsync(Guid.NewGuid(), GameCode, RankingPeriod.Monthly, null));
    }

    [Fact]
    public async Task GetMyLapsAsync_WithTrack_IncludesPersonalBest()
    {
        _laps.PersonalBest = new Lap
        {
            Id = Guid.NewGuid(), UserId = UserId, TrackId = TrackId, GameCode = GameCode,
            SessionType = SessionType.TimeTrial, LapTimeMs = 83452, IsValid = true,
            IsRankingEligible = true, SetAt = Now,
        };
        _lapQueries.Laps.Add((UserId, FakeLapQueryRepository.Row(_laps.PersonalBest.Id, TrackId, 83452)));

        var result = await _sut.GetMyLapsAsync(
            UserId, TrackId, sessionType: null, validOnly: false, MyLapsSort.Recent, page: 1, pageSize: 20);

        Assert.NotNull(result.PersonalBest);
        Assert.Equal(83452, result.PersonalBest!.LapTimeMs);
        Assert.Equal(TrackId, result.PersonalBest.TrackId);
        Assert.Single(result.Laps.Items);
        Assert.Equal(1, result.Laps.Total);
    }

    [Fact]
    public async Task GetMyLapsAsync_PersonalBest_UsesTheTracksGameCode()
    {
        var track2026 = Guid.NewGuid();
        _tracks.Items.Add(new Track { Id = track2026, GameCode = "F1_26", GameTrackId = 7, Name = "Silverstone" });

        await _sut.GetMyLapsAsync(UserId, track2026, null, validOnly: false, MyLapsSort.Recent, 1, 20);

        Assert.Equal("F1_26", _laps.LastPersonalBestGameCode);
    }

    [Fact]
    public async Task GetMyTracks_WithGameCode_KeepsOnlyThatGame()
    {
        var at = new DateTime(2026, 7, 14, 10, 0, 0, DateTimeKind.Utc);
        _laps.TrackSummaries =
        [
            new MyTrackSummaryRow(TrackId, "Silverstone", GameCode, 5, 83452, at, "GB", 12),
            new MyTrackSummaryRow(Guid.NewGuid(), "Madrid (Madring)", "F1_26", 2, null, at, "ES", 16),
        ];

        var only2026 = await _sut.GetMyTracksAsync(UserId, "F1_26");
        var all = await _sut.GetMyTracksAsync(UserId);

        Assert.Equal("Madrid (Madring)", Assert.Single(only2026.Items).TrackName);
        Assert.Equal(2, all.Items.Count);
    }

    [Fact]
    public async Task GetTracks_WithGameCode_KeepsOnlyThatGame()
    {
        _tracks.Items.Add(new Track { Id = Guid.NewGuid(), GameCode = "F1_26", GameTrackId = 7, Name = "Silverstone 26" });

        var result = await _sut.GetTracksAsync("F1_26");

        Assert.Equal("Silverstone 26", Assert.Single(result.Items).Name);
    }

    [Fact]
    public async Task GetMyLapsAsync_WithoutTrack_OmitsPersonalBest()
    {
        var result = await _sut.GetMyLapsAsync(
            UserId, trackId: null, sessionType: null, validOnly: false, MyLapsSort.Recent, page: 1, pageSize: 20);

        Assert.Null(result.PersonalBest);
    }

    [Fact]
    public async Task GetMyLaps_PassesSortAndFiltersToRepository()
    {
        await _sut.GetMyLapsAsync(
            UserId, TrackId, SessionType.TimeTrial, validOnly: true, MyLapsSort.Fastest, page: 1, pageSize: 20);

        Assert.Equal(MyLapsSort.Fastest, _lapQueries.LastSort);
        Assert.Equal(new MyLapsFilter(TrackId, SessionType.TimeTrial, ValidOnly: true), _lapQueries.LastFilter);
    }

    [Fact]
    public async Task GetMyLaps_ValidOnly_ReturnsOnlyValidLaps()
    {
        _lapQueries.Laps.Add((UserId, FakeLapQueryRepository.Row(Guid.NewGuid(), TrackId, 90_000, isValid: false)));
        _lapQueries.Laps.Add((UserId, FakeLapQueryRepository.Row(Guid.NewGuid(), TrackId, 91_000)));

        var all = await _sut.GetMyLapsAsync(UserId, TrackId, null, validOnly: false, MyLapsSort.Recent, 1, 20);
        var valid = await _sut.GetMyLapsAsync(UserId, TrackId, null, validOnly: true, MyLapsSort.Recent, 1, 20);

        Assert.Equal(2, all.Laps.Total);
        Assert.Equal(91_000, Assert.Single(valid.Laps.Items).LapTimeMs);
        Assert.Equal(1, valid.Laps.Total);
    }

    [Fact]
    public async Task GetMyLaps_MapsDetailFields_TeamWeatherTraceModeLapNumber()
    {
        var withSnapshot = FakeLapQueryRepository.Row(
            Guid.NewGuid(), TrackId, 98_448, teamId: 1, weather: Weather.LightRain, hasTrace: true, gameMode: "DriverCareer");
        var oldLap = FakeLapQueryRepository.Row(Guid.NewGuid(), TrackId, 99_000);
        _lapQueries.Laps.Add((UserId, withSnapshot));
        _lapQueries.Laps.Add((UserId, oldLap));

        var result = await _sut.GetMyLapsAsync(UserId, null, null, validOnly: false, MyLapsSort.Recent, 1, 20);

        Assert.Collection(result.Laps.Items,
            lap =>
            {
                Assert.Equal(5, lap.LapNumber);
                Assert.Equal("DriverCareer", lap.GameMode);
                Assert.Equal(new TeamRefDto("Ferrari", "#E8002D"), lap.Team);
                Assert.Equal("LightRain", lap.Weather);
                Assert.True(lap.HasTrace);
                Assert.Equal("Jeddah", lap.TrackName);
                Assert.Equal("TimeTrial", lap.SessionType);
                Assert.Equal(2, lap.Sectors.Count);
            },
            lap =>
            {
                // 옛 랩(스냅샷·트레이스·모드 없음).
                Assert.Null(lap.GameMode);
                Assert.Null(lap.Team);
                Assert.Null(lap.Weather);
                Assert.False(lap.HasTrace);
            });
    }

    [Fact]
    public async Task GetMyTracks_MapsRowsInRepositoryOrder()
    {
        var otherTrackId = Guid.NewGuid();
        var newer = new DateTime(2026, 7, 14, 10, 0, 0, DateTimeKind.Utc);
        var older = new DateTime(2026, 7, 10, 10, 0, 0, DateTimeKind.Utc);
        _laps.TrackSummaries =
        [
            new MyTrackSummaryRow(TrackId, "Silverstone", GameCode, 5, 83452, newer, "GB", 12),
            new MyTrackSummaryRow(otherTrackId, "Suzuka", GameCode, 2, null, older, null, 0),
        ];

        var result = await _sut.GetMyTracksAsync(UserId);

        Assert.Equal(UserId, _laps.LastSummaryUserId);
        Assert.Collection(result.Items,
            t =>
            {
                Assert.Equal(TrackId, t.TrackId);
                Assert.Equal("Silverstone", t.TrackName);
                Assert.Equal(GameCode, t.GameCode);
                Assert.Equal(5, t.LapCount);
                Assert.Equal(83452, t.BestValidLapTimeMs);
                Assert.Equal(newer, t.LastSetAt);
                Assert.Equal("GB", t.CountryCode);
                Assert.Equal(12, t.DisplayOrder);
            },
            t =>
            {
                Assert.Equal(otherTrackId, t.TrackId);
                Assert.Equal("Suzuka", t.TrackName);
                Assert.Equal(2, t.LapCount);
                Assert.Null(t.BestValidLapTimeMs);
                Assert.Equal(older, t.LastSetAt);
                Assert.Null(t.CountryCode);
                Assert.Equal(0, t.DisplayOrder);
            });
    }

    [Fact]
    public async Task GetTracks_MapsCountryAndDisplayOrder_InRepositoryOrder()
    {
        // 순서(표시 순서 → 이름)는 리포지토리가 보장한다 — 서비스는 다시 정렬하지 않는다(D-43).
        _tracks.Items.Clear();
        var melbourne = new Track { Id = Guid.NewGuid(), GameCode = GameCode, GameTrackId = 0, Name = "Melbourne", CountryCode = "AU", DisplayOrder = 1 };
        var shanghai = new Track { Id = Guid.NewGuid(), GameCode = GameCode, GameTrackId = 2, Name = "Shanghai", CountryCode = "CN", DisplayOrder = 2 };
        _tracks.Items.AddRange([melbourne, shanghai]);

        var result = await _sut.GetTracksAsync();

        Assert.Collection(result.Items,
            t =>
            {
                Assert.Equal(melbourne.Id, t.TrackId);
                Assert.Equal("Melbourne", t.Name);
                Assert.Equal(GameCode, t.GameCode);
                Assert.Equal("AU", t.CountryCode);
                Assert.Equal(1, t.DisplayOrder);
            },
            t =>
            {
                Assert.Equal("Shanghai", t.Name);
                Assert.Equal("CN", t.CountryCode);
                Assert.Equal(2, t.DisplayOrder);
            });
    }

    [Fact]
    public async Task GetMyTracks_NoLaps_ReturnsEmpty()
    {
        _laps.TrackSummaries = [];

        var result = await _sut.GetMyTracksAsync(UserId);

        Assert.Empty(result.Items);
    }

    [Theory]
    [InlineData(0, 20)]     // page 하한 보정.
    [InlineData(1, 1000)]   // pageSize 상한 100.
    public async Task GetMyLapsAsync_ClampsPaging(int page, int pageSize)
    {
        var result = await _sut.GetMyLapsAsync(UserId, null, null, validOnly: false, MyLapsSort.Recent, page, pageSize);

        Assert.True(result.Laps.Page >= 1);
        Assert.True(result.Laps.PageSize is >= 1 and <= 100);
    }

    // ── Fakes ──

    private sealed class FakeLapRepository : ILapRepository
    {
        public IReadOnlyList<RankingLapRow> RankingRows { get; set; } = new List<RankingLapRow>();
        public Lap? PersonalBest { get; set; }
        public IReadOnlyList<MyTrackSummaryRow> TrackSummaries { get; set; } = new List<MyTrackSummaryRow>();
        public SessionType LastSessionType { get; private set; }
        public int LastTop { get; private set; }
        public Guid LastSummaryUserId { get; private set; }

        public Task AddAsync(Lap lap, CancellationToken ct = default) => Task.CompletedTask;

        public Task AddTraceAsync(LapTelemetryTrace trace, CancellationToken ct = default) => Task.CompletedTask;

        public Task<IReadOnlyList<RankingLapRow>> GetRankingAsync(
            Guid trackId, string gameCode, SessionType sessionType, DateTime fromUtc, DateTime toUtc, int top, CancellationToken ct = default)
        {
            LastSessionType = sessionType;
            LastTop = top;
            return Task.FromResult(RankingRows);
        }

        public Task<IReadOnlyList<MyTrackSummaryRow>> GetMyTrackSummariesAsync(Guid userId, CancellationToken ct = default)
        {
            LastSummaryUserId = userId;
            return Task.FromResult(TrackSummaries);
        }

        public string? LastPersonalBestGameCode { get; private set; }

        public Task<Lap?> GetPersonalBestLapAsync(Guid userId, Guid trackId, string gameCode, CancellationToken ct = default)
        {
            LastPersonalBestGameCode = gameCode;
            return Task.FromResult(PersonalBest);
        }
    }

    private sealed class FakeTrackRepository : ITrackRepository
    {
        public List<Track> Items { get; } = new();

        public Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.GameCode == gameCode && x.GameTrackId == gameTrackId));

        public Task<Track?> GetByIdAsync(Guid id, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.Id == id));

        public Task<IReadOnlyList<Track>> GetAllAsync(CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<Track>>(Items.ToList());
    }

    private sealed class FakeTimeZoneProvider : IRankingTimeZoneProvider
    {
        public FakeTimeZoneProvider(string timeZoneId) => TimeZoneId = timeZoneId;

        public string TimeZoneId { get; }
    }

    private sealed class FakeClock : IClock
    {
        public FakeClock(DateTime utcNow) => UtcNow = utcNow;

        public DateTime UtcNow { get; }
    }
}
