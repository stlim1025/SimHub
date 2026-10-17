using SimCenter.Application.AgentDevices;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Tests.AgentDevices;

public class AgentDeviceServiceTests
{
    private static readonly DateTime Now = new(2026, 10, 17, 9, 0, 0, DateTimeKind.Utc);

    private readonly Guid _userId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private readonly Guid _otherUserId = Guid.Parse("00000000-0000-0000-0000-0000000000a2");

    private readonly FakeDevices _devices = new();
    private readonly FakeUnitOfWork _uow = new();

    private readonly AgentDeviceService _sut;

    public AgentDeviceServiceTests()
    {
        _sut = new AgentDeviceService(_devices, _uow, new FakeClock(Now));
    }

    private AgentDevice Device(Guid? userId = null, string name = "PC", DateTime? createdAt = null, DateTime? lastSeenAt = null)
        => new()
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? _userId,
            Name = name,
            ApiKeyHash = "h:" + Guid.NewGuid(),
            CreatedAt = createdAt ?? Now.AddDays(-1),
            LastSeenAt = lastSeenAt,
        };

    [Fact]
    public async Task GetMyDevices_ReturnsOnlyMine_NewestFirst()
    {
        var older = Device(name: "Old PC", createdAt: Now.AddDays(-3));
        var newer = Device(name: "New PC", createdAt: Now.AddDays(-1), lastSeenAt: Now.AddMinutes(-2));
        var others = Device(userId: _otherUserId, name: "Other PC", createdAt: Now.AddDays(-2));
        _devices.Items.AddRange(new[] { older, others, newer });

        var response = await _sut.GetMyDevicesAsync(_userId);

        Assert.Equal(2, response.Items.Count);
        Assert.Equal(new[] { newer.Id, older.Id }, response.Items.Select(x => x.DeviceId));

        var first = response.Items[0];
        Assert.Equal("New PC", first.Name);
        Assert.Equal(Now.AddMinutes(-2), first.LastSeenAt);
        Assert.Equal(newer.CreatedAt, first.CreatedAt);
        Assert.Null(response.Items[1].LastSeenAt);
    }

    [Fact]
    public async Task GetMyDevices_NoDevices_ReturnsEmptyList()
    {
        var response = await _sut.GetMyDevicesAsync(_userId);

        Assert.Empty(response.Items);
    }

    [Fact]
    public async Task Revoke_Mine_SoftDeletes()
    {
        var device = Device();
        _devices.Items.Add(device);

        await _sut.RevokeAsync(_userId, device.Id);

        Assert.True(device.IsDeleted);
        Assert.Equal(Now, device.UpdatedAt);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task Revoke_OthersDevice_ThrowsForbidden()
    {
        var device = Device(userId: _otherUserId);
        _devices.Items.Add(device);

        await Assert.ThrowsAsync<ForbiddenException>(() => _sut.RevokeAsync(_userId, device.Id));

        Assert.False(device.IsDeleted);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task Revoke_Missing_ThrowsNotFound()
    {
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.RevokeAsync(_userId, Guid.NewGuid()));

        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task Revoke_AlreadyRevoked_ThrowsNotFound()
    {
        var device = Device();
        device.IsDeleted = true; // 전역 soft-delete 필터로 조회되지 않는다.
        _devices.Items.Add(device);

        await Assert.ThrowsAsync<NotFoundException>(() => _sut.RevokeAsync(_userId, device.Id));

        Assert.Equal(0, _uow.SaveCount);
    }

    // ── Fakes ──

    private sealed class FakeDevices : IAgentDeviceRepository
    {
        public List<AgentDevice> Items { get; } = new();

        public Task AddAsync(AgentDevice device, CancellationToken ct = default)
        {
            Items.Add(device);
            return Task.CompletedTask;
        }

        // 전역 soft-delete 필터를 모사: 해제된 장치는 조회되지 않는다.
        public Task<AgentDevice?> GetByIdAsync(Guid id, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.Id == id && !x.IsDeleted));

        public Task<AgentDevice?> GetByApiKeyHashAsync(string hash, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.ApiKeyHash == hash && !x.IsDeleted));

        public Task<IReadOnlyList<AgentDevice>> GetByUserAsync(Guid userId, CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<AgentDevice>>(
                Items.Where(x => x.UserId == userId && !x.IsDeleted).OrderByDescending(x => x.CreatedAt).ToList());
    }

    private sealed class FakeUnitOfWork : IUnitOfWork
    {
        public int SaveCount { get; private set; }

        public Task<int> SaveChangesAsync(CancellationToken ct = default)
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
