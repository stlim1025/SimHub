using SimCenter.Application.AgentDevices;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
using Xunit.Sdk;

namespace SimCenter.Application.Tests.AgentDevices;

public class AgentPairingServiceTests
{
    private const string RawCode = "ABCDEFGH";
    private const string DisplayCode = "ABCD-EFGH";
    private const string InvalidCodeMessage = "유효하지 않거나 만료된 코드입니다.";
    private const string DefaultDeviceName = "Windows PC";

    private static readonly DateTime Now = new(2026, 10, 17, 9, 0, 0, DateTimeKind.Utc);

    private readonly Guid _ownerId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private readonly Guid _otherUserId = Guid.Parse("00000000-0000-0000-0000-0000000000a2");

    private readonly FakeRandom _random = new();
    private readonly FakeCodes _codes = new();
    private readonly FakeDevices _devices = new();
    private readonly FakeUnitOfWork _uow = new();
    private readonly FakeTransactionRunner _transactions = new();

    private readonly AgentPairingService _sut;

    public AgentPairingServiceTests()
    {
        _sut = new AgentPairingService(
            _codes, _devices, _uow, _transactions,
            new FakeHasher(), _random, new SequentialIdGenerator(), new FakeClock(Now));
    }

    private AgentPairingCode StoredCode(
        string rawCode = RawCode,
        Guid? userId = null,
        DateTime? expiresAt = null,
        DateTime? consumedAt = null,
        bool isDeleted = false) => new()
    {
        Id = Guid.NewGuid(),
        UserId = userId ?? _ownerId,
        CodeHash = "h:" + rawCode,
        ExpiresAt = expiresAt ?? Now.AddMinutes(5),
        ConsumedAt = consumedAt,
        IsDeleted = isDeleted,
        CreatedAt = Now.AddMinutes(-5),
    };

    private static async Task AssertInvalidCodeAsync(Func<Task> act)
    {
        var ex = await Assert.ThrowsAsync<ValidationException>(act);
        Assert.Equal(InvalidCodeMessage, ex.Errors["code"][0]);
    }

    // ── 코드 발급 ──

    [Fact]
    public async Task IssueCode_ReturnsDisplayFormattedCode_AndStoresOnlyHash()
    {
        _random.EnqueueCode(RawCode);

        var result = await _sut.IssueCodeAsync(_ownerId);

        Assert.Equal(DisplayCode, result.Code);
        Assert.Equal(Now.AddMinutes(10), result.ExpiresAt);

        var stored = Assert.Single(_codes.Items);
        Assert.Equal("h:" + RawCode, stored.CodeHash);
        Assert.Equal(_ownerId, stored.UserId);
        Assert.Equal(Now.AddMinutes(10), stored.ExpiresAt);
        Assert.Equal(Now, stored.CreatedAt);
        Assert.Null(stored.ConsumedAt);
        Assert.False(stored.IsDeleted);
        Assert.NotEqual(Guid.Empty, stored.Id);
        Assert.Equal(1, _uow.SaveCount);

        // 원문(정규화/표시 형식)이 그대로 저장된 문자열 필드는 없어야 한다.
        var storedStrings = typeof(AgentPairingCode).GetProperties()
            .Where(p => p.PropertyType == typeof(string))
            .Select(p => (string?)p.GetValue(stored))
            .ToList();
        Assert.DoesNotContain(RawCode, storedStrings);
        Assert.DoesNotContain(DisplayCode, storedStrings);
    }

    [Fact]
    public async Task IssueCode_InvalidatesPreviousUnconsumedCodes()
    {
        var previousA = StoredCode("PREVIOUA");
        var previousB = StoredCode("PREVIOUB");
        var consumed = StoredCode("CONSUMED", consumedAt: Now.AddMinutes(-1));
        var otherUsers = StoredCode("OTHERUSR", userId: _otherUserId);
        _codes.Items.AddRange(new[] { previousA, previousB, consumed, otherUsers });
        _random.EnqueueCode(RawCode);

        await _sut.IssueCodeAsync(_ownerId);

        Assert.True(previousA.IsDeleted);
        Assert.True(previousB.IsDeleted);
        Assert.Equal(Now, previousA.UpdatedAt);
        Assert.Equal(Now, previousB.UpdatedAt);
        Assert.False(consumed.IsDeleted); // 이미 사용된 코드는 건드리지 않는다.
        Assert.False(otherUsers.IsDeleted); // 타인 코드는 건드리지 않는다.

        var issued = _codes.Items.Single(x => x.CodeHash == "h:" + RawCode);
        Assert.False(issued.IsDeleted);
        Assert.Equal(1, _uow.SaveCount); // 무효화 + 신규 저장이 한 번의 커밋.
    }

    [Fact]
    public async Task IssueCode_RetriesOnHashCollision_ThenSucceeds()
    {
        _random.EnqueueCode("AAAAAAAA");
        _random.EnqueueCode("BBBBBBBB");
        _random.EnqueueCode("CCCCCCCC");
        _codes.ExistsTrueForFirst = 2;

        var result = await _sut.IssueCodeAsync(_ownerId);

        Assert.Equal("CCCC-CCCC", result.Code);
        var stored = Assert.Single(_codes.Items);
        Assert.Equal("h:CCCCCCCC", stored.CodeHash);
        Assert.Equal(3, _codes.ExistsCalls);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task IssueCode_CollidesThreeTimes_Throws()
    {
        _random.EnqueueCode("AAAAAAAA");
        _random.EnqueueCode("BBBBBBBB");
        _random.EnqueueCode("CCCCCCCC");
        _codes.ExistsTrueForFirst = int.MaxValue;

        await Assert.ThrowsAsync<InvalidOperationException>(() => _sut.IssueCodeAsync(_ownerId));

        Assert.Equal(3, _codes.ExistsCalls);
        Assert.Empty(_codes.Items);
        Assert.Equal(0, _uow.SaveCount);
    }

    // ── 장치 연결 ──

    [Fact]
    public async Task Pair_ValidCode_CreatesDeviceForCodeOwner_AndReturnsKey()
    {
        var code = StoredCode();
        _codes.Items.Add(code);
        _random.EnqueueKey();

        var response = await _sut.PairAsync(new PairRequest(DisplayCode, "Gaming Rig"));

        var device = Assert.Single(_devices.Items);
        Assert.Equal(_ownerId, device.UserId);
        Assert.Equal("h:" + response.DeviceKey, device.ApiKeyHash);
        Assert.Equal(43, response.DeviceKey.Length);
        Assert.Equal(response.DeviceId, device.Id);
        Assert.NotEqual(Guid.Empty, device.Id);
        Assert.Equal("Gaming Rig", device.Name);
        Assert.Equal(Now, device.CreatedAt);
        Assert.Null(device.LastSeenAt);
        Assert.Equal(1, _codes.TryConsumeCalls);
        Assert.Equal(Now, code.ConsumedAt);
        Assert.Equal(1, _transactions.RunCount);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task Pair_NormalizesLowercaseHyphenAndSpaces()
    {
        _codes.Items.Add(StoredCode());
        _random.EnqueueKey();

        var response = await _sut.PairAsync(new PairRequest(" abcd-efgh ", null));

        Assert.Single(_devices.Items);
        Assert.Equal(43, response.DeviceKey.Length);
    }

    [Theory]
    [InlineData("unknown")]
    [InlineData("expired")]
    [InlineData("consumed")]
    [InlineData("invalidated")]
    public async Task Pair_UnredeemableCode_ThrowsSameValidationError(string scenario)
    {
        switch (scenario)
        {
            case "expired":
                _codes.Items.Add(StoredCode(expiresAt: Now.AddSeconds(-1)));
                break;
            case "consumed":
                _codes.Items.Add(StoredCode(consumedAt: Now.AddMinutes(-1)));
                break;
            case "invalidated":
                _codes.Items.Add(StoredCode(isDeleted: true));
                break;
        }

        await AssertInvalidCodeAsync(() => _sut.PairAsync(new PairRequest(DisplayCode, "PC")));

        Assert.Empty(_devices.Items);
        Assert.Equal(0, _codes.TryConsumeCalls);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task Pair_AtExactExpiry_IsRejected()
    {
        _codes.Items.Add(StoredCode(expiresAt: Now));

        await AssertInvalidCodeAsync(() => _sut.PairAsync(new PairRequest(DisplayCode, "PC")));

        Assert.Empty(_devices.Items);
    }

    [Fact]
    public async Task Pair_LostConcurrentConsume_ThrowsSameValidationError()
    {
        _codes.Items.Add(StoredCode());
        _codes.TryConsumeSucceeds = false;

        await AssertInvalidCodeAsync(() => _sut.PairAsync(new PairRequest(DisplayCode, "PC")));

        Assert.Equal(1, _codes.TryConsumeCalls);
        Assert.Empty(_devices.Items);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("ABC")]
    [InlineData("ABCDEFGHJ")]
    public async Task Pair_CodeNotEightChars_ThrowsSameErrorWithoutLookup(string? code)
    {
        await AssertInvalidCodeAsync(() => _sut.PairAsync(new PairRequest(code, "PC")));

        Assert.Equal(0, _codes.GetRedeemableCalls);
        Assert.Empty(_devices.Items);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("   ")]
    public async Task Pair_BlankDeviceName_UsesDefault(string? name)
    {
        _codes.Items.Add(StoredCode());
        _random.EnqueueKey();

        await _sut.PairAsync(new PairRequest(DisplayCode, name));

        Assert.Equal(DefaultDeviceName, Assert.Single(_devices.Items).Name);
    }

    [Fact]
    public async Task Pair_DeviceName_IsTrimmed_AndExactly50CharsAccepted()
    {
        _codes.Items.Add(StoredCode());
        _random.EnqueueKey();
        var name = new string('가', 50);

        await _sut.PairAsync(new PairRequest(DisplayCode, $"  {name}  "));

        Assert.Equal(name, Assert.Single(_devices.Items).Name);
    }

    [Fact]
    public async Task Pair_DeviceNameOver50_ThrowsValidation()
    {
        _codes.Items.Add(StoredCode());

        var ex = await Assert.ThrowsAsync<ValidationException>(
            () => _sut.PairAsync(new PairRequest(DisplayCode, new string('가', 51))));

        Assert.True(ex.Errors.ContainsKey("deviceName"));
        Assert.Empty(_devices.Items);
        Assert.Null(_codes.Items.Single().ConsumedAt); // 이름 검증 실패로 코드를 소비하지 않는다.
    }

    // ── Fakes ──

    /// <summary>준비된 바이트열을 순서대로 돌려준다. 준비된 것보다 많이 요청하면 테스트를 실패시킨다.</summary>
    private sealed class FakeRandom : IRandomSource
    {
        private readonly Queue<byte[]> _queue = new();

        public void EnqueueCode(string code)
            => _queue.Enqueue(code.Select(c => (byte)PairingCodeFormat.Alphabet.IndexOf(c)).ToArray());

        public void EnqueueKey(byte fill = 7)
            => _queue.Enqueue(Enumerable.Repeat(fill, DeviceKeyFormat.KeyBytes).ToArray());

        public byte[] GetBytes(int count)
        {
            if (!_queue.TryDequeue(out var bytes))
            {
                throw new XunitException("준비된 것보다 많은 난수를 요청했습니다.");
            }

            if (bytes.Length != count)
            {
                throw new XunitException($"난수 {count}바이트를 요청했지만 준비된 값은 {bytes.Length}바이트입니다.");
            }

            return bytes;
        }
    }

    private sealed class FakeHasher : IApiKeyHasher
    {
        public string Hash(string rawKey) => "h:" + rawKey;
    }

    private sealed class FakeCodes : IAgentPairingCodeRepository
    {
        public List<AgentPairingCode> Items { get; } = new();
        public int ExistsTrueForFirst { get; set; }
        public int ExistsCalls { get; private set; }
        public int GetRedeemableCalls { get; private set; }
        public int TryConsumeCalls { get; private set; }
        public bool TryConsumeSucceeds { get; set; } = true;

        public Task AddAsync(AgentPairingCode code, CancellationToken ct = default)
        {
            Items.Add(code);
            return Task.CompletedTask;
        }

        // 전역 soft-delete 필터를 모사: 삭제된 코드는 보이지 않는다.
        public Task<IReadOnlyList<AgentPairingCode>> GetUnconsumedByUserAsync(Guid userId, CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<AgentPairingCode>>(
                Items.Where(x => x.UserId == userId && x.ConsumedAt is null && !x.IsDeleted).ToList());

        // 고유 인덱스는 soft-delete 행도 포함하므로 삭제 여부를 무시한다.
        public Task<bool> ExistsByHashAsync(string codeHash, CancellationToken ct = default)
        {
            ExistsCalls++;
            if (ExistsCalls <= ExistsTrueForFirst)
            {
                return Task.FromResult(true);
            }

            return Task.FromResult(Items.Any(x => x.CodeHash == codeHash));
        }

        public Task<AgentPairingCode?> GetRedeemableByHashAsync(string codeHash, DateTime nowUtc, CancellationToken ct = default)
        {
            GetRedeemableCalls++;
            return Task.FromResult(Items.FirstOrDefault(x =>
                x.CodeHash == codeHash && !x.IsDeleted && x.ConsumedAt is null && x.ExpiresAt > nowUtc));
        }

        // TryConsumeSucceeds=false: 다른 요청이 먼저 소비해 조건부 UPDATE가 0행인 경우를 모사.
        public Task<bool> TryConsumeAsync(Guid codeId, DateTime nowUtc, CancellationToken ct = default)
        {
            TryConsumeCalls++;
            if (!TryConsumeSucceeds)
            {
                return Task.FromResult(false);
            }

            var code = Items.FirstOrDefault(x => x.Id == codeId && !x.IsDeleted && x.ConsumedAt is null);
            if (code is null)
            {
                return Task.FromResult(false);
            }

            code.ConsumedAt = nowUtc;
            return Task.FromResult(true);
        }
    }

    private sealed class FakeDevices : IAgentDeviceRepository
    {
        public List<AgentDevice> Items { get; } = new();

        public Task AddAsync(AgentDevice device, CancellationToken ct = default)
        {
            Items.Add(device);
            return Task.CompletedTask;
        }

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

    private sealed class FakeTransactionRunner : ITransactionRunner
    {
        public int RunCount { get; private set; }

        public Task<T> RunAsync<T>(Func<CancellationToken, Task<T>> work, CancellationToken cancellationToken = default)
        {
            RunCount++;
            return work(cancellationToken);
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
