using SimCenter.Application.Auth;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Tests.Auth;

public class AuthServiceTests
{
    private const string ValidEmail = "driver@simcenter.test";
    private const string ValidPassword = "P@ssw0rd!";
    private const string ValidDisplayName = "홍길동";

    private readonly FakeUserRepository _users = new();
    private readonly FakeClock _clock = new(new DateTime(2026, 7, 7, 0, 0, 0, DateTimeKind.Utc));
    private readonly AuthService _sut;

    public AuthServiceTests()
    {
        _sut = new AuthService(
            _users,
            _users, // IUnitOfWork도 겸함(테스트 편의)
            new FakePasswordHasher(),
            new FakeJwtTokenGenerator(),
            new SequentialIdGenerator(),
            _clock);
    }

    // ── Register ──

    [Fact]
    public async Task Register_Succeeds_PersistsHashedUser()
    {
        var response = await _sut.RegisterAsync(new RegisterRequest(ValidEmail, ValidPassword, ValidDisplayName));

        Assert.Equal(ValidDisplayName, response.DisplayName);
        var stored = Assert.Single(_users.Items);
        Assert.Equal(ValidEmail, stored.Email);
        Assert.Equal($"hashed:{ValidPassword}", stored.PasswordHash);
        Assert.NotEqual(ValidPassword, stored.PasswordHash);
        Assert.Equal(_clock.UtcNow, stored.CreatedAt);
        Assert.Equal(1, _users.SaveCount);
    }

    [Fact]
    public async Task Register_NormalizesEmail_LowercasesAndTrims()
    {
        await _sut.RegisterAsync(new RegisterRequest("  DRIVER@SimCenter.Test  ", ValidPassword, ValidDisplayName));

        Assert.Equal(ValidEmail, _users.Items.Single().Email);
    }

    [Fact]
    public async Task Register_DuplicateEmail_ThrowsConflict()
    {
        await _sut.RegisterAsync(new RegisterRequest(ValidEmail, ValidPassword, ValidDisplayName));

        await Assert.ThrowsAsync<ConflictException>(() =>
            _sut.RegisterAsync(new RegisterRequest(ValidEmail, ValidPassword, "다른이름")));
    }

    [Theory]
    [InlineData("not-an-email")]
    [InlineData("")]
    public async Task Register_InvalidEmail_ThrowsValidation(string email)
    {
        await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.RegisterAsync(new RegisterRequest(email, ValidPassword, ValidDisplayName)));
    }

    [Fact]
    public async Task Register_ShortPassword_ThrowsValidation()
    {
        await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.RegisterAsync(new RegisterRequest(ValidEmail, "short", ValidDisplayName)));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Register_BlankDisplayName_ThrowsValidation(string displayName)
    {
        await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.RegisterAsync(new RegisterRequest(ValidEmail, ValidPassword, displayName)));
    }

    // ── Login ──

    [Fact]
    public async Task Login_Succeeds_ReturnsToken()
    {
        await _sut.RegisterAsync(new RegisterRequest(ValidEmail, ValidPassword, ValidDisplayName));

        var response = await _sut.LoginAsync(new LoginRequest(ValidEmail, ValidPassword));

        Assert.False(string.IsNullOrEmpty(response.AccessToken));
        Assert.Equal(ValidDisplayName, response.User.DisplayName);
        Assert.Equal(_clock.UtcNow.AddHours(1), response.ExpiresAt);
    }

    [Fact]
    public async Task Login_WrongPassword_ThrowsAuthentication()
    {
        await _sut.RegisterAsync(new RegisterRequest(ValidEmail, ValidPassword, ValidDisplayName));

        await Assert.ThrowsAsync<AuthenticationException>(() =>
            _sut.LoginAsync(new LoginRequest(ValidEmail, "WrongP@ss1")));
    }

    [Fact]
    public async Task Login_UnknownEmail_ThrowsAuthentication()
    {
        await Assert.ThrowsAsync<AuthenticationException>(() =>
            _sut.LoginAsync(new LoginRequest("nobody@simcenter.test", ValidPassword)));
    }

    // ── GetMe ──

    [Fact]
    public async Task GetMe_ReturnsProfile()
    {
        var registered = await _sut.RegisterAsync(new RegisterRequest(ValidEmail, ValidPassword, ValidDisplayName));

        var me = await _sut.GetMeAsync(registered.UserId);

        Assert.Equal(ValidEmail, me.Email);
        Assert.Equal(ValidDisplayName, me.DisplayName);
    }

    [Fact]
    public async Task GetMe_Unknown_ThrowsNotFound()
    {
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMeAsync(Guid.NewGuid()));
    }

    // ── Fakes ──

    private sealed class FakeUserRepository : IUserRepository, IUnitOfWork
    {
        public List<User> Items { get; } = new();
        public int SaveCount { get; private set; }

        public Task<User?> GetByIdAsync(Guid id, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.Id == id));

        public Task<User?> GetByEmailAsync(string email, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.Email == email));

        public Task<bool> ExistsByEmailAsync(string email, CancellationToken ct = default)
            => Task.FromResult(Items.Any(x => x.Email == email));

        public Task AddAsync(User user, CancellationToken ct = default)
        {
            Items.Add(user);
            return Task.CompletedTask;
        }

        public Task<int> SaveChangesAsync(CancellationToken ct = default)
        {
            SaveCount++;
            return Task.FromResult(1);
        }
    }

    private sealed class FakePasswordHasher : IPasswordHasher
    {
        public string Hash(string password) => $"hashed:{password}";

        public bool Verify(string password, string passwordHash) => passwordHash == $"hashed:{password}";
    }

    private sealed class FakeJwtTokenGenerator : IJwtTokenGenerator
    {
        public (string Token, DateTime ExpiresAt) Generate(User user)
            => ($"token-for-{user.Id}", new DateTime(2026, 7, 7, 1, 0, 0, DateTimeKind.Utc));
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
