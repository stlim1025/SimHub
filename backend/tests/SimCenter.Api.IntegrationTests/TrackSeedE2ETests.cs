using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;
using SimCenter.Infrastructure.Persistence;
using SimCenter.Infrastructure.Persistence.Seed;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 트랙 시드가 Agent가 보낼 수 있는 F1 25 트랙 ID를 모두 덮는지 확인한다.
/// 매핑이 없는 트랙의 LapFinished·SessionClassified는 Reject되어 Agent Outbox에서 지워지므로(영구 손실) 시드 누락은 데이터 손실이다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class TrackSeedE2ETests : IClassFixture<ApiFactory>
{
    /// <summary>
    /// Agent가 보낼 수 있는 트랙 ID 계약. Agent 테스트(TrackIdContractTests)가 F1Game.UDP의 Track enum 값이 모두
    /// 이 파일에 있는지 확인하므로, 라이브러리를 올려 새 트랙이 생기면 그쪽이 먼저 실패한다(계약에 더 있는 것은 허용, D-41).
    /// </summary>
    private const string ContractRelativePath = "shared/telemetry/f1_25_track_ids.json";

    private static readonly DateTime OccurredAt = new(2026, 10, 18, 9, 0, 0, DateTimeKind.Utc);

    /// <summary>
    /// 15 §4.1의 표(시험 기준값): 표시 순서대로 (게임 트랙 ID, 국가). F1 25 캘린더 24개 → 리버스 3개 → Madrid → 옛 트랙 3개.
    /// </summary>
    private static readonly (int GameTrackId, string CountryCode)[] ExpectedCalendar =
    [
        (0, "AU"), (2, "CN"), (13, "JP"), (3, "BH"), (29, "SA"), (30, "US"), (27, "IT"), (5, "MC"),
        (4, "ES"), (6, "CA"), (17, "AT"), (7, "GB"), (10, "BE"), (9, "HU"), (26, "NL"), (11, "IT"),
        (20, "AZ"), (12, "SG"), (15, "US"), (19, "MX"), (16, "BR"), (31, "US"), (32, "QA"), (14, "AE"),
        (41, "NL"), (40, "AT"), (39, "GB"), (42, "ES"), (1, "FR"), (8, "DE"), (28, "PT"),
    ];

    private readonly ApiFactory _factory;

    public TrackSeedE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Seed_SetsCountryAndCalendarOrder_ForAll31Tracks()
    {
        _ = _factory.CreateClient(); // 호스트 시작 = 마이그레이션·시드 실행

        var seeded = await ReadF1TracksAsync();

        AssertMatchesCalendar(seeded);
    }

    [Fact]
    public async Task Seed_FixesExistingRowsCountryAndOrder_ButKeepsNames()
    {
        _ = _factory.CreateClient();
        const int JeddahId = 29;
        const string CustomName = "Jeddah (이름 유지 확인)";

        try
        {
            // 마이그레이션 직후의 기존 행(국가 null·순서 0)과 틀린 값을 흉내 낸다. 이름도 바꿔 시드가 덮지 않는지 본다.
            using (var scope = _factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                await db.Tracks.Where(t => t.GameCode == GameCodes.F1_25)
                    .ExecuteUpdateAsync(s => s.SetProperty(t => t.CountryCode, (string?)null).SetProperty(t => t.DisplayOrder, 0));
                await db.Tracks.Where(t => t.GameCode == GameCodes.F1_25 && t.GameTrackId == JeddahId)
                    .ExecuteUpdateAsync(s => s.SetProperty(t => t.CountryCode, "XX").SetProperty(t => t.DisplayOrder, 999).SetProperty(t => t.Name, CustomName));
            }

            await RunSeederAsync();

            var seeded = await ReadF1TracksAsync();
            AssertMatchesCalendar(seeded);
            Assert.Equal(CustomName, seeded.Single(t => t.GameTrackId == JeddahId).Name);
        }
        finally
        {
            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await db.Tracks.Where(t => t.GameCode == GameCodes.F1_25 && t.GameTrackId == JeddahId)
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.Name, "Jeddah"));
            await RunSeederAsync();
        }
    }

    [Fact]
    public async Task GetTracks_ReturnsCalendarOrder_WithCountryCodes()
    {
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var body = await client.GetFromJsonAsync<JsonElement>("/api/v1/tracks");

        var items = body.GetProperty("items").EnumerateArray()
            .Where(t => t.GetProperty("gameCode").GetString() == GameCodes.F1_25)
            .ToList();
        var seeded = (await ReadF1TracksAsync()).ToDictionary(t => t.Name, t => t.GameTrackId);

        Assert.Equal(ExpectedCalendar.Select(e => e.GameTrackId), items.Select(t => seeded[t.GetProperty("name").GetString()!]));
        Assert.Equal(ExpectedCalendar.Select(e => e.CountryCode), items.Select(t => t.GetProperty("countryCode").GetString()));
        Assert.Equal(Enumerable.Range(1, ExpectedCalendar.Length), items.Select(t => t.GetProperty("displayOrder").GetInt32()));
    }

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

    private async Task<List<Track>> ReadF1TracksAsync()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return await db.Tracks.AsNoTracking().Where(t => t.GameCode == GameCodes.F1_25).ToListAsync();
    }

    private async Task RunSeederAsync()
    {
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<DbSeeder>().SeedAsync();
    }

    /// <summary>시드된 F1 25 트랙이 정확히 표의 31개이고, 각자 표의 국가·순서(1부터)를 가졌는지.</summary>
    private static void AssertMatchesCalendar(IReadOnlyList<Track> seeded)
    {
        Assert.Equal(ExpectedCalendar.Length, seeded.Count);

        var byGameId = seeded.ToDictionary(t => t.GameTrackId);
        for (var i = 0; i < ExpectedCalendar.Length; i++)
        {
            var (gameTrackId, countryCode) = ExpectedCalendar[i];
            var track = byGameId[gameTrackId];
            Assert.True(countryCode == track.CountryCode, $"트랙 {gameTrackId}: 국가 {track.CountryCode} (기대 {countryCode})");
            Assert.True(i + 1 == track.DisplayOrder, $"트랙 {gameTrackId}: 순서 {track.DisplayOrder} (기대 {i + 1})");
        }
    }

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
