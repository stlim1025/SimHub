using SimCenter.Domain.Enums;
using SimCenter.Domain.Seasons;

namespace SimCenter.Domain.Tests.Seasons;

public class SeasonPolicyTests
{
    private const long SeasonLinkId = 11;
    private const long WeekendLinkId = 22;

    [Theory]
    [InlineData(GameMode.DriverCareer, true)]
    [InlineData(GameMode.MyTeamCareer, true)]
    [InlineData(GameMode.OnlineCareer, true)]
    [InlineData(GameMode.ChallengeCareer, true)]
    [InlineData(GameMode.GrandPrix, true)]
    [InlineData(GameMode.TimeTrial, false)]
    [InlineData(GameMode.Online, false)]
    [InlineData(GameMode.Story, false)]
    [InlineData(GameMode.Other, false)]
    public void BelongsToSeason_ByMode(GameMode mode, bool expected) =>
        Assert.Equal(expected, SeasonPolicy.BelongsToSeason(mode, SeasonLinkId, WeekendLinkId));

    [Theory]
    [InlineData(0, 22)]
    [InlineData(11, 0)]
    [InlineData(0, 0)]
    public void BelongsToSeason_ZeroLink_IsFalse(long seasonLinkId, long weekendLinkId) =>
        Assert.False(SeasonPolicy.BelongsToSeason(GameMode.DriverCareer, seasonLinkId, weekendLinkId));
}
