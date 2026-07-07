using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Sessions;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Sessions;

public class SessionServiceTests
{
    private static readonly DateTime Now = new(2026, 7, 7, 9, 0, 0, DateTimeKind.Utc);

    private readonly FakeSimRigRepository _rigs = new();
    private readonly FakeDrivingSessionRepository _sessions;
    private readonly SessionService _sut;

    private readonly Guid _userA = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private readonly Guid _userB = Guid.Parse("00000000-0000-0000-0000-0000000000b2");
    private readonly SimRig _rig1;
    private readonly SimRig _rig2;

    public SessionServiceTests()
    {
        _sessions = new FakeDrivingSessionRepository(_rigs);
        _rig1 = new SimRig { Id = Guid.NewGuid(), StoreId = Guid.NewGuid(), RigCode = "A-01", DisplayName = "1번 좌석" };
        _rig2 = new SimRig { Id = Guid.NewGuid(), StoreId = _rig1.StoreId, RigCode = "A-02", DisplayName = "2번 좌석" };
        _rigs.Items.AddRange([_rig1, _rig2]);

        _sut = new SessionService(_rigs, _sessions, _sessions, new SequentialIdGenerator(), new FakeClock(Now));
    }

    private CheckInRequest CheckIn(string rig = "A-01") => new(rig, "F1_25");

    // ── Check-in ──

    [Fact]
    public async Task CheckIn_CreatesActiveSession()
    {
        var result = await _sut.CheckInAsync(_userA, CheckIn());

        Assert.Equal("A-01", result.RigCode);
        Assert.Equal("Active", result.Status);
        Assert.Equal(Now, result.StartedAt);

        var stored = Assert.Single(_sessions.Items);
        Assert.Equal(_userA, stored.UserId);
        Assert.Equal(_rig1.Id, stored.SimRigId);
        Assert.Equal(_rig1.StoreId, stored.StoreId);
        Assert.Equal(SessionStatus.Active, stored.Status);
    }

    [Fact]
    public async Task CheckIn_EndsOwnPreviousActiveSessionOnAnotherRig()
    {
        await _sut.CheckInAsync(_userA, CheckIn("A-01"));
        await _sut.CheckInAsync(_userA, CheckIn("A-02"));

        var onRig1 = _sessions.Items.Single(x => x.SimRigId == _rig1.Id);
        var onRig2 = _sessions.Items.Single(x => x.SimRigId == _rig2.Id);
        Assert.Equal(SessionStatus.Ended, onRig1.Status);
        Assert.Equal(Now, onRig1.EndedAt);
        Assert.Equal(SessionStatus.Active, onRig2.Status);
    }

    [Fact]
    public async Task CheckIn_SameRigReCheckIn_EndsOldCreatesNew_NoConflict()
    {
        await _sut.CheckInAsync(_userA, CheckIn("A-01"));
        await _sut.CheckInAsync(_userA, CheckIn("A-01"));

        var onRig1 = _sessions.Items.Where(x => x.SimRigId == _rig1.Id).ToList();
        Assert.Equal(2, onRig1.Count);
        Assert.Single(onRig1, x => x.Status == SessionStatus.Active);
        Assert.Single(onRig1, x => x.Status == SessionStatus.Ended);
    }

    [Fact]
    public async Task CheckIn_RigOccupiedByAnotherUser_ThrowsConflict()
    {
        await _sut.CheckInAsync(_userB, CheckIn("A-01"));

        await Assert.ThrowsAsync<ConflictException>(() => _sut.CheckInAsync(_userA, CheckIn("A-01")));
    }

    [Fact]
    public async Task CheckIn_UnknownRig_ThrowsNotFound()
    {
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.CheckInAsync(_userA, CheckIn("Z-99")));
    }

    [Theory]
    [InlineData("", "F1_25")]
    [InlineData("A-01", "")]
    public async Task CheckIn_BlankFields_ThrowsValidation(string rigCode, string gameCode)
    {
        await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.CheckInAsync(_userA, new CheckInRequest(rigCode, gameCode)));
    }

    // ── Check-out ──

    [Fact]
    public async Task CheckOut_OwnActiveSession_Ends()
    {
        var checkedIn = await _sut.CheckInAsync(_userA, CheckIn());

        var result = await _sut.CheckOutAsync(_userA, checkedIn.SessionId);

        Assert.Equal("Ended", result.Status);
        Assert.Equal(Now, result.EndedAt);
        Assert.Equal(SessionStatus.Ended, _sessions.Items.Single().Status);
    }

    [Fact]
    public async Task CheckOut_AnotherUsersSession_ThrowsForbidden()
    {
        var checkedIn = await _sut.CheckInAsync(_userB, CheckIn());

        await Assert.ThrowsAsync<ForbiddenException>(() => _sut.CheckOutAsync(_userA, checkedIn.SessionId));
    }

    [Fact]
    public async Task CheckOut_UnknownSession_ThrowsNotFound()
    {
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.CheckOutAsync(_userA, Guid.NewGuid()));
    }

    [Fact]
    public async Task CheckOut_AlreadyEnded_IsIdempotent()
    {
        var checkedIn = await _sut.CheckInAsync(_userA, CheckIn());
        await _sut.CheckOutAsync(_userA, checkedIn.SessionId);

        var second = await _sut.CheckOutAsync(_userA, checkedIn.SessionId);

        Assert.Equal("Ended", second.Status);
    }

    // ── Active ──

    [Fact]
    public async Task GetActive_ReturnsActiveWithRigCode()
    {
        await _sut.CheckInAsync(_userA, CheckIn("A-02"));

        var active = await _sut.GetActiveAsync(_userA);

        Assert.NotNull(active);
        Assert.Equal("A-02", active!.RigCode);
    }

    [Fact]
    public async Task GetActive_NoSession_ReturnsNull()
    {
        Assert.Null(await _sut.GetActiveAsync(_userA));
    }

    // ── Fakes ──

    private sealed class FakeSimRigRepository : ISimRigRepository
    {
        public List<SimRig> Items { get; } = new();

        public Task<SimRig?> GetByRigCodeAsync(string rigCode, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.RigCode == rigCode));

        public Task<SimRig?> GetByApiKeyHashAsync(string apiKeyHash, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.ApiKeyHash == apiKeyHash));
    }

    private sealed class FakeDrivingSessionRepository : IDrivingSessionRepository, IUnitOfWork
    {
        private readonly FakeSimRigRepository _rigs;
        public List<DrivingSession> Items { get; } = new();
        public int SaveCount { get; private set; }

        public FakeDrivingSessionRepository(FakeSimRigRepository rigs) => _rigs = rigs;

        public Task<DrivingSession?> GetByIdAsync(Guid id, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.Id == id));

        public Task<DrivingSession?> GetActiveByRigAsync(Guid simRigId, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.SimRigId == simRigId && x.Status == SessionStatus.Active));

        public Task<DrivingSession?> GetActiveByUserAsync(Guid userId, CancellationToken ct = default)
        {
            var session = Items
                .Where(x => x.UserId == userId && x.Status == SessionStatus.Active)
                .OrderByDescending(x => x.StartedAt)
                .FirstOrDefault();
            if (session is not null)
            {
                session.SimRig = _rigs.Items.FirstOrDefault(r => r.Id == session.SimRigId);
            }

            return Task.FromResult(session);
        }

        public Task<IReadOnlyList<DrivingSession>> GetActiveSessionsByUserAsync(Guid userId, CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<DrivingSession>>(
                Items.Where(x => x.UserId == userId && x.Status == SessionStatus.Active).ToList());

        public Task AddAsync(DrivingSession session, CancellationToken ct = default)
        {
            Items.Add(session);
            return Task.CompletedTask;
        }

        public Task<int> SaveChangesAsync(CancellationToken ct = default)
        {
            SaveCount++;
            return Task.FromResult(Items.Count);
        }
    }

    private sealed class SequentialIdGenerator : IIdGenerator
    {
        private int _counter;

        public Guid NewId()
        {
            _counter++;
            return new Guid(_counter, 0, 0, new byte[8]);
        }
    }

    private sealed class FakeClock : IClock
    {
        public FakeClock(DateTime utcNow) => UtcNow = utcNow;

        public DateTime UtcNow { get; }
    }
}
