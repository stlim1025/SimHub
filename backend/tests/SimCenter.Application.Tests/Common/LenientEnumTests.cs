using SimCenter.Application.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Common;

public class LenientEnumTests
{
    [Theory]
    [InlineData("Race", SessionKind.Race)]
    [InlineData("race", SessionKind.Race)]
    [InlineData("RACE2", SessionKind.Race2)]
    [InlineData("Sprint", SessionKind.Unknown)]
    [InlineData(null, SessionKind.Unknown)]
    [InlineData("", SessionKind.Unknown)]
    [InlineData("15", SessionKind.Unknown)]
    [InlineData("-1", SessionKind.Unknown)]
    [InlineData("Race,Race2", SessionKind.Unknown)]
    [InlineData(" Race", SessionKind.Unknown)]
    public void Parse_MatchesNameIgnoringCase_ElseDefault(string? input, SessionKind expected)
    {
        Assert.Equal(expected, LenientEnum.Parse<SessionKind>(input));
    }

    [Theory]
    [InlineData("other", GameMode.Other)]
    [InlineData("NewMode", GameMode.Other)]
    [InlineData("grandprix", GameMode.GrandPrix)]
    public void Parse_UsesZeroValueAsFallback_ForOtherEnums(string input, GameMode expected)
    {
        Assert.Equal(expected, LenientEnum.Parse<GameMode>(input));
    }
}
