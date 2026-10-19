using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons;

public class SeasonSessionSelectorTests
{
    [Fact]
    public void Select_DuplicateKindInWeekend_KeepsLatest()
    {
        var rows = new[]
        {
            Row(session: 1, weekend: 1, "a", position: 1, points: 25, hours: 10),
            Row(session: 1, weekend: 1, "b", position: 2, points: 18, hours: 10),
            Row(session: 2, weekend: 1, "a", position: 1, points: 25, hours: 11),
            Row(session: 2, weekend: 1, "b", position: 2, points: 18, hours: 11),
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.Equal(2, selection.CountedRows.Count);
        Assert.All(selection.CountedRows, r => Assert.Equal(Id(2), r.SessionId));
        Assert.Equal(Id(2), selection.MainRaceSessionByWeekend[Id(1)]);
    }

    [Fact]
    public void Select_DuplicateKind_SameClassifiedAt_KeepsGreaterSessionId()
    {
        var rows = new[]
        {
            Row(session: 3, weekend: 1, "a", position: 1, points: 25, hours: 10),
            Row(session: 7, weekend: 1, "a", position: 1, points: 25, hours: 10),
        };

        var selection = SeasonSessionSelector.Select(rows);

        var kept = Assert.Single(selection.CountedRows);
        Assert.Equal(Id(7), kept.SessionId);
    }

    [Fact]
    public void Select_SameKindInDifferentWeekends_BothKept()
    {
        var rows = new[]
        {
            Row(session: 1, weekend: 1, "a", position: 1, points: 25, hours: 10),
            Row(session: 2, weekend: 2, "a", position: 1, points: 25, hours: 20),
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.Equal(2, selection.CountedRows.Count);
        Assert.Equal(Id(1), selection.MainRaceSessionByWeekend[Id(1)]);
        Assert.Equal(Id(2), selection.MainRaceSessionByWeekend[Id(2)]);
    }

    [Fact]
    public void Select_UnknownKind_IsNotDeduplicated()
    {
        var rows = new[]
        {
            Row(session: 1, weekend: 1, "a", position: 1, points: 0, type: SessionType.Practice, kind: SessionKind.Unknown, hours: 1),
            Row(session: 2, weekend: 1, "a", position: 1, points: 0, type: SessionType.Practice, kind: SessionKind.Unknown, hours: 2),
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.Equal(2, selection.CountedRows.Count);
        Assert.Equal(new[] { Id(1), Id(2) }, selection.CountedRows.Select(r => r.SessionId));
    }

    [Fact]
    public void Select_MainRace_IsLatestRaceSession()
    {
        var rows = new[]
        {
            Row(session: 1, weekend: 1, "a", position: 3, points: 6, kind: SessionKind.Race, hours: 10),   // 스프린트
            Row(session: 2, weekend: 1, "a", position: 1, points: 25, kind: SessionKind.Race2, hours: 14),  // 본 레이스
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.Equal(2, selection.CountedRows.Count);
        Assert.Equal(Id(2), selection.MainRaceSessionByWeekend[Id(1)]);
    }

    [Fact]
    public void Select_WeekendWithoutRace_HasNoMainRace()
    {
        var rows = new[]
        {
            Row(session: 1, weekend: 1, "a", position: 1, points: 0, type: SessionType.Qualifying, kind: SessionKind.Qualifying1, hours: 5),
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.Single(selection.CountedRows);
        Assert.False(selection.MainRaceSessionByWeekend.ContainsKey(Id(1)));
    }

    [Fact]
    public void Select_SprintOnlyWeekend_SprintIsMainRace()
    {
        var rows = new[]
        {
            Row(session: 1, weekend: 1, "a", position: 1, points: 8, kind: SessionKind.Race, hours: 10),
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.Equal(Id(1), selection.MainRaceSessionByWeekend[Id(1)]);
    }

    [Fact]
    public void Select_SprintWeekendBeforeMainRace_HasNoMainRace()
    {
        // 슛아웃이 있으면 스프린트 주말이다 — 그 주말의 Race는 스프린트라 본 레이스(Race2)를 달리기 전에는 본 레이스가 없다.
        var rows = new[]
        {
            Row(session: 1, weekend: 1, "a", position: 3, points: 0, type: SessionType.Qualifying, kind: SessionKind.SprintShootout3, hours: 9),
            Row(session: 2, weekend: 1, "a", position: 1, points: 8, kind: SessionKind.Race, hours: 10),
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.False(selection.MainRaceSessionByWeekend.ContainsKey(Id(1)));
        Assert.Equal(2, selection.CountedRows.Count);   // 스프린트 행은 계산 대상으로 남는다(점수)
    }

    [Fact]
    public void Select_SprintWeekend_MainRaceIsRace2_EvenIfSprintClassifiedLater()
    {
        var rows = new[]
        {
            Row(session: 1, weekend: 1, "a", position: 2, points: 18, kind: SessionKind.Race2, hours: 10),
            Row(session: 2, weekend: 1, "a", position: 1, points: 8, kind: SessionKind.Race, hours: 11),
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.Equal(Id(1), selection.MainRaceSessionByWeekend[Id(1)]);
    }

    [Fact]
    public void Select_PreservesInputRowOrder()
    {
        var rows = new[]
        {
            Row(session: 2, weekend: 1, "b", position: 2, points: 18, kind: SessionKind.Race2, hours: 14),
            Row(session: 1, weekend: 1, "a", position: 1, points: 8, kind: SessionKind.Race, hours: 10),
            Row(session: 2, weekend: 1, "a", position: 1, points: 25, kind: SessionKind.Race2, hours: 14),
        };

        var selection = SeasonSessionSelector.Select(rows);

        Assert.Equal(rows, selection.CountedRows);
    }

    [Fact]
    public void Select_NoRows_ReturnsEmptySelection()
    {
        var selection = SeasonSessionSelector.Select(Array.Empty<SeasonResultRow>());

        Assert.Empty(selection.CountedRows);
        Assert.Empty(selection.MainRaceSessionByWeekend);
    }
}
