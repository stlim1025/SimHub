using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.TrackSamples;
using SimCenter.Domain.Entities;
using static SimCenter.Application.Tests.TrackSamples.TrackSamplePayloads;

namespace SimCenter.Application.Tests.TrackSamples;

/// <summary>트랙 형상 서비스: 조각 버전이 그대로면 만든 형상을 다시 쓰고, 조각이 바뀌면 다시 만든다.</summary>
public sealed class TrackGeometryServiceTests
{
    private const double Radius = 100;
    private const string GameCode = "F1_25";

    [Fact]
    public async Task GetAsync_SameChunkVersion_ReusesTheGeometry_AndRebuildsWhenChunksChange()
    {
        var repository = new CountingChunkRepository(CircleLap());
        var service = new TrackGeometryService(repository, new TrackGeometryCache(), NullLogger<TrackGeometryService>.Instance);
        var trackId = Guid.NewGuid();

        var first = await service.GetAsync(trackId, GameCode);
        var again = await service.GetAsync(trackId, GameCode);
        repository.Version = repository.Version with { ChunkCount = 2 };
        var rebuilt = await service.GetAsync(trackId, GameCode);

        Assert.Same(first, again);
        Assert.NotSame(first, rebuilt);
        Assert.Equal(2, repository.ListCalls);
        Assert.Equal(first.X.Count, first.EdgeLeftM!.Count);
        Assert.Equal(first.X.Count, first.ReachRightM!.Count);
    }

    /// <summary>반지름 100m 원을 한 바퀴 도는 차 한 대(2m마다 표본).</summary>
    private static byte[] CircleLap()
    {
        var frames = new List<Sample[]>();
        for (var d = 0.0; d < 2 * Math.PI * Radius; d += 2)
        {
            var angle = d / Radius;
            frames.Add([new Sample(0, d, Radius * Math.Cos(angle), Radius * Math.Sin(angle))]);
        }

        return Encode(frames);
    }

    private sealed class CountingChunkRepository(byte[] payload) : ITrackSampleChunkRepository
    {
        public TrackSampleVersion Version { get; set; } = new(1, new DateTime(2026, 10, 30, 0, 0, 0, DateTimeKind.Utc));

        public int ListCalls { get; private set; }

        public Task<TrackSampleVersion?> GetTrackVersionAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default)
            => Task.FromResult<TrackSampleVersion?>(Version);

        public Task<IReadOnlyList<StoredTrackSampleChunk>> ListForTrackAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default)
        {
            ListCalls++;
            return Task.FromResult<IReadOnlyList<StoredTrackSampleChunk>>([new StoredTrackSampleChunk("s1", 0, 5, payload)]);
        }

        public Task<IReadOnlyList<StoredTrackSampleChunk>> ListForSessionAsync(Guid userId, string sessionRef, CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<StoredTrackSampleChunk>>([]);

        public Task<bool> ExistsAsync(Guid agentDeviceId, string sessionRef, int chunkIndex, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task AddAsync(TrackSampleChunk chunk, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
