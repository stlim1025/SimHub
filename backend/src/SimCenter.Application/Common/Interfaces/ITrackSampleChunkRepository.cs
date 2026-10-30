using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>저장된 표본 조각의 본문(gzip)과 풀 때 필요한 값. <paramref name="TrackLengthM"/>은 게임이 알려 준 트랙 길이(모르면 null).</summary>
public sealed record StoredTrackSampleChunk(string SessionRef, int ChunkIndex, int Format, byte[] Payload, int? TrackLengthM = null);

/// <summary>순위표 없이 끝난 내 표본 세션 하나(저장했다가 이어 달린 레이스의 앞 조각 후보). <paramref name="FirstReceivedAt"/>은 첫 조각을 받은 시각(UTC).</summary>
public sealed record UnclassifiedSampleSession(string SessionRef, DateTime FirstReceivedAt);

/// <summary>트랙·게임 조각의 수와 가장 늦게 받은 시각(UTC, 지운 것 제외) — 그 사이 조각이 늘거나 지워졌는지 보는 값.</summary>
public sealed record TrackSampleVersion(int ChunkCount, DateTime? LatestReceivedAt);

/// <summary>트랙 형상 표본 조각 저장소 포트.</summary>
public interface ITrackSampleChunkRepository
{
    /// <summary>같은 장치·세션·순번의 조각이 이미 있는지.</summary>
    Task<bool> ExistsAsync(Guid agentDeviceId, string sessionRef, int chunkIndex, CancellationToken cancellationToken = default);

    /// <summary>조각을 추적에 더한다(저장은 호출자의 커밋과 함께).</summary>
    Task AddAsync(TrackSampleChunk chunk, CancellationToken cancellationToken = default);

    /// <summary>트랙·게임의 모든 조각(지운 것 제외, 받은 순서).</summary>
    Task<IReadOnlyList<StoredTrackSampleChunk>> ListForTrackAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default);

    /// <summary>트랙·게임 조각의 버전(형상 캐시가 낡았는지 본다). 모르는 구현은 null(캐시하지 않는다).</summary>
    Task<TrackSampleVersion?> GetTrackVersionAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default)
        => Task.FromResult<TrackSampleVersion?>(null);

    /// <summary>내 세션(게임 세션 Ref) 하나의 조각(지운 것 제외, 조각 순서).</summary>
    Task<IReadOnlyList<StoredTrackSampleChunk>> ListForSessionAsync(Guid userId, string sessionRef, CancellationToken cancellationToken = default);

    /// <summary>
    /// 내 표본 세션 중 같은 트랙·게임·세션 유형이면서 순위표(게임 세션)가 없는 것들, [before] 이전에 받기 시작한 것만(최근 것부터).
    /// 모르는 구현은 없다고 본다.
    /// </summary>
    Task<IReadOnlyList<UnclassifiedSampleSession>> ListUnclassifiedSessionsAsync(
        Guid userId, Guid trackId, string gameCode, Domain.Enums.SessionType sessionType, DateTime before,
        CancellationToken cancellationToken = default)
        => Task.FromResult<IReadOnlyList<UnclassifiedSampleSession>>([]);

    /// <summary>[sessionRef] 조각을 처음 받은 시각(UTC, 없으면 null). 모르는 구현은 null.</summary>
    Task<DateTime?> FirstReceivedAtAsync(Guid userId, string sessionRef, CancellationToken cancellationToken = default)
        => Task.FromResult<DateTime?>(null);
}
