using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Import;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.Import.ImportTestData;

namespace SimCenter.Application.Tests.Seasons.Import;

/// <summary>docs/15 §12(D-55) 가져오기 서비스: 기록 세션 연결 + 랩 키 변경, 409, 400(줄 번호).</summary>
public sealed class SeasonImportServiceTests
{
    private static readonly Guid UserId = Id(1);

    private readonly Fakes _fakes = new();

    private SeasonImportService CreateService() => new(
        _fakes, _fakes, _fakes, _fakes, _fakes, _fakes, _fakes, _fakes, NullLogger<SeasonImportService>.Instance);

    [Fact]
    public async Task Import_attaches_linked_sessions_and_rekeys_their_laps()
    {
        var miami = _fakes.Tracks[6];
        var linked = MiamiQualifying(miami, UserId);
        _fakes.Unseasoned.AddRange(linked);
        var oldKey = linked[0].SessionKey;
        var lap = new Lap { Id = Id(800), UserId = UserId, GameCode = GameCodes.F1_25, SessionKey = oldKey };
        _fakes.Laps.Add(lap);

        var result = await CreateService().ImportAsync(UserId, new SeasonImportRequest(Summary));

        var season = Assert.Single(_fakes.AddedSeasons);
        Assert.Equal((MiamiSeasonLink, "F1Laps", GameMode.DriverCareer), (season.SeasonLinkId, season.ImportedFrom, season.GameMode));
        Assert.Equal(season.Id, result.SeasonId);
        Assert.Equal(3, result.AttachedSessionCount);
        Assert.All(linked, s =>
        {
            Assert.Equal(season.Id, s.SeasonId);
            Assert.Equal(GameMode.DriverCareer, s.GameMode);
            Assert.StartsWith("link:2160041047:2160041547:", s.SessionKey, StringComparison.Ordinal);
        });
        Assert.Equal(linked[0].SessionKey, lap.SessionKey);
        Assert.Equal(1, _fakes.SaveCount);
        Assert.Equal(1, _fakes.TransactionCount);
    }

    [Fact]
    public async Task Import_twice_with_same_link_is_conflict()
    {
        _fakes.Unseasoned.AddRange(MiamiQualifying(_fakes.Tracks[6], UserId));
        _fakes.ExistingSeasonLinks.Add(MiamiSeasonLink);

        await Assert.ThrowsAsync<ConflictException>(() => CreateService().ImportAsync(UserId, new SeasonImportRequest(Summary)));
        Assert.Empty(_fakes.AddedSeasons);
        Assert.Equal(0, _fakes.SaveCount);
    }

    [Fact]
    public async Task Import_of_same_name_without_link_is_conflict_and_preview_says_so()
    {
        var first = CreateService();
        await first.ImportAsync(UserId, new SeasonImportRequest(Summary));
        _fakes.ImportedSeasons.AddRange(_fakes.AddedSeasons);

        var preview = await CreateService().PreviewAsync(UserId, new SeasonImportRequest(Summary));
        Assert.True(preview.AlreadyImported);
        Assert.Null(preview.LinkCandidate);
        await Assert.ThrowsAsync<ConflictException>(() => CreateService().ImportAsync(UserId, new SeasonImportRequest(Summary)));
    }

    [Fact]
    public async Task Preview_does_not_save_or_move_sessions()
    {
        var linked = MiamiQualifying(_fakes.Tracks[6], UserId);
        _fakes.Unseasoned.AddRange(linked);

        var preview = await CreateService().PreviewAsync(UserId, new SeasonImportRequest(All));

        Assert.Equal(3, preview.LinkCandidate!.Sessions.Count);
        Assert.Equal("Miami", preview.LinkCandidate.Sessions[0].TrackName);
        Assert.Equal(0, _fakes.SaveCount);
        Assert.Empty(_fakes.AddedSeasons);
        Assert.All(linked, s => Assert.Null(s.SeasonId));
    }

    [Fact]
    public async Task Bad_markdown_is_validation_error_with_line_number()
    {
        var markdown = Summary.Replace("| 2 | China | 14 |", "| 2 | China | x14 |", StringComparison.Ordinal);

        var error = await Assert.ThrowsAsync<ValidationException>(
            () => CreateService().PreviewAsync(UserId, new SeasonImportRequest(markdown)));

        Assert.StartsWith("10번째 줄:", error.Errors["markdown"][0], StringComparison.Ordinal);
        await Assert.ThrowsAsync<ValidationException>(() => CreateService().PreviewAsync(UserId, new SeasonImportRequest("  ")));
    }

    /// <summary>저장소·트랜잭션·시계·Id 가짜 한 묶음.</summary>
    private sealed class Fakes :
        ISeasonImportRepository, ISeasonRepository, IGameSessionRepository, ITrackRepository, IUnitOfWork, ITransactionRunner, IIdGenerator, IClock
    {
        private int _ids = 20_000;

        public Dictionary<int, Track> Tracks { get; } = ImportTestData.Tracks();

        public List<GameSession> Unseasoned { get; } = [];

        public List<Lap> Laps { get; } = [];

        public List<Season> AddedSeasons { get; } = [];

        public List<Season> ImportedSeasons { get; } = [];

        public HashSet<long> ExistingSeasonLinks { get; } = [];

        public int SaveCount { get; private set; }

        public int TransactionCount { get; private set; }

        public DateTime UtcNow => Now;

        public Guid NewId() => Id(_ids++);

        public Task<IReadOnlyList<GameSession>> GetUnseasonedLinkedSessionsAsync(
            Guid userId, string gameCode, IReadOnlyCollection<GameMode> modes, CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<GameSession>>(Unseasoned.Where(s => s.SeasonId is null && modes.Contains(s.GameMode)).ToList());

        public Task<IReadOnlyList<Season>> GetImportedSeasonsAsync(Guid userId, string gameCode, CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<Season>>(ImportedSeasons);

        public Task<IReadOnlyList<GameSession>> GetImportedSessionsOfDeletedSeasonsAsync(
            Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<GameSession>>([]);

        public Task<bool> SessionKeyInUseAsync(Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task<IReadOnlyList<Lap>> GetLapsBySessionKeyAsync(
            Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<Lap>>(Laps.Where(l => l.SessionKey == sessionKey).ToList());

        public Task<Season?> GetByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
            => Task.FromResult(ExistingSeasonLinks.Contains(seasonLinkId)
                ? new Season { GameCode = gameCode, SeasonLinkId = seasonLinkId, ImportedFrom = "F1Laps" }
                : AddedSeasons.FirstOrDefault(s => s.SeasonLinkId == seasonLinkId));

        public Task<Season?> GetDeletedByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
            => Task.FromResult<Season?>(null);

        public Task<Season?> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
            => Task.FromResult<Season?>(null);

        public Task<IReadOnlyList<GameSession>> GetImportedSessionsAsync(Guid seasonId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<RaceWeekend?> GetWeekendAsync(Guid seasonId, long weekendLinkId, CancellationToken cancellationToken = default)
            => Task.FromResult<RaceWeekend?>(null);

        public Task AddAsync(Season season, CancellationToken cancellationToken = default)
        {
            AddedSeasons.Add(season);
            return Task.CompletedTask;
        }

        public Task AddWeekendAsync(RaceWeekend weekend, CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<GameSession?> GetByKeyWithResultsAsync(
            Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
            => Task.FromResult<GameSession?>(null);

        public Task AddAsync(GameSession session, CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken cancellationToken = default)
            => Task.FromResult<Track?>(null);

        public Task<Track?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
            => Task.FromResult(Tracks.Values.FirstOrDefault(t => t.Id == id));

        public Task<IReadOnlyList<Track>> GetAllAsync(CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<Track>>(Tracks.Values.ToList());

        public Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        {
            SaveCount++;
            return Task.FromResult(1);
        }

        public Task<T> RunAsync<T>(Func<CancellationToken, Task<T>> work, CancellationToken cancellationToken = default)
        {
            TransactionCount++;
            return work(cancellationToken);
        }
    }
}
