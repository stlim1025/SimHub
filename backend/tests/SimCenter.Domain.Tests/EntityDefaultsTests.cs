using SimCenter.Domain.Entities;

namespace SimCenter.Domain.Tests;

public class EntityDefaultsTests
{
    [Fact]
    public void User_Defaults_AreSaneForNewEntity()
    {
        var user = new User { Email = "a@b.com", PasswordHash = "hash", DisplayName = "홍길동" };

        Assert.False(user.IsDeleted);
        Assert.Null(user.UpdatedAt);
        Assert.Empty(user.AgentDevices);
    }

    [Fact]
    public void AgentDevice_DefaultsToNeverSeenAndActive()
    {
        var device = new AgentDevice { Name = "SIM-PC", ApiKeyHash = "hash" };

        Assert.Null(device.LastSeenAt);
        Assert.False(device.IsDeleted);
    }

    [Fact]
    public void Lap_Defaults_AreNotRankingEligibleUntilSet()
    {
        var lap = new Lap { GameCode = "F1_25" };

        Assert.False(lap.IsRankingEligible);
        Assert.False(lap.IsInvalidatedManually);
        Assert.Empty(lap.Sectors);
        Assert.Equal(Guid.Empty, lap.AgentDeviceId);
    }

    [Fact]
    public void Season_Defaults_AreSaneForNewEntity()
    {
        var season = new Season { GameCode = "F1_25" };

        Assert.False(season.IsDeleted);
        Assert.Null(season.UpdatedAt);
        Assert.Empty(season.Weekends);
    }

    [Fact]
    public void RaceWeekend_Defaults_AreSaneForNewEntity()
    {
        var weekend = new RaceWeekend();

        Assert.False(weekend.IsDeleted);
        Assert.Null(weekend.UpdatedAt);
    }

    [Fact]
    public void GameSession_Defaults_AreSaneForNewEntity()
    {
        var session = new GameSession { GameCode = "F1_25", SessionKey = "uid:1", SessionRef = "1" };

        Assert.False(session.IsDeleted);
        Assert.Null(session.UpdatedAt);
        Assert.Null(session.SeasonId);
        Assert.Null(session.RaceWeekendId);
        Assert.Empty(session.Results);
    }

    [Fact]
    public void SessionResult_Defaults_AreSaneForNewEntity()
    {
        var result = new SessionResult { DriverKey = "player" };

        Assert.False(result.IsDeleted);
        Assert.Null(result.UpdatedAt);
        Assert.Null(result.DriverName);
        Assert.Null(result.GameDriverId);
        Assert.Null(result.TeamId);
        Assert.Null(result.RaceNumber);
        Assert.Empty(result.TyreStints);
    }

    [Fact]
    public void SessionResultTyreStint_Defaults_AreSaneForNewEntity()
    {
        var stint = new SessionResultTyreStint();

        Assert.False(stint.IsDeleted);
        Assert.Null(stint.UpdatedAt);
        Assert.Null(stint.ActualCompound);
    }
}
