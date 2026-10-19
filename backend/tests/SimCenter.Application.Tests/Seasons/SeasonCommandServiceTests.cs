using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Commands;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Seasons;

public class SeasonCommandServiceTests
{
    private const string GameCode = "F1_25";
    private const string NameField = "name";
    private const string CompletedField = "completed";

    private static readonly DateTime Now = new(2026, 10, 20, 9, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime Earlier = Now.AddDays(-3);

    private readonly Guid _userId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private readonly Guid _otherUserId = Guid.Parse("00000000-0000-0000-0000-0000000000a2");

    private readonly FakeSeasons _seasons = new();
    private readonly FakeUnitOfWork _uow = new();
    private readonly SeasonCommandService _sut;

    public SeasonCommandServiceTests()
    {
        _sut = new SeasonCommandService(_seasons, _uow, new FakeClock(Now));
    }

    private Season AddSeason(Guid? userId = null)
    {
        var season = new Season
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? _userId,
            GameCode = GameCode,
            SeasonLinkId = 11,
            GameMode = GameMode.DriverCareer,
            FirstSessionAt = Earlier,
            LastSessionAt = Earlier,
            CreatedAt = Earlier,
        };
        _seasons.Items.Add(season);
        return season;
    }

    // ---- 이름 ----

    [Fact]
    public async Task Rename_TrimsAndSaves()
    {
        var season = AddSeason();

        await _sut.RenameAsync(_userId, season.Id, new RenameSeasonRequest("  My Ferrari Career  "));

        Assert.Equal("My Ferrari Career", season.Name);
        Assert.Equal(Now, season.UpdatedAt);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Rename_EmptyOrNull_ResetsToDefault(string? name)
    {
        var season = AddSeason();
        season.Name = "Old";

        await _sut.RenameAsync(_userId, season.Id, new RenameSeasonRequest(name));

        Assert.Null(season.Name);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task Rename_ExactlyMaxLength_IsAllowed()
    {
        var season = AddSeason();
        var name = new string('a', Season.NameMaxLength);

        await _sut.RenameAsync(_userId, season.Id, new RenameSeasonRequest($" {name} "));

        Assert.Equal(name, season.Name);
    }

    [Fact]
    public async Task Rename_TooLong_ThrowsValidationWithNameField()
    {
        var season = AddSeason();

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.RenameAsync(_userId, season.Id, new RenameSeasonRequest(new string('a', Season.NameMaxLength + 1))));

        Assert.True(ex.Errors.ContainsKey(NameField));
        Assert.Null(season.Name);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task Rename_OthersSeason_ThrowsNotFound()
    {
        var season = AddSeason(_otherUserId);

        await Assert.ThrowsAsync<NotFoundException>(() =>
            _sut.RenameAsync(_userId, season.Id, new RenameSeasonRequest("Mine?")));

        Assert.Null(season.Name);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task Rename_Missing_ThrowsNotFound()
    {
        await Assert.ThrowsAsync<NotFoundException>(() =>
            _sut.RenameAsync(_userId, Guid.NewGuid(), new RenameSeasonRequest("x")));
    }

    // ---- 완료 ----

    [Fact]
    public async Task SetCompleted_True_StampsNow()
    {
        var season = AddSeason();

        await _sut.SetCompletedAsync(_userId, season.Id, new SetSeasonCompletionRequest(true));

        Assert.Equal(Now, season.CompletedAt);
        Assert.Equal(Now, season.UpdatedAt);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task SetCompleted_TrueAgain_KeepsFirstTimestamp()
    {
        var season = AddSeason();
        season.CompletedAt = Earlier;

        await _sut.SetCompletedAsync(_userId, season.Id, new SetSeasonCompletionRequest(true));

        Assert.Equal(Earlier, season.CompletedAt);
    }

    [Fact]
    public async Task SetCompleted_False_Reopens()
    {
        var season = AddSeason();
        season.CompletedAt = Earlier;

        await _sut.SetCompletedAsync(_userId, season.Id, new SetSeasonCompletionRequest(false));

        Assert.Null(season.CompletedAt);
        Assert.Equal(Now, season.UpdatedAt);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task SetCompleted_MissingValue_ThrowsValidationWithCompletedField()
    {
        var season = AddSeason();

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.SetCompletedAsync(_userId, season.Id, new SetSeasonCompletionRequest(null)));

        Assert.True(ex.Errors.ContainsKey(CompletedField));
        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task SetCompleted_OthersSeason_ThrowsNotFound()
    {
        var season = AddSeason(_otherUserId);

        await Assert.ThrowsAsync<NotFoundException>(() =>
            _sut.SetCompletedAsync(_userId, season.Id, new SetSeasonCompletionRequest(true)));

        Assert.Null(season.CompletedAt);
    }

    // ---- 삭제 ----

    [Fact]
    public async Task Delete_Mine_SoftDeletes()
    {
        var season = AddSeason();

        await _sut.DeleteAsync(_userId, season.Id);

        Assert.True(season.IsDeleted);
        Assert.Equal(Now, season.UpdatedAt);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task Delete_Twice_SecondIsNotFound()
    {
        var season = AddSeason();
        await _sut.DeleteAsync(_userId, season.Id);

        await Assert.ThrowsAsync<NotFoundException>(() => _sut.DeleteAsync(_userId, season.Id));
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task Delete_OthersSeason_ThrowsNotFound()
    {
        var season = AddSeason(_otherUserId);

        await Assert.ThrowsAsync<NotFoundException>(() => _sut.DeleteAsync(_userId, season.Id));

        Assert.False(season.IsDeleted);
        Assert.Equal(0, _uow.SaveCount);
    }

    // ---- Fakes ----

    private sealed class FakeSeasons : ISeasonRepository
    {
        public List<Season> Items { get; } = new();

        public Task<Season?> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
            => Task.FromResult(Items.FirstOrDefault(s => !s.IsDeleted && s.UserId == userId && s.Id == seasonId));

        public Task<Season?> GetByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<Season?> GetDeletedByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<RaceWeekend?> GetWeekendAsync(Guid seasonId, long weekendLinkId, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task AddAsync(Season season, CancellationToken cancellationToken = default) => throw new NotSupportedException();

        public Task AddWeekendAsync(RaceWeekend weekend, CancellationToken cancellationToken = default) => throw new NotSupportedException();
    }

    private sealed class FakeUnitOfWork : IUnitOfWork
    {
        public int SaveCount { get; private set; }

        public Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        {
            SaveCount++;
            return Task.FromResult(1);
        }
    }

    private sealed class FakeClock : IClock
    {
        public FakeClock(DateTime utcNow) => UtcNow = utcNow;

        public DateTime UtcNow { get; }
    }
}
