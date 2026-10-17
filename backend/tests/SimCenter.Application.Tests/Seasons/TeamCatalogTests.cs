using System.Text.RegularExpressions;
using SimCenter.Application.Seasons.Queries;

namespace SimCenter.Application.Tests.Seasons;

public class TeamCatalogTests
{
    private const string GameCode = "F1_25";
    private const string FallbackColor = "#9CA3AF";

    [Theory]
    [InlineData(0, "Mercedes", "#27F4D2")]
    [InlineData(1, "Ferrari", "#E8002D")]
    [InlineData(2, "Red Bull Racing", "#3671C6")]
    [InlineData(3, "Williams", "#64C4FF")]
    [InlineData(4, "Aston Martin", "#229971")]
    [InlineData(5, "Alpine", "#0093CC")]
    [InlineData(6, "Racing Bulls", "#6692FF")]
    [InlineData(7, "Haas", "#B6BABD")]
    [InlineData(8, "McLaren", "#FF8000")]
    [InlineData(9, "Sauber", "#52E252")]
    [InlineData(41, "F1 Generic", "#9CA3AF")]
    [InlineData(104, "My Team", "#6366F1")]
    [InlineData(185, "Mercedes", "#27F4D2")]
    [InlineData(187, "Red Bull Racing", "#3671C6")]
    [InlineData(194, "Sauber", "#52E252")]
    [InlineData(476, "Mercedes", "#27F4D2")]
    [InlineData(478, "Red Bull Racing", "#3671C6")]
    [InlineData(484, "McLaren", "#FF8000")]
    [InlineData(485, "Audi", "#BB0A30")]
    [InlineData(486, "Cadillac", "#B5B5B5")]
    public void Resolve_KnownTeam(int id, string name, string color)
    {
        var team = TeamCatalog.Resolve(GameCode, id);

        Assert.Equal(name, team.Name);
        Assert.Equal(color, team.Color);
    }

    [Theory]
    [InlineData(10)]
    [InlineData(184)]
    [InlineData(195)]
    [InlineData(475)]
    [InlineData(487)]
    [InlineData(999)]
    [InlineData(-1)]
    public void Resolve_UnknownTeam_UsesFallback(int id)
    {
        var team = TeamCatalog.Resolve(GameCode, id);

        Assert.Equal($"Team {id}", team.Name);
        Assert.Equal(FallbackColor, team.Color);
    }

    [Fact]
    public void Resolve_NullTeam_IsUnknownTeam()
    {
        var team = TeamCatalog.Resolve(GameCode, null);

        Assert.Equal("Unknown Team", team.Name);
        Assert.Equal(FallbackColor, team.Color);
    }

    [Fact]
    public void Resolve_OtherGameCode_UsesFallback()
    {
        var team = TeamCatalog.Resolve("ACC", 2);

        Assert.Equal("Team 2", team.Name);
        Assert.Equal(FallbackColor, team.Color);
    }

    [Fact]
    public void FallbackColor_IsNeutralGray()
    {
        Assert.Equal(FallbackColor, TeamCatalog.FallbackColor);
    }

    [Fact]
    public void AllColors_AreHexRrggbb()
    {
        var hex = new Regex("^#[0-9A-F]{6}$");
        var known = 0;

        for (var id = -5; id <= 1000; id++)
        {
            var team = TeamCatalog.Resolve(GameCode, id);
            Assert.Matches(hex, team.Color);
            if (!team.Name.StartsWith("Team ", StringComparison.Ordinal))
            {
                known++;
            }
        }

        // 2025 팀 10 + F1 Generic + My Team + 2024 차량 10 + 2026 팀 9 + Audi + Cadillac
        Assert.Equal(10 + 1 + 1 + 10 + 9 + 2, known);
    }
}
