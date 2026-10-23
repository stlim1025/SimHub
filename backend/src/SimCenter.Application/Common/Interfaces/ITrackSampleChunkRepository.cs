using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>저장된 표본 조각의 본문(gzip)과 풀 때 필요한 값. <paramref name="TrackLengthM"/>은 게임이 알려 준 트랙 길이(모르면 null).</summary>
public sealed record StoredTrackSampleChunk(string SessionRef, int ChunkIndex, int Format, byte[] Payload, int? TrackLengthM = null);

/// <summary>트랙 형상 표본 조각 저장소 포트.</summary>
public interface ITrackSampleChunkRepository
{
    /// <summary>같은 장치·세션·순번의 조각이 이미 있는지.</summary>
    Task<bool> ExistsAsync(Guid agentDeviceId, string sessionRef, int chunkIndex, CancellationToken cancellationToken = default);

    /// <summary>조각을 추적에 더한다(저장은 호출자의 커밋과 함께).</summary>
    Task AddAsync(TrackSampleChunk chunk, CancellationToken cancellationToken = default);

    /// <summary>트랙·게임의 모든 조각(지운 것 제외, 받은 순서).</summary>
    Task<IReadOnlyList<StoredTrackSampleChunk>> ListForTrackAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default);

    /// <summary>내 세션(게임 세션 Ref) 하나의 조각(지운 것 제외, 조각 순서).</summary>
    Task<IReadOnlyList<StoredTrackSampleChunk>> ListForSessionAsync(Guid userId, string sessionRef, CancellationToken cancellationToken = default);
}
