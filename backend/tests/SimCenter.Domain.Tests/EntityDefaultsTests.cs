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
}
