using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Rankings;
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
    private readonly FakeTrackRepository _tracks = new();
    private readonly FakeStoreRepository _stores = new();
    private readonly RankingService _sut;

    public RankingServiceTests()
    {
        _tracks.Items.Add(new Track { Id = TrackId, GameCode = GameCode, GameTrackId = 7, Name = "Silverstone" });
        _sut = new RankingService(_laps, _tracks, _stores, new FakeClock(Now));
    }

    [Fact]
    public async Task GetRankingAsync_AssignsSequentialRanks_AndMapsSnapshot()
    {
        _laps.RankingRows =
        [
            new RankingLapRow(Guid.NewGuid(), "홍길동", 83452, Now),
            new RankingLapRow(Guid.NewGuid(), "김레이", 84010, Now),
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
        _laps.MyLaps = ([_laps.PersonalBest], 1);

        var result = await _sut.GetMyLapsAsync(UserId, TrackId, sessionType: null, page: 1, pageSize: 20);

        Assert.NotNull(result.PersonalBest);
        Assert.Equal(83452, result.PersonalBest!.LapTimeMs);
        Assert.Equal(TrackId, result.PersonalBest.TrackId);
        Assert.Single(result.Laps.Items);
        Assert.Equal(1, result.Laps.Total);
    }

    [Fact]
    public async Task GetMyLapsAsync_WithoutTrack_OmitsPersonalBest()
    {
        _laps.MyLaps = ([], 0);

        var result = await _sut.GetMyLapsAsync(UserId, trackId: null, sessionType: null, page: 1, pageSize: 20);

        Assert.Null(result.PersonalBest);
    }

    [Theory]
    [InlineData(0, 20)]     // page 하한 보정.
    [InlineData(1, 1000)]   // pageSize 상한 100.
    public async Task GetMyLapsAsync_ClampsPaging(int page, int pageSize)
    {
        _laps.MyLaps = ([], 0);

        var result = await _sut.GetMyLapsAsync(UserId, null, null, page, pageSize);

        Assert.True(result.Laps.Page >= 1);
        Assert.True(result.Laps.PageSize is >= 1 and <= 100);
    }

    // ── Fakes ──

    private sealed class FakeLapRepository : ILapRepository
    {
        public IReadOnlyList<RankingLapRow> RankingRows { get; set; } = new List<RankingLapRow>();
        public (IReadOnlyList<Lap> Items, int Total) MyLaps { get; set; } = (new List<Lap>(), 0);
        public Lap? PersonalBest { get; set; }
        public SessionType LastSessionType { get; private set; }
        public int LastTop { get; private set; }

        public Task AddAsync(Lap lap, CancellationToken ct = default) => Task.CompletedTask;

        public Task<IReadOnlyList<RankingLapRow>> GetRankingAsync(
            Guid trackId, string gameCode, SessionType sessionType, DateTime fromUtc, DateTime toUtc, int top, CancellationToken ct = default)
        {
            LastSessionType = sessionType;
            LastTop = top;
            return Task.FromResult(RankingRows);
        }

        public Task<(IReadOnlyList<Lap> Items, int Total)> GetMyLapsAsync(
            Guid userId, Guid? trackId, SessionType? sessionType, int skip, int take, CancellationToken ct = default)
            => Task.FromResult(MyLaps);

        public Task<Lap?> GetPersonalBestLapAsync(Guid userId, Guid trackId, string gameCode, CancellationToken ct = default)
            => Task.FromResult(PersonalBest);
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

    private sealed class FakeStoreRepository : IStoreRepository
    {
        public Task<string> GetPrimaryTimeZoneIdAsync(CancellationToken ct = default)
            => Task.FromResult("Asia/Seoul");
    }

    private sealed class FakeClock : IClock
    {
        public FakeClock(DateTime utcNow) => UtcNow = utcNow;

        public DateTime UtcNow { get; }
    }
}
