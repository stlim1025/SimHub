using System.Text.Json;
using SimCenter.Application.Common;

namespace SimCenter.Application.Tests.Common;

public class GameEditionResolverTests
{
    private static JsonElement Car(string json) => JsonDocument.Parse(json).RootElement.Clone();

    [Theory]
    [InlineData("""{"teamId":229}""", "F1_26")]
    [InlineData("""{"teamId":486}""", "F1_26")]
    [InlineData("""{"TeamId":476}""", "F1_26")]
    [InlineData("""{"teamId":2}""", "F1_25")]
    [InlineData("""{"teamId":104}""", "F1_25")]
    [InlineData("""{"teamId":"229"}""", "F1_25")]
    [InlineData("""{}""", "F1_25")]
    [InlineData("""[]""", "F1_25")]
    public void ForLap_F1_25Envelope_Uses2026WhenCarTeamIs2026(string car, string expected)
    {
        Assert.Equal(expected, GameEditionResolver.ForLap("F1_25", Car(car)));
    }

    [Fact]
    public void ForLap_NoCar_KeepsEnvelopeCode()
    {
        Assert.Equal("F1_25", GameEditionResolver.ForLap("F1_25", null));
    }

    [Fact]
    public void ForLap_AlreadyF1_26_OrOtherGame_KeepsEnvelopeCode()
    {
        Assert.Equal("F1_26", GameEditionResolver.ForLap("F1_26", Car("""{"teamId":2}""")));
        Assert.Equal("ACC", GameEditionResolver.ForLap("ACC", Car("""{"teamId":229}""")));
    }

    [Fact]
    public void ForClassification_Any2026Team_IsF1_26()
    {
        Assert.Equal("F1_26", GameEditionResolver.ForClassification("F1_25", [104, null, 225]));
        Assert.Equal("F1_25", GameEditionResolver.ForClassification("F1_25", [104, null, 2]));
        Assert.Equal("F1_25", GameEditionResolver.ForClassification("F1_25", null));
        Assert.Equal("F1_26", GameEditionResolver.ForClassification("F1_26", [1]));
    }
}
