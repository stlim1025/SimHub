using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Profile;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Profile;

public class ProfileServiceTests
{
    private const string Email = "driver@simcenter.test";
    private const string Password = "P@ssw0rd!";

    private static readonly DateTime Now = new(2026, 10, 18, 3, 0, 0, DateTimeKind.Utc);
    private static readonly Guid UserId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");

    private readonly FakeUserRepository _users = new();
    private readonly ProfileService _sut;

    public ProfileServiceTests()
    {
        _users.Items.Add(new User
        {
            Id = UserId,
            Email = Email,
            PasswordHash = FakePasswordHasher.HashOf(Password),
            DisplayName = "홍길동",
            CreatedAt = Now.AddDays(-1),
        });
        _sut = new ProfileService(_users, _users, new FakePasswordHasher(), new FakeClock(Now), NullLogger<ProfileService>.Instance);
    }

    private User Stored => _users.Items.Single(u => u.Id == UserId);

    private static UpdateProfileRequest ValidRequest() => new(
        DisplayName: "lemonary",
        ShowOnLeaderboard: false,
        AvatarTeam: "MCL",
        PreferredGame: "F1_25",
        Controller: "Gamepad",
        Console: "PlayStation",
        Units: "Imperial",
        TimeZoneId: "Europe/London",
        Theme: "Light");

    // ── UpdateProfile ──

    [Fact]
    public async Task UpdateProfile_SavesAllFields_AndReturnsProfile()
    {
        var dto = await _sut.UpdateProfileAsync(UserId, ValidRequest());

        var user = Stored;
        Assert.Equal("lemonary", user.DisplayName);
        Assert.False(user.ShowOnLeaderboard);
        Assert.Equal("MCL", user.AvatarTeam);
        Assert.Equal("F1_25", user.PreferredGame);
        Assert.Equal(ControllerType.Gamepad, user.Controller);
        Assert.Equal(ConsolePlatform.PlayStation, user.Console);
        Assert.Equal(UnitSystem.Imperial, user.Units);
        Assert.Equal("Europe/London", user.TimeZoneId);
        Assert.Equal(ThemePreference.Light, user.Theme);
        Assert.Equal(Now, user.UpdatedAt);
        Assert.Equal(1, _users.SaveCount);

        Assert.Equal(UserId, dto.UserId);
        Assert.Equal(Email, dto.Email);
        Assert.Equal("Gamepad", dto.Controller);
        Assert.Equal("PlayStation", dto.Console);
        Assert.Equal("Imperial", dto.Units);
        Assert.Equal("Light", dto.Theme);
    }

    [Fact]
    public async Task UpdateProfile_NormalizesInput_TrimAndCase()
    {
        var request = ValidRequest() with
        {
            DisplayName = "  lemonary  ",
            AvatarTeam = " mcl ",
            PreferredGame = "f1_25",
            Controller = "wheel",
            Console = "XBOX",
            Units = " metric ",
            TimeZoneId = " Asia/Tokyo ",
            Theme = "system",
        };

        await _sut.UpdateProfileAsync(UserId, request);

        var user = Stored;
        Assert.Equal("lemonary", user.DisplayName);
        Assert.Equal("MCL", user.AvatarTeam);
        Assert.Equal("F1_25", user.PreferredGame);
        Assert.Equal(ControllerType.Wheel, user.Controller);
        Assert.Equal(ConsolePlatform.Xbox, user.Console);
        Assert.Equal(UnitSystem.Metric, user.Units);
        Assert.Equal("Asia/Tokyo", user.TimeZoneId);
        Assert.Equal(ThemePreference.System, user.Theme);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task UpdateProfile_BlankAvatar_ClearsPicture(string? avatarTeam)
    {
        Stored.AvatarTeam = "FER";

        await _sut.UpdateProfileAsync(UserId, ValidRequest() with { AvatarTeam = avatarTeam });

        Assert.Null(Stored.AvatarTeam);
    }

    [Theory]
    [InlineData("MER")]
    [InlineData("FER")]
    [InlineData("RBR")]
    [InlineData("MCL")]
    [InlineData("AST")]
    [InlineData("ALP")]
    [InlineData("WIL")]
    [InlineData("RB")]
    [InlineData("SAU")]
    [InlineData("HAA")]
    public async Task UpdateProfile_AcceptsEveryAvatarTeamCode(string code)
    {
        await _sut.UpdateProfileAsync(UserId, ValidRequest() with { AvatarTeam = code });

        Assert.Equal(code, Stored.AvatarTeam);
    }

    [Theory]
    [InlineData("displayName", "")]
    [InlineData("displayName", "   ")]
    [InlineData("avatarTeam", "XYZ")]
    [InlineData("preferredGame", "F1_24")]
    [InlineData("preferredGame", "")]
    [InlineData("controller", "Joystick")]
    [InlineData("controller", "1")]
    [InlineData("console", "Switch")]
    [InlineData("units", "Nautical")]
    [InlineData("theme", "Sepia")]
    [InlineData("timeZoneId", "Mars/Olympus")]
    [InlineData("timeZoneId", "")]
    public async Task UpdateProfile_InvalidField_ThrowsValidationForThatField(string field, string value)
    {
        var request = field switch
        {
            "displayName" => ValidRequest() with { DisplayName = value },
            "avatarTeam" => ValidRequest() with { AvatarTeam = value },
            "preferredGame" => ValidRequest() with { PreferredGame = value },
            "controller" => ValidRequest() with { Controller = value },
            "console" => ValidRequest() with { Console = value },
            "units" => ValidRequest() with { Units = value },
            "theme" => ValidRequest() with { Theme = value },
            _ => ValidRequest() with { TimeZoneId = value },
        };

        var error = await Assert.ThrowsAsync<ValidationException>(() => _sut.UpdateProfileAsync(UserId, request));

        Assert.Equal(new[] { field }, error.Errors.Keys);
        Assert.Equal(0, _users.SaveCount);
        Assert.Equal("홍길동", Stored.DisplayName); // 아무것도 바뀌지 않는다.
    }

    [Fact]
    public async Task UpdateProfile_DisplayNameOver50_ThrowsValidation()
    {
        var request = ValidRequest() with { DisplayName = new string('가', 51) };

        var error = await Assert.ThrowsAsync<ValidationException>(() => _sut.UpdateProfileAsync(UserId, request));

        Assert.Contains("displayName", error.Errors.Keys);
    }

    [Fact]
    public async Task UpdateProfile_WindowsTimeZoneId_IsRejected()
    {
        var request = ValidRequest() with { TimeZoneId = "Korea Standard Time" };

        var error = await Assert.ThrowsAsync<ValidationException>(() => _sut.UpdateProfileAsync(UserId, request));

        Assert.Contains("timeZoneId", error.Errors.Keys);
    }

    [Theory]
    [InlineData("Asia/Seoul")]
    [InlineData("UTC")]
    [InlineData("Europe/London")]
    [InlineData("Europe/Berlin")]
    [InlineData("America/New_York")]
    [InlineData("America/Los_Angeles")]
    [InlineData("Asia/Tokyo")]
    [InlineData("Australia/Sydney")]
    public async Task UpdateProfile_AcceptsCuratedIanaTimeZones(string timeZoneId)
    {
        await _sut.UpdateProfileAsync(UserId, ValidRequest() with { TimeZoneId = timeZoneId });

        Assert.Equal(timeZoneId, Stored.TimeZoneId);
    }

    [Theory]
    [InlineData(" asia/seoul ", "Asia/Seoul")]
    [InlineData("ASIA/TOKYO", "Asia/Tokyo")]
    [InlineData("america/new_york", "America/New_York")]
    [InlineData("america/los_angeles", "America/Los_Angeles")]
    [InlineData("europe/london", "Europe/London")]
    [InlineData("utc", "UTC")]
    public async Task UpdateProfile_StoresCanonicalTimeZoneId(string input, string expected)
    {
        await _sut.UpdateProfileAsync(UserId, ValidRequest() with { TimeZoneId = input });

        Assert.Equal(expected, Stored.TimeZoneId);
    }

    [Fact]
    public async Task UpdateProfile_MissingFields_ReportsEveryField()
    {
        var request = new UpdateProfileRequest(null, null, null, null, null, null, null, null, null);

        var error = await Assert.ThrowsAsync<ValidationException>(() => _sut.UpdateProfileAsync(UserId, request));

        // 사진(avatarTeam)만 선택 항목이다.
        Assert.Equal(
            new[] { "console", "controller", "displayName", "preferredGame", "showOnLeaderboard", "theme", "timeZoneId", "units" },
            error.Errors.Keys.Order().ToArray());
    }

    [Fact]
    public async Task UpdateProfile_UnknownUser_ThrowsNotFound()
    {
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.UpdateProfileAsync(Guid.NewGuid(), ValidRequest()));
    }

    // ── ChangeEmail ──

    [Fact]
    public async Task ChangeEmail_WithCorrectPassword_NormalizesAndSaves()
    {
        var dto = await _sut.ChangeEmailAsync(UserId, new ChangeEmailRequest("  New@SimCenter.Test ", Password));

        Assert.Equal("new@simcenter.test", Stored.Email);
        Assert.Equal("new@simcenter.test", dto.Email);
        Assert.Equal(Now, Stored.UpdatedAt);
        Assert.Equal(1, _users.SaveCount);
    }

    [Fact]
    public async Task ChangeEmail_WrongPassword_ThrowsValidationOnCurrentPassword()
    {
        var error = await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.ChangeEmailAsync(UserId, new ChangeEmailRequest("new@simcenter.test", "WrongP@ss1")));

        Assert.Equal(new[] { "currentPassword" }, error.Errors.Keys);
        Assert.Equal(Email, Stored.Email);
        Assert.Equal(0, _users.SaveCount);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public async Task ChangeEmail_MissingPassword_ThrowsValidationOnCurrentPassword(string? password)
    {
        var error = await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.ChangeEmailAsync(UserId, new ChangeEmailRequest("new@simcenter.test", password)));

        Assert.Equal(new[] { "currentPassword" }, error.Errors.Keys);
    }

    [Theory]
    [InlineData("not-an-email")]
    [InlineData("")]
    [InlineData(null)]
    public async Task ChangeEmail_InvalidEmail_ThrowsValidationOnNewEmail(string? newEmail)
    {
        var error = await Assert.ThrowsAsync<ValidationException>(() =>
            _sut.ChangeEmailAsync(UserId, new ChangeEmailRequest(newEmail, Password)));

        Assert.Equal(new[] { "newEmail" }, error.Errors.Keys);
    }

    [Fact]
    public async Task ChangeEmail_TakenByAnotherUser_ThrowsConflict()
    {
        _users.Items.Add(new User { Id = Guid.NewGuid(), Email = "taken@simcenter.test", PasswordHash = "x", DisplayName = "다른 사람" });

        await Assert.ThrowsAsync<ConflictException>(() =>
            _sut.ChangeEmailAsync(UserId, new ChangeEmailRequest("TAKEN@simcenter.test", Password)));

        Assert.Equal(Email, Stored.Email);
        Assert.Equal(0, _users.SaveCount);
    }

    [Fact]
    public async Task ChangeEmail_SameEmail_ReturnsProfileWithoutSaving()
    {
        var dto = await _sut.ChangeEmailAsync(UserId, new ChangeEmailRequest(Email.ToUpperInvariant(), Password));

        Assert.Equal(Email, dto.Email);
        Assert.Equal(0, _users.SaveCount);
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
        public static string HashOf(string password) => $"hashed:{password}";

        public string Hash(string password) => HashOf(password);

        public bool Verify(string password, string passwordHash) => passwordHash == HashOf(password);
    }

    private sealed class FakeClock : IClock
    {
        public FakeClock(DateTime utcNow) => UtcNow = utcNow;

        public DateTime UtcNow { get; }
    }
}
