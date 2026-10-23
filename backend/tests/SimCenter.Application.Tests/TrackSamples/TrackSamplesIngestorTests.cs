using System.IO.Compression;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Telemetry;
using SimCenter.Application.TrackSamples;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.TrackSamples;

public class TrackSamplesIngestorTests
{
    private const string GameCode = "F1_25";
    private const int GameTrackId = 6;

    private static readonly DateTime Now = new(2026, 10, 23, 9, 0, 0, DateTimeKind.Utc);
    private static readonly JsonSerializerOptions WireOptions = new(JsonSerializerDefaults.Web);

    private readonly FakeTrackRepository _tracks = new();
    private readonly FakeChunkRepository _chunks = new();
    private readonly AgentDevice _device = new()
    {
        Id = Guid.Parse("00000000-0000-0000-0000-0000000000e1"),
        UserId = Guid.Parse("00000000-0000-0000-0000-0000000000a1"),
        Name = "SIM-PC",
        ApiKeyHash = "h",
    };

    private readonly Guid _trackId = Guid.Parse("00000000-0000-0000-0000-0000000000c6");
    private readonly TrackSamplesIngestor _sut;

    public TrackSamplesIngestorTests()
    {
        _tracks.Items.Add(new Track { Id = _trackId, GameCode = GameCode, GameTrackId = GameTrackId, Name = "Montreal" });
        _sut = new TrackSamplesIngestor(_tracks, _chunks, new SequentialIdGenerator(), NullLogger<TrackSamplesIngestor>.Instance);
    }

    private static byte[] Gzip(byte[] raw)
    {
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Fastest))
        {
            gzip.Write(raw);
        }

        return output.ToArray();
    }

    private static TelemetryEnvelopeDto Envelope(
        string sessionType = "Race", int format = 1, int chunkIndex = 0, string? data = null, int trackId = GameTrackId, int sampleRateHz = 10)
        => new(Guid.NewGuid(), GameCode, Now, "TrackSamplesChunk", JsonSerializer.SerializeToElement(new
        {
            sessionRef = "123456789",
            trackId,
            sessionType,
            trackLengthM = 4361,
            format,
            sampleRateHz,
            chunkIndex,
            isLast = true,
            frameCount = 3,
            sampleCount = 40,
            data = data ?? Convert.ToBase64String(Gzip([1, 2, 3, 4])),
        }, WireOptions));

    [Fact]
    public async Task ValidChunk_IsTrackedWithGzipPayloadAndOwner()
    {
        var reason = await _sut.ApplyAsync(Envelope(), _device, Now);

        Assert.Null(reason);
        var chunk = Assert.Single(_chunks.Items);
        Assert.Equal(_device.Id, chunk.AgentDeviceId);
        Assert.Equal(_device.UserId, chunk.UserId);
        Assert.Equal(_trackId, chunk.TrackId);
        Assert.Equal(GameCode, chunk.GameCode);
        Assert.Equal("123456789", chunk.SessionRef);
        Assert.Equal(SessionType.Race, chunk.SessionType);
        Assert.True(chunk.IsLast);
        Assert.Equal(10, chunk.SampleRateHz);
        Assert.Equal(40, chunk.SampleCount);
        Assert.Equal(4361, chunk.TrackLengthM);
        Assert.Equal(0x1f, chunk.Payload[0]);
        Assert.Equal(Now, chunk.CreatedAt);
    }

    [Fact]
    public async Task SameChunkAgain_IsAcknowledgedWithoutSecondRow()
    {
        await _sut.ApplyAsync(Envelope(), _device, Now);

        var reason = await _sut.ApplyAsync(Envelope(), _device, Now);

        Assert.Null(reason);
        Assert.Single(_chunks.Items);
    }

    [Theory]
    [InlineData("TimeTrial")]
    [InlineData("Unknown")]
    [InlineData("race")]
    public async Task NonCollectedSessionType_IsRejected(string sessionType)
    {
        var reason = await _sut.ApplyAsync(Envelope(sessionType: sessionType), _device, Now);

        Assert.StartsWith("TrackSamplesChunk 검증 실패: sessionType", reason);
        Assert.Empty(_chunks.Items);
    }

    [Fact]
    public async Task InvalidData_IsRejected()
    {
        Assert.Contains("base64", await _sut.ApplyAsync(Envelope(data: "%%%"), _device, Now));
        Assert.Contains("gzip", await _sut.ApplyAsync(Envelope(data: Convert.ToBase64String([1, 2, 3])), _device, Now));
        var tooBig = Convert.ToBase64String(Gzip(RandomBytes(TrackSamplesChunkValidator.MaxPayloadBytes + 1024)));
        Assert.Contains("넘습니다", await _sut.ApplyAsync(Envelope(data: tooBig), _device, Now));
        Assert.Empty(_chunks.Items);
    }

    [Fact]
    public async Task UnsupportedFormatOrRate_IsRejected()
    {
        Assert.Contains("format", await _sut.ApplyAsync(Envelope(format: 3), _device, Now));
        Assert.Contains("sampleRateHz", await _sut.ApplyAsync(Envelope(sampleRateHz: 0), _device, Now));
        Assert.Contains("chunkIndex", await _sut.ApplyAsync(Envelope(chunkIndex: -1), _device, Now));
        Assert.Empty(_chunks.Items);

        Assert.Null(await _sut.ApplyAsync(Envelope(format: 2), _device, Now)); // G-force·속도·손상 열이 붙은 format 2
        Assert.Equal(2, Assert.Single(_chunks.Items).Format);
    }

    [Fact]
    public async Task UnknownTrack_IsRejected()
    {
        var reason = await _sut.ApplyAsync(Envelope(trackId: 99), _device, Now);

        Assert.StartsWith("트랙 매핑 없음", reason);
        Assert.Empty(_chunks.Items);
    }

    private static byte[] RandomBytes(int length)
    {
        var bytes = new byte[length];
        new Random(7).NextBytes(bytes);
        return bytes;
    }

    private sealed class FakeTrackRepository : ITrackRepository
    {
        public List<Track> Items { get; } = new();

        public Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.GameCode == gameCode && x.GameTrackId == gameTrackId));

        public Task<Track?> GetByIdAsync(Guid id, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.Id == id));

        public Task<IReadOnlyList<Track>> GetAllAsync(CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<Track>>(Items.ToList());
    }

    private sealed class FakeChunkRepository : ITrackSampleChunkRepository
    {
        public List<TrackSampleChunk> Items { get; } = new();

        public Task<bool> ExistsAsync(Guid agentDeviceId, string sessionRef, int chunkIndex, CancellationToken ct = default)
            => Task.FromResult(Items.Any(x => x.AgentDeviceId == agentDeviceId && x.SessionRef == sessionRef && x.ChunkIndex == chunkIndex));

        public Task AddAsync(TrackSampleChunk chunk, CancellationToken ct = default)
        {
            Items.Add(chunk);
            return Task.CompletedTask;
        }
    }

    private sealed class SequentialIdGenerator : IIdGenerator
    {
        private int _next;

        public Guid NewId() => new($"00000000-0000-0000-0000-{++_next:D12}");
    }
}
