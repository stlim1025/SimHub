using System.IO.Compression;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
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

    [Fact]
    public async Task Geometry_IsPublic_AndUndecodableChunksAreSkipped()
    {
        var client = _factory.CreateClient();
        var userId = await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-GEOMETRY-PC");
        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        Assert.True((await SendAsync(connection, Gzip(RandomBytes(BodyBytes)))).Acknowledged);
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var trackId = (await db.TrackSampleChunks.FirstAsync(c => c.UserId == userId)).TrackId;

        var anonymous = _factory.CreateClient();
        var response = await anonymous.GetAsync($"/api/v1/tracks/{trackId}/geometry?gameCode=F1_25");

        // 로그인 없이도 401이 아니고, 풀 수 없는 조각(임의 바이트)만 있으면 형상이 없어 404.
        Assert.Equal(System.Net.HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task UnclassifiedSessions_AreEarlierRaceSampleSessionsWithoutClassification()
    {
        var client = _factory.CreateClient();
        var userId = await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-RESUME-PC");
        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        Assert.True((await SendAsync(connection, Gzip(RandomBytes(BodyBytes)))).Acknowledged);
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var current = await db.TrackSampleChunks.FirstAsync(c => c.UserId == userId);
        var receivedAt = current.CreatedAt;

        // 앞 조각 둘(하나는 순위표가 있다)과, 이번 세션보다 늦게 받은 조각 하나.
        TrackSampleChunk Chunk(string sessionRef, TimeSpan offset) => new()
        {
            Id = Guid.NewGuid(),
            CreatedAt = receivedAt + offset,
            AgentDeviceId = current.AgentDeviceId,
            UserId = userId,
            TrackId = current.TrackId,
            GameCode = current.GameCode,
            SessionRef = sessionRef,
            SessionType = SessionType.Race,
            Format = 5,
            Payload = [1],
        };
        db.TrackSampleChunks.AddRange(
            Chunk("111", TimeSpan.FromDays(-1)),
            Chunk("222", TimeSpan.FromDays(-2)),
            Chunk("333", TimeSpan.FromHours(1)));
        db.GameSessions.Add(new GameSession
        {
            Id = Guid.NewGuid(),
            CreatedAt = receivedAt,
            UserId = userId,
            GameCode = current.GameCode,
            SessionKey = "resume-e2e",
            SessionRef = "222",
            TrackId = current.TrackId,
            SessionType = SessionType.Race,
        });
        await db.SaveChangesAsync();
        var repository = scope.ServiceProvider.GetRequiredService<ITrackSampleChunkRepository>();

        var first = await repository.FirstReceivedAtAsync(userId, current.SessionRef);
        var candidates = await repository.ListUnclassifiedSessionsAsync(
            userId, current.TrackId, current.GameCode, SessionType.Race, receivedAt);

        Assert.Equal(receivedAt, first!.Value, TimeSpan.FromMilliseconds(1));
        Assert.Equal("111", Assert.Single(candidates).SessionRef);
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
