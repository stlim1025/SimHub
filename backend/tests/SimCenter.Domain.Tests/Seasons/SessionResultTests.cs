using System.Reflection;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Domain.Tests.Seasons.SessionTestData;

namespace SimCenter.Domain.Tests.Seasons;

public class SessionResultTests
{
    private static readonly DateTime Now = new(2026, 10, 17, 12, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime Earlier = Now.AddHours(-2);

    /// <summary><see cref="SessionResult.CopyValuesFrom"/>이 건드리면 안 되는 속성(정체성·관계·삭제 상태).</summary>
    private static readonly HashSet<string> NonValueProperties =
    [
        nameof(SessionResult.Id),
        nameof(SessionResult.GameSessionId),
        nameof(SessionResult.CreatedAt),
        nameof(SessionResult.UpdatedAt),
        nameof(SessionResult.IsDeleted),
        nameof(SessionResult.TyreStints),
    ];

    [Fact]
    public void CopyValuesFrom_CopiesEveryValueFieldAndStampsUpdatedAt()
    {
        var target = NewResult(0, position: 1, Earlier, stintCount: 1);
        var sessionId = Guid.NewGuid();
        target.GameSessionId = sessionId;
        var source = new SessionResult
        {
            Id = Guid.NewGuid(),
            CreatedAt = Now,
            CarIndex = 3,
            Position = 2,
            GridPosition = 5,
            NumLaps = 57,
            Points = 18,
            NumPitStops = 2,
            NumPenalties = 1,
            ResultStatus = ResultStatus.DidNotFinish,
            BestLapTimeMs = 91_234,
            TotalRaceTimeMs = 5_400_000,
            PenaltiesTimeMs = 5_000,
            DriverKey = "driver:44",
            DriverName = "HAMILTON",
            GameDriverId = 44,
            TeamId = 1,
            RaceNumber = 44,
            IsAiControlled = true,
            IsPlayer = true,
        };
        var targetId = target.Id;
        var stints = target.TyreStints.ToList();

        target.CopyValuesFrom(source, Now);

        var valueProperties = typeof(SessionResult).GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(p => !NonValueProperties.Contains(p.Name))
            .ToList();
        Assert.NotEmpty(valueProperties);
        foreach (var property in valueProperties)
        {
            Assert.Equal(property.GetValue(source), property.GetValue(target));
        }

        Assert.Equal(targetId, target.Id);
        Assert.Equal(sessionId, target.GameSessionId);
        Assert.Equal(Earlier, target.CreatedAt);
        Assert.False(target.IsDeleted);
        Assert.Equal(Now, target.UpdatedAt);
        Assert.Equal(stints, target.TyreStints);
    }

    [Fact]
    public void CopyValuesFrom_NullableSourceFields_OverwriteWithNull()
    {
        var target = NewResult(0, position: 1, Earlier);
        target.GameDriverId = 9;
        target.TeamId = 2;
        target.RaceNumber = 33;
        var source = NewResult(0, position: 1, Now);
        source.DriverName = null;
        source.GameDriverId = null;
        source.TeamId = null;
        source.RaceNumber = null;

        target.CopyValuesFrom(source, Now);

        Assert.Null(target.DriverName);
        Assert.Null(target.GameDriverId);
        Assert.Null(target.TeamId);
        Assert.Null(target.RaceNumber);
    }

    [Fact]
    public void ReplaceTyreStints_SoftDeletesActiveStintsAndAppendsNewOnes()
    {
        var result = NewResult(0, position: 1, Earlier, stintCount: 2);
        var oldStints = result.TyreStints.ToList();
        var alreadyDeleted = NewStint(result.Id, 3, Earlier);
        alreadyDeleted.IsDeleted = true;
        alreadyDeleted.UpdatedAt = Earlier;
        result.TyreStints.Add(alreadyDeleted);
        var added = NewStint(Guid.Empty, 1, Now);

        result.ReplaceTyreStints([added], Now);

        Assert.All(oldStints, stint =>
        {
            Assert.True(stint.IsDeleted);
            Assert.Equal(Now, stint.UpdatedAt);
        });
        Assert.True(alreadyDeleted.IsDeleted);
        Assert.Equal(Earlier, alreadyDeleted.UpdatedAt);
        Assert.Same(added, Assert.Single(result.TyreStints, s => !s.IsDeleted));
        Assert.Equal(result.Id, added.SessionResultId);
        Assert.Equal(4, result.TyreStints.Count);
    }

    [Fact]
    public void ReplaceTyreStints_EmptyList_OnlySoftDeletes()
    {
        var result = NewResult(0, position: 1, Earlier, stintCount: 2);

        result.ReplaceTyreStints([], Now);

        Assert.Equal(2, result.TyreStints.Count);
        Assert.All(result.TyreStints, stint => Assert.True(stint.IsDeleted));
    }

    [Fact]
    public void SoftDelete_MarksRowAndActiveStints_LeavesDeletedStintsUntouched()
    {
        var result = NewResult(0, position: 1, Earlier, stintCount: 1);
        var activeStint = Assert.Single(result.TyreStints);
        var deletedStint = NewStint(result.Id, 2, Earlier);
        deletedStint.IsDeleted = true;
        deletedStint.UpdatedAt = Earlier;
        result.TyreStints.Add(deletedStint);

        result.SoftDelete(Now);

        Assert.True(result.IsDeleted);
        Assert.Equal(Now, result.UpdatedAt);
        Assert.True(activeStint.IsDeleted);
        Assert.Equal(Now, activeStint.UpdatedAt);
        Assert.Equal(Earlier, deletedStint.UpdatedAt);
        Assert.Equal(2, result.TyreStints.Count);
    }

    [Fact]
    public void SoftDelete_OnAlreadyDeletedRow_IsNoOp()
    {
        var result = NewResult(0, position: 1, Earlier);
        result.IsDeleted = true;
        result.UpdatedAt = Earlier;

        result.SoftDelete(Now);

        Assert.Equal(Earlier, result.UpdatedAt);
    }
}
