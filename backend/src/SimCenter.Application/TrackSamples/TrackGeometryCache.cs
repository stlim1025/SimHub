using System.Collections.Concurrent;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.TrackSamples;

/// <summary>
/// 트랙·게임별로 마지막에 만든 형상 응답(서버 메모리, 싱글턴). 모든 조각을 풀어 다시 계산하는 일은 무거워서,
/// 조각 버전(<see cref="TrackSampleVersion"/>)이 그대로면 저장해 둔 응답을 돌려준다. 서버가 다시 뜨면 비어 있다.
/// </summary>
public sealed class TrackGeometryCache
{
    private readonly ConcurrentDictionary<(Guid TrackId, string GameCode), (TrackSampleVersion Version, TrackGeometryResponse Response)> _entries = new();

    /// <summary>같은 버전으로 만든 응답이 있으면 그것, 없거나 낡았으면 null.</summary>
    public TrackGeometryResponse? Get(Guid trackId, string gameCode, TrackSampleVersion version)
        => _entries.TryGetValue((trackId, gameCode), out var entry) && entry.Version == version ? entry.Response : null;

    public void Set(Guid trackId, string gameCode, TrackSampleVersion version, TrackGeometryResponse response)
        => _entries[(trackId, gameCode)] = (version, response);
}
