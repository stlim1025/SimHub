using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Tests;

public class EntityDefaultsTests
{
    [Fact]
    public void User_Defaults_AreSaneForNewEntity()
    {
        var user = new User { Email = "a@b.com", PasswordHash = "hash", DisplayName = "홍길동" };

        Assert.False(user.IsDeleted);
        Assert.Null(user.UpdatedAt);
        Assert.Empty(user.Sessions);
    }

    [Fact]
    public void DrivingSession_DefaultStatus_IsActive()
    {
        var session = new DrivingSession { GameCode = "F1_25" };

        Assert.Equal(SessionStatus.Active, session.Status);
        Assert.Null(session.EndedAt);
    }

    [Fact]
    public void Lap_Defaults_AreNotRankingEligibleUntilSet()
    {
        var lap = new Lap { GameCode = "F1_25" };

        Assert.False(lap.IsRankingEligible);
        Assert.False(lap.IsInvalidatedManually);
        Assert.Empty(lap.Sectors);
    }
}
