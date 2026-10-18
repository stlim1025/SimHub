using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Laps;

/// <summary>메모리 랩 조회 저장소. 실제 구현과 같은 규칙(내 것만, 유효 랩만 필터, 비교 = 빠른 순 → 먼저 세운 순)을 흉내 낸다.</summary>
internal sealed class FakeLapQueryRepository : ILapQueryRepository
{
    public List<(Guid UserId, LapRow Row)> Laps { get; } = new();
    public Dictionary<Guid, LapSnapshot> Snapshots { get; } = new();
    public Dictionary<Guid, LapTelemetryTrace> Traces { get; } = new();

    public MyLapsFilter? LastFilter { get; private set; }
    public MyLapsSort? LastSort { get; private set; }
    public int CallCount { get; private set; }

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
        string gameCode = "F1_25") => new(
            lapId, trackId, "Jeddah", "SA", gameCode, SessionType.TimeTrial, 5, lapTimeMs, isValid, isValid,
            setAt ?? new DateTime(2026, 10, 18, 9, 0, 0, DateTimeKind.Utc), gameMode, sessionKey, teamId, weather, hasTrace,
            [new LapSectorDto(1, lapTimeMs / 2), new LapSectorDto(2, lapTimeMs - (lapTimeMs / 2))]);

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

    public Task<LapRow?> GetMyFastestValidAsync(Guid userId, Guid trackId, string gameCode, CancellationToken cancellationToken = default)
    {
        CallCount++;
        return Task.FromResult(Mine(userId)
            .Where(r => r.TrackId == trackId && r.GameCode == gameCode && r.IsValid)
            .OrderBy(r => r.LapTimeMs)
            .ThenBy(r => r.SetAt)
            .FirstOrDefault());
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

    private IEnumerable<LapRow> Mine(Guid userId) => Laps.Where(l => l.UserId == userId).Select(l => l.Row);
}
