using SimCenter.Application.Common;
using SimCenter.Application.Setups;
using SimCenter.Domain.Constants;

namespace SimCenter.Application.Tests.Common;

public sealed class TrackCatalogTests
{
    /// <summary>F1Laps 셋업 slug는 모두 카탈로그에 있는 트랙으로 이어진다.</summary>
    [Theory]
    [InlineData("australia", 0, "Albert Park Circuit")]
    [InlineData("saudi_arabia", 29, "Jeddah Corniche Circuit")]
    [InlineData("usa", 15, "Circuit of the Americas")]
    [InlineData("netherlands_reverse", 41, "Circuit Zandvoort")]
    [InlineData("madrid", 42, "Madring")]
    public void Slug_MapsToCatalogTrack(string slug, int gameTrackId, string circuit)
    {
        Assert.True(F1LapsTrackSlugs.TryGetGameTrackId(slug, out var id));
        Assert.Equal(gameTrackId, id);
        Assert.Equal(circuit, TrackCatalog.Find(GameCodes.F1_25, id)?.CircuitName);
    }

    [Fact]
    public void UnknownSlugAndTrack_AreMissing()
    {
        Assert.False(F1LapsTrackSlugs.TryGetGameTrackId("atlantis", out _));
        Assert.Null(TrackCatalog.Find(GameCodes.F1_25, 999));
        Assert.Null(F1LapsTrackSlugs.GamePath("F1_99"));
        Assert.Equal("f1-26", F1LapsTrackSlugs.GamePath(GameCodes.F1_26));
    }

    [Fact]
    public void ReverseTrack_HasNoGrandPrixOrRecord()
    {
        var reverse = TrackCatalog.Find(GameCodes.F1_25, 39)!;
        Assert.Equal(("Silverstone Circuit", null, 5.891, null), (reverse.CircuitName, reverse.GrandPrixName, reverse.LengthKm, reverse.F1LapRecord));
    }

    [Fact]
    public void F126_OverridesSpanishGrandPrix()
    {
        Assert.Equal("Spanish Grand Prix", TrackCatalog.Find(GameCodes.F1_25, 4)!.GrandPrixName);
        Assert.Equal("Barcelona-Catalunya Grand Prix", TrackCatalog.Find(GameCodes.F1_26, 4)!.GrandPrixName);
        Assert.Null(TrackCatalog.Find(GameCodes.F1_25, 42)!.GrandPrixName);
        Assert.Equal("Spanish Grand Prix", TrackCatalog.Find(GameCodes.F1_26, 42)!.GrandPrixName);
    }
}
