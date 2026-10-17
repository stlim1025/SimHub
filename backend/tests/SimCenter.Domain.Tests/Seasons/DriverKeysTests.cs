using SimCenter.Domain.Seasons;

namespace SimCenter.Domain.Tests.Seasons;

public class DriverKeysTests
{
    private const string SessionRef = "S";

    [Fact]
    public void Player_ConstantIsStable() =>
        Assert.Equal("player", DriverKeys.Player);

    [Fact]
    public void Build_Player_IgnoresOtherFields() =>
        Assert.Equal("player", DriverKeys.Build(true, 9, "X", 1, SessionRef, 0));

    [Fact]
    public void Build_GameDriverId_UsesDriverId() =>
        Assert.Equal("driver:9", DriverKeys.Build(false, 9, "VERSTAPPEN", 1, SessionRef, 4));

    [Fact]
    public void Build_NoDriverId_UsesNormalizedNameAndNumber() =>
        Assert.Equal("name:LIM#26", DriverKeys.Build(false, null, "  lim ", 26, SessionRef, 4));

    [Fact]
    public void Build_NoDriverIdNoNumber_UsesNameWithEmptyNumber() =>
        Assert.Equal("name:LIM#", DriverKeys.Build(false, null, "  lim ", null, SessionRef, 4));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void Build_NoIdentity_UsesSessionScopedCarKey(string? name) =>
        Assert.Equal("car:S1:4", DriverKeys.Build(false, null, name, 26, "S1", 4));
}
