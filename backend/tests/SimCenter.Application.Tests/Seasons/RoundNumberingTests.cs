using SimCenter.Application.Seasons.Queries;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons;

public class RoundNumberingTests
{
    private static WeekendRow Weekend(int id, double hours) => new(Id(id), Id(100), $"Track {id}", At(hours));

    [Fact]
    public void Assign_OrdersByFirstSessionAt_ThenId()
    {
        var weekends = new[]
        {
            Weekend(id: 9, hours: 30),
            Weekend(id: 5, hours: 10),   // 같은 시각 → Id 순
            Weekend(id: 2, hours: 10),
            Weekend(id: 8, hours: 20),
        };

        var rounds = RoundNumbering.Assign(weekends);

        Assert.Equal(4, rounds.Count);
        Assert.Equal(1, rounds[Id(2)]);
        Assert.Equal(2, rounds[Id(5)]);
        Assert.Equal(3, rounds[Id(8)]);
        Assert.Equal(4, rounds[Id(9)]);
    }

    [Fact]
    public void Assign_NoWeekends_ReturnsEmpty()
    {
        Assert.Empty(RoundNumbering.Assign(Array.Empty<WeekendRow>()));
    }
}
