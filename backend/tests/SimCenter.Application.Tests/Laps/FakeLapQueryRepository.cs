using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Laps;

/// <summary>
/// 메모리 랩 조회 저장소. 실제 구현과 같은 규칙(내 것만, 유효 랩만 필터, 비교 = 빠른 순 → 먼저 세운 순,
/// 남의 랩은 랭킹 적격만 비교 가능 — D-51)을 흉내 낸다.
/// </summary>
internal sealed class FakeLapQueryRepository : ILapQueryRepository
{
    public List<(Guid UserId, LapRow Row)> Laps { get; } = new();
    public Dictionary<Guid, LapSnapshot> Snapshots { get; } = new();
    public Dictionary<Guid, LapTelemetryTrace> Traces { get; } = new();
    public Dictionary<Guid, LapDriverRow> Drivers { get; } = new();

    public MyLapsFilter? LastFilter { get; private set; }
    public MyLapsSort? LastSort { get; private set; }
    public LapComparisonCriteria? LastCriteria { get; private set; }
    public int CallCount { get; private set; }
    public int DriverCalls { get; private set; }

    public static LapRow Row(
        Guid lapId,
        Guid trackId,
        int lapTimeMs,
        bool isValid = true,
        DateTime? setAt = null,
        int? teamId = null,
        Weather? weather = null,
        bool hasTrace = false,
        string? sessionKey = null,
        string? gameMode = null,
        string gameCode = "F1_25",
        Guid userId = default,
        SessionType sessionType = SessionType.TimeTrial,
        bool? isRankingEligible = null) => new(
            lapId, trackId, "Jeddah", "SA", gameCode, sessionType, 5, lapTimeMs, isValid, isRankingEligible ?? isValid,
            setAt ?? new DateTime(2026, 10, 18, 9, 0, 0, DateTimeKind.Utc), gameMode, sessionKey, teamId, weather, hasTrace,
            [new LapSectorDto(1, lapTimeMs / 2), new LapSectorDto(2, lapTimeMs - (lapTimeMs / 2))], userId);

    public Task<(IReadOnlyList<LapRow> Items, int Total)> GetMyPageAsync(
        Guid userId, MyLapsFilter filter, MyLapsSort sort, int skip, int take, CancellationToken cancellationToken = default)
    {
        CallCount++;
        LastFilter = filter;
        LastSort = sort;
        var rows = Mine(userId)
            .Where(r => filter.TrackId is null || r.TrackId == filter.TrackId)
            .Where(r => filter.SessionType is null || r.SessionType == filter.SessionType)
            .Where(r => !filter.ValidOnly || r.IsValid)
            .ToList();
        return Task.FromResult<(IReadOnlyList<LapRow>, int)>((rows.Skip(skip).Take(take).ToList(), rows.Count));
    }

    public Task<LapRow?> GetMineAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
    {
        CallCount++;
        return Task.FromResult(Mine(userId).FirstOrDefault(r => r.LapId == lapId));
    }

    public Task<LapRow?> FindFastestAsync(LapComparisonCriteria criteria, CancellationToken cancellationToken = default)
    {
        CallCount++;
        LastCriteria = criteria;
        var scope = criteria.Scope == LapComparisonScope.MineValid
            ? Mine(criteria.UserId).Where(r => r.IsValid)
            : Laps.Select(l => l.Row).Where(r => r.IsRankingEligible);
        return Task.FromResult(scope
            .Where(r => r.TrackId == criteria.TrackId && r.GameCode == criteria.GameCode)
            .Where(r => criteria.TeamId is null || r.TeamId == criteria.TeamId)
            .Where(r => criteria.SessionType is null || r.SessionType == criteria.SessionType)
            .Where(r => criteria.Assists is null
                || SameAssists(criteria.Assists, LapAssistValues.From(Snapshots.GetValueOrDefault(r.LapId))))
            .OrderBy(r => r.LapTimeMs)
            .ThenBy(r => r.SetAt)
            .FirstOrDefault());
    }

    public Task<LapRow?> GetComparableAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
    {
        CallCount++;
        return Task.FromResult(Comparable(userId).FirstOrDefault(r => r.LapId == lapId));
    }

    public Task<LapDriverRow?> GetDriverAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        CallCount++;
        DriverCalls++;
        return Task.FromResult(Drivers.GetValueOrDefault(userId));
    }

    public Task<LapSnapshot?> GetSnapshotAsync(Guid lapId, CancellationToken cancellationToken = default)
    {
        CallCount++;
        return Task.FromResult(Snapshots.GetValueOrDefault(lapId));
    }

    public Task<LapTelemetryTrace?> GetMyTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
    {
        CallCount++;
        var mine = Mine(userId).Any(r => r.LapId == lapId);
        return Task.FromResult(mine ? Traces.GetValueOrDefault(lapId) : null);
    }

    public Task<LapTelemetryTrace?> GetComparableTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default)
    {
        CallCount++;
        var comparable = Comparable(userId).Any(r => r.LapId == lapId);
        return Task.FromResult(comparable ? Traces.GetValueOrDefault(lapId) : null);
    }

    /// <summary>실제 구현처럼 조건의 값이 있는 칸만 같아야 한다.</summary>
    private static bool SameAssists(LapAssistValues wanted, LapAssistValues actual)
        => Same(wanted.TractionControl, actual.TractionControl)
            && Same(wanted.AntiLockBrakes, actual.AntiLockBrakes)
            && Same(wanted.SteeringAssist, actual.SteeringAssist)
            && Same(wanted.BrakingAssist, actual.BrakingAssist)
            && Same(wanted.GearboxAssist, actual.GearboxAssist)
            && Same(wanted.DynamicRacingLine, actual.DynamicRacingLine);

    private static bool Same(int? wanted, int? actual) => wanted is null || wanted == actual;

    private IEnumerable<LapRow> Comparable(Guid userId)
        => Laps.Where(l => l.UserId == userId || l.Row.IsRankingEligible).Select(l => l.Row);

    private IEnumerable<LapRow> Mine(Guid userId) => Laps.Where(l => l.UserId == userId).Select(l => l.Row);
}
