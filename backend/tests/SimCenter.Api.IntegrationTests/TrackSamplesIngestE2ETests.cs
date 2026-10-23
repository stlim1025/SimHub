using System.IO.Compression;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Domain.Enums;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// Agent → TelemetryHub → DB: <c>TrackSamplesChunk</c>(트랙 형상 표본 조각)를 받은 그대로 <c>track_sample_chunks</c>에 저장하고,
/// 같은 조각은 한 번만 남긴다. 실 PostgreSQL(테스트 DB <c>simcenter_test</c>)이 필요하다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class TrackSamplesIngestE2ETests : IClassFixture<ApiFactory>
{
    /// <summary>시드된 F1 25 트랙(다른 인입 E2E와 같은 값).</summary>
    private const int SeedTrackId = SessionClassifiedPayloads.SeedTrackId;

    /// <summary>조각 본문 크기 — SignalR 기본 수신 한도(32KB)를 넘겨 명시 한도(1MiB) 회귀를 잡는다.</summary>
    private const int BodyBytes = 300 * 1024;

    private readonly ApiFactory _factory;

    public TrackSamplesIngestE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Chunk_IsStoredOnce_AsReceivedGzip()
    {
        var client = _factory.CreateClient();
        var userId = await TestApi.RegisterAndLoginAsync(client);
        var (deviceId, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-TRACK-PC");
        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        var gzip = Gzip(RandomBytes(BodyBytes));

        var first = await SendAsync(connection, gzip);
        var again = await SendAsync(connection, gzip); // 다른 eventId로 같은 조각

        Assert.True(first.Acknowledged, first.RejectReason);
        Assert.True(again.Acknowledged, again.RejectReason);
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var chunk = Assert.Single(await db.TrackSampleChunks.Where(c => c.UserId == userId).ToListAsync());
        Assert.Equal(deviceId, chunk.AgentDeviceId);
        Assert.Equal(SessionType.Race, chunk.SessionType);
        Assert.Equal(gzip, chunk.Payload);
        Assert.True(chunk.IsLast);
    }

    private static Task<SubmitAck> SendAsync(HubConnection connection, byte[] gzip)
        => connection.InvokeAsync<SubmitAck>("SubmitEvent", new
        {
            eventId = Guid.NewGuid(),
            gameCode = "F1_25",
            occurredAt = DateTime.UtcNow,
            type = "TrackSamplesChunk",
            payload = new
            {
                sessionRef = "987654321",
                trackId = SeedTrackId,
                sessionType = "Race",
                trackLengthM = 5278,
                format = 1,
                sampleRateHz = 10,
                chunkIndex = 0,
                isLast = true,
                frameCount = 100,
                sampleCount = 2000,
                data = Convert.ToBase64String(gzip),
            },
        });

    private static byte[] Gzip(byte[] raw)
    {
        using var output = new MemoryStream();
        using (var stream = new GZipStream(output, CompressionLevel.Fastest))
        {
            stream.Write(raw);
        }

        return output.ToArray();
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);

    private static byte[] RandomBytes(int length)
    {
        var bytes = new byte[length];
        new Random(11).NextBytes(bytes);
        return bytes;
    }
}
