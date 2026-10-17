using SimCenter.Domain.Enums;
using SimCenter.Domain.Seasons;

namespace SimCenter.Domain.Tests.Seasons;

public class SessionKeysTests
{
    private const long SeasonLinkId = 11;
    private const long WeekendLinkId = 22;
    private const long SessionLinkId = 33;
    private const string SessionRef = "999";

    [Fact]
    public void For_SeasonModeWithSessionLink_UsesLinkTriple() =>
        Assert.Equal("link:11:22:33",
            SessionKeys.For(GameMode.DriverCareer, SeasonLinkId, WeekendLinkId, SessionLinkId, SessionRef));

    [Fact]
    public void For_SeasonModeWithoutSessionLink_UsesUid() =>
        Assert.Equal("uid:999",
            SessionKeys.For(GameMode.DriverCareer, SeasonLinkId, WeekendLinkId, 0, SessionRef));

    [Fact]
    public void For_NonSeasonMode_AlwaysUsesUid() =>
        Assert.Equal("uid:999",
            SessionKeys.For(GameMode.Online, SeasonLinkId, WeekendLinkId, SessionLinkId, SessionRef));

    [Theory]
    [InlineData(0, 22)]
    [InlineData(11, 0)]
    public void For_SeasonModeWithoutSeasonOrWeekendLink_UsesUid(long seasonLinkId, long weekendLinkId) =>
        Assert.Equal("uid:999",
            SessionKeys.For(GameMode.DriverCareer, seasonLinkId, weekendLinkId, SessionLinkId, SessionRef));

    [Fact]
    public void Uid_PrefixesSessionRef() =>
        Assert.Equal("uid:999", SessionKeys.Uid(SessionRef));
}
