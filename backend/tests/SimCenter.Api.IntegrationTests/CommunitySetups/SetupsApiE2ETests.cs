using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Setups;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests.CommunitySetups;

/// <summary>
/// 커뮤니티 셋업 조회(<c>GET /setups/tracks</c>·<c>/setups</c>·<c>/setups/{id}</c>). 셋업 행은 실제 리포지토리의 묶음 교체로 심는다
/// (F1 25 Melbourne Dry 2건·Wet 1건 → Dry 1건으로 다시 교체해 빠진 행이 soft delete되는지도 본다).
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class SetupsApiE2ETests : IClassFixture<ApiFactory>
{
    private const int MelbourneGameTrackId = 0;
    private static readonly DateTime FetchedAt = new(2026, 10, 22, 3, 0, 0, DateTimeKind.Utc);

    private readonly ApiFactory _factory;

    public SetupsApiE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task SetupEndpoints_ListTracksSetupsAndDetail()
    {
        var (track, dryIds) = await SeedAsync();
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        // 트랙 메뉴: 게임의 트랙 전체(캘린더 순, 리버스 포함), 셋업 수.
        var tracks = (await client.GetFromJsonAsync<JsonElement>("/api/v1/setups/tracks?gameCode=F1_25")).EnumerateArray().ToList();
        var orders = tracks.Select(t => t.GetProperty("displayOrder").GetInt32()).ToList();
        Assert.Equal(orders.Order(), orders);
        Assert.Contains(tracks, t => t.GetProperty("name").GetString() == "Silverstone (Reverse)");
        var melbourne = tracks.Single(t => t.GetProperty("trackId").GetGuid() == track.Id);
        Assert.Equal(("Albert Park Circuit", 2, 1),
            (melbourne.GetProperty("circuitName").GetString(), melbourne.GetProperty("dryCount").GetInt32(), melbourne.GetProperty("wetCount").GetInt32()));
        Assert.All(tracks.Where(t => t.GetProperty("trackId").GetGuid() != track.Id),
            t => Assert.Equal(0, t.GetProperty("dryCount").GetInt32()));

        // 목록(조건 대소문자 무시).
        var list = await client.GetFromJsonAsync<JsonElement>($"/api/v1/setups?trackId={track.Id}&condition=dry");
        Assert.Equal(SetupConditions.Dry, list.GetProperty("condition").GetString());
        Assert.Equal(FetchedAt, list.GetProperty("fetchedAt").GetDateTime().ToUniversalTime());
        Assert.Equal("Albert Park Circuit", list.GetProperty("track").GetProperty("circuitName").GetString());
        var items = list.GetProperty("items").EnumerateArray().ToList();
        Assert.Equal([1, 2], items.Select(i => i.GetProperty("rank").GetInt32()));
        Assert.Equal(("Aston Martin", "Time Trial", 75_974),
            (items[0].GetProperty("teamName").GetString(),
                items[0].GetProperty("sessionType").GetString(), items[0].GetProperty("lapTimeMs").GetInt32()));
        Assert.All(items, i => Assert.False(i.TryGetProperty("author", out _))); // 작성자 닉네임은 내보내지 않는다
        Assert.StartsWith("https://www.f1laps.com/", items[0].GetProperty("sourceUrl").GetString());

        // 상세.
        var detail = await client.GetFromJsonAsync<JsonElement>($"/api/v1/setups/{dryIds[0]}");
        Assert.Equal((GameCodes.F1_25, "Dry", "Wheel", "2025-12-22"),
            (detail.GetProperty("gameCode").GetString(), detail.GetProperty("condition").GetString(),
                detail.GetProperty("steering").GetString(), detail.GetProperty("setOn").GetString()));
        Assert.Equal(track.Id, detail.GetProperty("track").GetProperty("trackId").GetGuid());
        Assert.False(detail.TryGetProperty("author", out _));
        var section = detail.GetProperty("sections")[0];
        Assert.Equal("Suspension Geometry", section.GetProperty("title").GetString());
        Assert.Equal(("Front Camber", "-3.50˚"),
            (section.GetProperty("items")[0].GetProperty("label").GetString(), section.GetProperty("items")[0].GetProperty("value").GetString()));
        Assert.Equal(JsonValueKind.Null, (await client.GetFromJsonAsync<JsonElement>($"/api/v1/setups/{dryIds[1]}")).GetProperty("setOn").ValueKind);

        // 다시 교체: Dry 2위가 빠지면 soft delete → 목록·개수·상세에서 사라진다.
        await ReplaceAsync(track.Id, SetupConditions.Dry, [Setup(track.Id, SetupConditions.Dry, 1, "dry-1")]);
        var after = await client.GetFromJsonAsync<JsonElement>($"/api/v1/setups?trackId={track.Id}&condition=Dry");
        Assert.Single(after.GetProperty("items").EnumerateArray());
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/api/v1/setups/{dryIds[1]}")).StatusCode);
        var deleted = await WithDbAsync(db => db.CommunitySetups.IgnoreQueryFilters().SingleAsync(s => s.Id == dryIds[1]));
        Assert.True(deleted.IsDeleted);
    }

    [Fact]
    public async Task EmptyCondition_HasNullFetchedAt_AndBadInputsAreRejected()
    {
        var track = await TrackAsync(GameCodes.F1_26, 42); // Madring — 셋업 없음
        var client = _factory.CreateClient();
        await TestApi.RegisterAndLoginAsync(client);

        var empty = await client.GetFromJsonAsync<JsonElement>($"/api/v1/setups?trackId={track.Id}&condition=Wet");
        Assert.Equal(JsonValueKind.Null, empty.GetProperty("fetchedAt").ValueKind);
        Assert.Empty(empty.GetProperty("items").EnumerateArray());
        Assert.Equal("Madring", empty.GetProperty("track").GetProperty("circuitName").GetString());

        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync($"/api/v1/setups?trackId={track.Id}&condition=Snow")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync("/api/v1/setups")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync("/api/v1/setups/tracks?gameCode=F1_99")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/api/v1/setups?trackId={Guid.NewGuid()}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/api/v1/setups/{Guid.NewGuid()}")).StatusCode);

        var f126 = (await client.GetFromJsonAsync<JsonElement>("/api/v1/setups/tracks?gameCode=F1_26")).EnumerateArray().ToList();
        Assert.Contains(f126, t => t.GetProperty("trackId").GetGuid() == track.Id);
    }

    [Fact]
    public async Task Anonymous_IsUnauthorized_AndSwaggerDescribesEndpoints()
    {
        var anonymous = _factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/api/v1/setups/tracks")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync($"/api/v1/setups/{Guid.NewGuid()}")).StatusCode);

        var swagger = await anonymous.GetFromJsonAsync<JsonElement>("/swagger/v1/swagger.json");
        var paths = swagger.GetProperty("paths");
        Assert.True(paths.TryGetProperty("/api/v1/setups/tracks", out _));
        Assert.True(paths.TryGetProperty("/api/v1/setups", out _));
        Assert.True(paths.TryGetProperty("/api/v1/setups/{id}", out _));
    }

    /// <summary>Melbourne(F1 25) Dry 2건·Wet 1건.</summary>
    private async Task<(Track Track, Guid[] DryIds)> SeedAsync()
    {
        var track = await TrackAsync(GameCodes.F1_25, MelbourneGameTrackId);
        var dry = new[]
        {
            Setup(track.Id, SetupConditions.Dry, 1, "dry-1"),
            Setup(track.Id, SetupConditions.Dry, 2, "dry-2", withDate: false),
        };
        await ReplaceAsync(track.Id, SetupConditions.Dry, dry);
        await ReplaceAsync(track.Id, SetupConditions.Wet, [Setup(track.Id, SetupConditions.Wet, 1, "wet-1")]);
        return (track, dry.Select(s => s.Id).ToArray());
    }

    private Task<Track> TrackAsync(string gameCode, int gameTrackId)
        => WithDbAsync(db => db.Tracks.AsNoTracking().SingleAsync(t => t.GameCode == gameCode && t.GameTrackId == gameTrackId));

    private async Task ReplaceAsync(Guid trackId, string condition, IReadOnlyList<CommunitySetup> setups)
    {
        using var scope = _factory.Services.CreateScope();
        var repository = scope.ServiceProvider.GetRequiredService<ICommunitySetupRepository>();
        await repository.ReplaceGroupAsync(GameCodes.F1_25, trackId, condition, setups, FetchedAt);
    }

    private async Task<T> WithDbAsync<T>(Func<AppDbContext, Task<T>> query)
    {
        using var scope = _factory.Services.CreateScope();
        return await query(scope.ServiceProvider.GetRequiredService<AppDbContext>());
    }

    private static CommunitySetup Setup(Guid trackId, string condition, int rank, string key, bool withDate = true)
        => new()
        {
            Id = Guid.CreateVersion7(),
            GameCode = GameCodes.F1_25,
            TrackId = trackId,
            Condition = condition,
            Rank = rank,
            Source = CommunitySetup.SourceF1Laps,
            SourceId = key,
            SourceUrl = $"https://www.f1laps.com/f1-25/setups/australia/{key}/",
            TeamName = "Aston Martin",
            SessionType = "Time Trial",
            LapTimeMs = 75_973 + rank,
            Steering = "Wheel",
            SetOn = withDate ? new DateOnly(2025, 12, 22) : null,
            Sections = SetupSections.Serialize(
            [
                new SetupSectionDto("Suspension Geometry", [new SetupItemDto("Front Camber", "-3.50˚")]),
            ]),
            FetchedAt = FetchedAt,
            CreatedAt = FetchedAt,
        };
}
