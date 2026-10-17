using SimCenter.Domain.Entities;

namespace SimCenter.Domain.Tests.Seasons;

public class SeasonTouchTests
{
    private static readonly DateTime Now = new(2026, 10, 17, 12, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime First = new(2026, 10, 17, 10, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime Last = new(2026, 10, 17, 11, 0, 0, DateTimeKind.Utc);

    private static Season NewSeason() => new()
    {
        GameCode = "F1_25",
        FirstSessionAt = First,
        LastSessionAt = Last,
    };

    [Fact]
    public void Season_Touch_WidensRangeOnly()
    {
        var season = NewSeason();

        var inside = First.AddMinutes(30);
        season.Touch(inside, Now);
        Assert.Equal(First, season.FirstSessionAt);
        Assert.Equal(Last, season.LastSessionAt);
        Assert.Null(season.UpdatedAt);

        var earlier = First.AddHours(-1);
        season.Touch(earlier, Now);
        Assert.Equal(earlier, season.FirstSessionAt);
        Assert.Equal(Last, season.LastSessionAt);
        Assert.Equal(Now, season.UpdatedAt);
    }

    [Fact]
    public void Season_Touch_LaterSessionExtendsLastOnly()
    {
        var season = NewSeason();

        var later = Last.AddHours(1);
        season.Touch(later, Now);

        Assert.Equal(First, season.FirstSessionAt);
        Assert.Equal(later, season.LastSessionAt);
        Assert.Equal(Now, season.UpdatedAt);
    }

    [Fact]
    public void Season_Touch_SameBoundaryDoesNotMarkUpdated()
    {
        var season = NewSeason();

        season.Touch(First, Now);
        season.Touch(Last, Now);

        Assert.Null(season.UpdatedAt);
    }

    [Fact]
    public void Weekend_Touch_KeepsEarliest()
    {
        var weekend = new RaceWeekend { FirstSessionAt = First };

        weekend.Touch(First.AddMinutes(30), Now);
        Assert.Equal(First, weekend.FirstSessionAt);
        Assert.Null(weekend.UpdatedAt);

        var earlier = First.AddHours(-1);
        weekend.Touch(earlier, Now);
        Assert.Equal(earlier, weekend.FirstSessionAt);
        Assert.Equal(Now, weekend.UpdatedAt);
    }
}
