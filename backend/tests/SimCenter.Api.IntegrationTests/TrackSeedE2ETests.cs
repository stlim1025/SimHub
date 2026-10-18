using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Domain.Constants;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 트랙 시드가 Agent가 보낼 수 있는 F1 25 트랙 ID를 모두 덮는지 확인한다.
/// 매핑이 없는 트랙의 LapFinished·SessionClassified는 Reject되어 Agent Outbox에서 지워지므로(영구 손실) 시드 누락은 데이터 손실이다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class TrackSeedE2ETests : IClassFixture<ApiFactory>
{
    /// <summary>
    /// Agent가 보낼 수 있는 트랙 ID 계약. Agent 테스트(TrackIdContractTests)가 이 파일이 F1Game.UDP의 Track enum과
    /// 같은지 확인하므로, 라이브러리를 올려 새 트랙이 생기면 그쪽이 먼저 실패한다.
    /// </summary>
    private const string ContractRelativePath = "shared/telemetry/f1_25_track_ids.json";

    private static readonly DateTime OccurredAt = new(2026, 10, 18, 9, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public TrackSeedE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Seed_CoversEveryF1GameUdpTrackId()
    {
        _ = _factory.CreateClient(); // 호스트 시작 = 마이그레이션·시드 실행

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var seeded = await db.Tracks
            .Where(t => t.GameCode == GameCodes.F1_25)
            .Select(t => t.GameTrackId)
            .ToListAsync();

        var contract = ReadContractTrackIds();
        Assert.NotEmpty(contract);

        var missing = contract.Except(seeded).ToList();
        Assert.True(missing.Count == 0, $"시드에 없는 F1 25 트랙 ID: {string.Join(", ", missing)}");
    }

    [Theory]
    [InlineData(39)] // Silverstone Reverse
    [InlineData(40)] // Austria Reverse
    [InlineData(41)] // Zandvoort Reverse
    [InlineData(42)] // Madrid (2026 시즌팩)
    public async Task LapFinished_OnReverseOrSeasonPackTrack_IsAcked(int gameTrackId)
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);
        var (_, deviceKey) = await TestApi.PairDeviceAsync(client, "TRACK-PC");

        await using var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", LapFinishedEnvelope(gameTrackId));

        Assert.True(ack.Acknowledged, ack.RejectReason);
    }

    private static object LapFinishedEnvelope(int gameTrackId) => new
    {
        eventId = Guid.NewGuid(),
        gameCode = GameCodes.F1_25,
        occurredAt = OccurredAt,
        type = "LapFinished",
        payload = new
        {
            sessionRef = "0xTRACKSEED",
            lapNumber = 2,
            lapTimeMs = 90123,
            sectors = new[]
            {
                new { sectorNumber = 1, sectorTimeMs = 30000 },
                new { sectorNumber = 2, sectorTimeMs = 30000 },
                new { sectorNumber = 3, sectorTimeMs = 30123 },
            },
            isValid = true,
            isOutOrInLap = false,
            trackId = gameTrackId,
            sessionType = "TimeTrial",
        },
    };

    private static IReadOnlyList<int> ReadContractTrackIds()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(FindContractPath()));
        return document.RootElement.GetProperty("trackIds").EnumerateArray().Select(id => id.GetInt32()).ToList();
    }

    /// <summary>테스트 실행 폴더(bin/…)에서 위로 올라가며 저장소의 계약 파일을 찾는다.</summary>
    private static string FindContractPath()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, ContractRelativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new FileNotFoundException($"저장소에서 {ContractRelativePath}를 찾지 못했습니다.");
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
