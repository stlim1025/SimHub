using SimCenter.Domain.Constants;

namespace SimCenter.Domain.Tests;

public class GameEditionsTests
{
    [Theory]
    [InlineData(220, true)]
    [InlineData(229, true)]
    [InlineData(230, true)]
    [InlineData(476, true)]
    [InlineData(485, true)]
    [InlineData(486, true)]
    [InlineData(0, false)]
    [InlineData(9, false)]
    [InlineData(104, false)]
    [InlineData(185, false)]
    [InlineData(219, false)]
    [InlineData(231, false)]
    [InlineData(475, false)]
    [InlineData(487, false)]
    public void Is2026TeamId_CoversSeasonPackAndV126Grid(int teamId, bool expected)
    {
        Assert.Equal(expected, GameEditions.Is2026TeamId(teamId));
    }

    [Fact]
    public void Is2026TeamId_Null_IsFalse()
    {
        Assert.False(GameEditions.Is2026TeamId((int?)null));
    }

    [Fact]
    public void Supported_ContainsBothGames()
    {
        Assert.Equal(new[] { GameCodes.F1_25, GameCodes.F1_26 }, GameCodes.Supported);
        Assert.True(GameCodes.IsSupported("F1_26"));
        Assert.False(GameCodes.IsSupported("f1_26"));
    }
}
