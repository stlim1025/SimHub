using SimCenter.Domain.Entities;
using static SimCenter.Domain.Tests.Seasons.SessionTestData;

namespace SimCenter.Domain.Tests.Seasons;

public class GameSessionReplaceResultsTests
{
    private static readonly DateTime Now = new(2026, 10, 17, 12, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime Earlier = Now.AddHours(-2);

    [Fact]
    public void ReplaceResults_MergesByCarIndex()
    {
        var car0 = NewResult(0, position: 1, Earlier, stintCount: 2);
        var car1 = NewResult(1, position: 2, Earlier);
        var car2 = NewResult(2, position: 3, Earlier, stintCount: 1);
        var session = NewSession(car0, car1, car2);
        var car0Id = car0.Id;
        var oldCar0Stints = car0.TyreStints.ToList();
        var oldCar2Stints = car2.TyreStints.ToList();

        var newCar0 = NewResult(0, position: 2, Now, stintCount: 1);
        var newCar1 = NewResult(1, position: 1, Now);
        var newCar5 = NewResult(5, position: 3, Now);
        session.ReplaceResults([newCar0, newCar1, newCar5], Now);

        // car 0: 같은 행(Id)의 값만 바뀌고, 옛 스틴트는 soft delete + 새 스틴트가 붙는다.
        var mergedCar0 = Assert.Single(session.Results, r => r.CarIndex == 0 && !r.IsDeleted);
        Assert.Equal(car0Id, mergedCar0.Id);
        Assert.Equal(2, mergedCar0.Position);
        Assert.Equal(Now, mergedCar0.UpdatedAt);
        Assert.Equal(Earlier, mergedCar0.CreatedAt);
        Assert.All(oldCar0Stints, stint =>
        {
            Assert.True(stint.IsDeleted);
            Assert.Equal(Now, stint.UpdatedAt);
        });
        var newStint = Assert.Single(mergedCar0.TyreStints, s => !s.IsDeleted);
        Assert.Same(Assert.Single(newCar0.TyreStints), newStint);
        Assert.Equal(car0Id, newStint.SessionResultId);
        Assert.Equal(oldCar0Stints.Count + 1, mergedCar0.TyreStints.Count);

        // car 1: 값만 바뀐다.
        var mergedCar1 = Assert.Single(session.Results, r => r.CarIndex == 1 && !r.IsDeleted);
        Assert.Equal(car1.Id, mergedCar1.Id);
        Assert.Equal(1, mergedCar1.Position);
        Assert.Equal(Now, mergedCar1.UpdatedAt);

        // car 2: 새 순위표에 없으니 행과 스틴트 모두 soft delete.
        Assert.True(car2.IsDeleted);
        Assert.Equal(Now, car2.UpdatedAt);
        Assert.All(oldCar2Stints, stint =>
        {
            Assert.True(stint.IsDeleted);
            Assert.Equal(Now, stint.UpdatedAt);
        });

        // car 5: 새 행으로 붙고 세션에 연결된다.
        var addedCar5 = Assert.Single(session.Results, r => r.CarIndex == 5);
        Assert.Same(newCar5, addedCar5);
        Assert.False(addedCar5.IsDeleted);
        Assert.Equal(session.Id, addedCar5.GameSessionId);

        // Remove 없음: 옛 행 3개 + 새 행 1개.
        Assert.Equal(4, session.Results.Count);
        Assert.Contains(car2, session.Results);
        Assert.Equal(
            [0, 1, 5],
            session.Results.Where(r => !r.IsDeleted).Select(r => r.CarIndex).OrderBy(c => c));
    }

    [Fact]
    public void ReplaceResults_IgnoresAlreadyDeletedRows()
    {
        var active = NewResult(0, position: 1, Earlier);
        var deletedCar3 = NewResult(3, position: 9, Earlier, stintCount: 1);
        deletedCar3.IsDeleted = true;
        deletedCar3.UpdatedAt = Earlier;
        var session = NewSession(active, deletedCar3);
        var deletedStint = Assert.Single(deletedCar3.TyreStints);

        var newCar3 = NewResult(3, position: 4, Now);
        session.ReplaceResults([NewResult(0, position: 1, Now), newCar3], Now);

        // 이미 지워진 car 3 행은 값·UpdatedAt 그대로.
        Assert.True(deletedCar3.IsDeleted);
        Assert.Equal(9, deletedCar3.Position);
        Assert.Equal(Earlier, deletedCar3.UpdatedAt);
        Assert.Null(deletedStint.UpdatedAt);

        // 새 car 3은 새 행으로 붙는다.
        var addedCar3 = Assert.Single(session.Results, r => r.CarIndex == 3 && !r.IsDeleted);
        Assert.Same(newCar3, addedCar3);
        Assert.NotSame(deletedCar3, addedCar3);
        Assert.Equal(3, session.Results.Count);
    }

    [Fact]
    public void ReplaceResults_NewRowsKeepTheirStintsLinkedToTheRow()
    {
        var session = NewSession();
        var incoming = NewResult(7, position: 1, Now, stintCount: 2);

        session.ReplaceResults([incoming], Now);

        Assert.Same(incoming, Assert.Single(session.Results));
        Assert.Equal(session.Id, incoming.GameSessionId);
        Assert.All(incoming.TyreStints, stint => Assert.Equal(incoming.Id, stint.SessionResultId));
        Assert.All(incoming.TyreStints, stint => Assert.False(stint.IsDeleted));
    }

    [Fact]
    public void ReplaceResults_EmptyIncoming_SoftDeletesEveryActiveRowWithoutRemoving()
    {
        var car0 = NewResult(0, position: 1, Earlier, stintCount: 1);
        var car1 = NewResult(1, position: 2, Earlier);
        var session = NewSession(car0, car1);

        session.ReplaceResults([], Now);

        Assert.Equal(2, session.Results.Count);
        Assert.All(session.Results, row =>
        {
            Assert.True(row.IsDeleted);
            Assert.Equal(Now, row.UpdatedAt);
        });
        Assert.All(car0.TyreStints, stint => Assert.True(stint.IsDeleted));
    }

    [Fact]
    public void ReplaceResults_SameStandingsTwice_KeepsRowsAndIds()
    {
        var car0 = NewResult(0, position: 1, Earlier, stintCount: 1);
        var session = NewSession(car0);

        session.ReplaceResults([NewResult(0, position: 1, Now, stintCount: 1)], Now);
        session.ReplaceResults([NewResult(0, position: 1, Now, stintCount: 1)], Now);

        var active = Assert.Single(session.Results, r => !r.IsDeleted);
        Assert.Same(car0, active);
        Assert.Single(active.TyreStints, s => !s.IsDeleted);
        Assert.Equal(3, active.TyreStints.Count);
    }
}
