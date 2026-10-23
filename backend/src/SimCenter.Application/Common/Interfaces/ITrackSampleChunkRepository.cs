using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>트랙 형상 표본 조각 저장소 포트.</summary>
public interface ITrackSampleChunkRepository
{
    /// <summary>같은 장치·세션·순번의 조각이 이미 있는지.</summary>
    Task<bool> ExistsAsync(Guid agentDeviceId, string sessionRef, int chunkIndex, CancellationToken cancellationToken = default);

    /// <summary>조각을 추적에 더한다(저장은 호출자의 커밋과 함께).</summary>
    Task AddAsync(TrackSampleChunk chunk, CancellationToken cancellationToken = default);
}
