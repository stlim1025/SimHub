using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Api.Hubs;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// Agent → TelemetryHub → DB: <c>SessionClassified</c>(시즌·주말·세션·결과·스틴트 저장, 재분류 병합, 허브 크기 한도)와
/// <c>LapFinished</c>의 <c>session_key</c> 저장(P7, 12 §4~§6). 실 PostgreSQL(테스트 DB <c>simcenter_test</c>)이 필요하다.
/// 테스트마다 새 사용자·장치를 만들고 그 사용자의 행만 확인하므로, 같은 링크 식별자(11/22/33)를 써도 서로 섞이지 않는다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class SessionClassifiedIngestE2ETests : IClassFixture<ApiFactory>
{
    private const long SeasonLink = 11;
    private const long WeekendLink = 22;
    private const long SessionLink = 33;
    private const string LinkSessionKey = "link:11:22:33";
    private const int GridSize = 22;
    private const int StintsPerCar = 2;
    private const int MaxCars = 32;
    private const int MaxStints = 8;
    private const int MaxNameLength = 64;
    private const int MaxActualCompoundLength = 10;
    private const char NonAsciiChar = '가';

    /// <summary>SignalR 기본 수신 한도(32KB) — 검증 상한 payload가 이 값을 넘어야 명시 한도(1MiB, D-49) 회귀를 잡는다.</summary>
    private const int DefaultHubLimitBytes = 32 * 1024;

    private static readonly DateTime FirstOccurredAt = DateTime.UtcNow.AddMinutes(-30);

    private readonly ApiFactory _factory;

    public SessionClassifiedIngestE2ETests(ApiFactory factory) => _factory = factory;

    [Fact]
    public async Task SessionClassified_CareerRace_PersistsSeasonWeekendSessionAndResults()
    {
        var (userId, deviceId, deviceKey) = await RegisterWithDeviceAsync();
        await using var connection = await ConnectAsync(deviceKey);

        var ack = await SendAsync(connection, Payload(GridSize, StintsPerCar), FirstOccurredAt);

        Assert.True(ack.Acknowledged, ack.RejectReason);

        var data = await LoadAsync(userId);
        Assert.Single(data.Seasons);
        Assert.Single(data.Weekends);
        var session = Assert.Single(data.Sessions);
        Assert.Equal(LinkSessionKey, session.SessionKey);
        Assert.Equal(deviceId, session.AgentDeviceId);
        Assert.Equal(SessionKind.Race, session.SessionKind);
        Assert.NotNull(session.SeasonId);
        Assert.NotNull(session.RaceWeekendId);
        Assert.Equal(GridSize, data.ActiveResults.Count);
        Assert.Equal(GridSize * StintsPerCar, data.ActiveStints.Count);
        Assert.Single(data.ActiveResults, r => r.IsPlayer);
    }

    [Fact]
    public async Task Reclassified_SameKey_FewerCars_MergesWithoutError()
    {
        var (userId, _, deviceKey) = await RegisterWithDeviceAsync();
        await using var connection = await ConnectAsync(deviceKey);
        Assert.True((await SendAsync(connection, Payload(GridSize, StintsPerCar), FirstOccurredAt)).Acknowledged);

        // 같은 키로 20대만 담은 순위표(다른 eventId, 1분 뒤).
        var ack = await SendAsync(connection, Payload(GridSize - 2, StintsPerCar), FirstOccurredAt.AddMinutes(1));

        Assert.True(ack.Acknowledged, ack.RejectReason);
        var data = await LoadAsync(userId);
        Assert.Single(data.Sessions);
        Assert.Equal(GridSize - 2, data.ActiveResults.Count);
        var removed = data.Results.Where(r => r.IsDeleted).ToList();
        Assert.Equal(2, removed.Count);
        Assert.Equal(new[] { GridSize - 2, GridSize - 1 }, removed.Select(r => r.CarIndex).Order().ToArray());
        var removedStints = data.Stints.Where(s => removed.Any(r => r.Id == s.SessionResultId)).ToList();
        Assert.Equal(removed.Count * StintsPerCar, removedStints.Count);
        Assert.All(removedStints, s => Assert.True(s.IsDeleted)); // 지워진 차의 스틴트도 함께 soft delete.
    }

    [Fact]
    public async Task Reclassified_SameKey_NewCarAndNewStints_AreInserted()
    {
        var (userId, _, deviceKey) = await RegisterWithDeviceAsync();
        await using var connection = await ConnectAsync(deviceKey);
        Assert.True((await SendAsync(connection, Payload(GridSize, StintsPerCar), FirstOccurredAt)).Acknowledged);

        // 차 1대 추가(carIndex 22) + 모든 차의 스틴트 변경(2개 → 3개). 새 행이 UPDATE로 나가면 DbUpdateConcurrencyException이 난다.
        var ack = await SendAsync(connection, Payload(GridSize + 1, StintsPerCar + 1), FirstOccurredAt.AddMinutes(1));

        Assert.True(ack.Acknowledged, ack.RejectReason);
        var data = await LoadAsync(userId);
        Assert.Single(data.Sessions);
        Assert.Equal(GridSize + 1, data.ActiveResults.Count);
        var addedCar = Assert.Single(data.ActiveResults, r => r.CarIndex == GridSize);
        Assert.Equal(StintsPerCar + 1, data.ActiveStints.Count(s => s.SessionResultId == addedCar.Id));
        Assert.Equal((GridSize + 1) * (StintsPerCar + 1), data.ActiveStints.Count);
        Assert.Equal(GridSize * StintsPerCar, data.Stints.Count(s => s.IsDeleted)); // 바뀐 차의 옛 스틴트는 soft delete.
    }

    [Fact]
    public async Task SessionClassified_ValidationMaxPayload_PassesHub()
    {
        var (userId, _, deviceKey) = await RegisterWithDeviceAsync();
        await using var connection = await ConnectAsync(deviceKey);

        // 검증이 허용하는 최대: 32대 × 스틴트 8개, 이름 = 비ASCII 최대 길이, 컴파운드 라벨 = 최대 길이.
        // 와이어 크기가 SignalR 기본 한도(32KB)를 넘는다 — 서버가 한도를 명시하지 않으면 연결이 끊긴다.
        var namePrefix = new string(NonAsciiChar, MaxNameLength - 3); // "{prefix} {carIndex}" ≤ 64자
        var payload = SessionClassifiedPayloads.Build(
            MaxCars, MaxStints, SeasonLink, WeekendLink, SessionLink,
            namePrefix: namePrefix, actualCompound: new string('C', MaxActualCompoundLength));
        var wireBytes = TestApi.MeasureInvocationBytes(Envelope(payload, FirstOccurredAt));
        Assert.InRange(wireBytes, DefaultHubLimitBytes + 1, TelemetryHub.MaxMessageBytes);

        var ack = await SendAsync(connection, payload, FirstOccurredAt);

        Assert.True(ack.Acknowledged, ack.RejectReason);
        var data = await LoadAsync(userId);
        Assert.Equal(MaxCars, data.ActiveResults.Count);
        Assert.Equal(MaxCars * MaxStints, data.ActiveStints.Count);
    }

    [Fact]
    public async Task SameKeyDifferentTrack_StoredWithoutSeason()
    {
        var (userId, _, deviceKey) = await RegisterWithDeviceAsync();
        await using var connection = await ConnectAsync(deviceKey);
        Assert.True((await SendAsync(connection, Payload(GridSize, StintsPerCar), FirstOccurredAt)).Acknowledged);

        // 같은 링크 키인데 트랙이 다르다 → 같은 세션이 아니므로 uid 키로 따로 저장하고 시즌·주말에는 넣지 않는다.
        var otherTrack = SessionClassifiedPayloads.Build(
            GridSize, StintsPerCar, SeasonLink, WeekendLink, SessionLink, trackId: SessionClassifiedPayloads.OtherSeedTrackId);
        var ack = await SendAsync(connection, otherTrack, FirstOccurredAt.AddMinutes(1));

        Assert.True(ack.Acknowledged, ack.RejectReason);
        var data = await LoadAsync(userId);
        Assert.Equal(2, data.Sessions.Count);
        var linked = Assert.Single(data.Sessions, s => s.SessionKey == LinkSessionKey);
        var detached = Assert.Single(data.Sessions, s => s.SessionKey != LinkSessionKey);
        Assert.Equal($"uid:{SessionClassifiedPayloads.SessionRef}", detached.SessionKey);
        Assert.NotNull(linked.SeasonId);
        Assert.Null(detached.SeasonId);
        Assert.Null(detached.RaceWeekendId);
        Assert.Single(data.Seasons);
        Assert.Single(data.Weekends);
    }

    [Fact]
    public async Task NewSessionLinkAtDifferentTrackInSameWeekend_StoredWithoutSeasonOrWeekend()
    {
        var (userId, _, deviceKey) = await RegisterWithDeviceAsync();
        await using var connection = await ConnectAsync(deviceKey);
        Assert.True((await SendAsync(connection, Payload(GridSize, StintsPerCar), FirstOccurredAt)).Acknowledged);
        var before = await LoadAsync(userId);
        var season = Assert.Single(before.Seasons);
        var weekend = Assert.Single(before.Weekends);

        // 같은 (시즌, 주말) 링크인데 새 세션 링크 + 다른 트랙 → 주말에 합류시키지 않고 소속 없이 저장한다.
        var otherTrack = SessionClassifiedPayloads.Build(
            GridSize, StintsPerCar, SeasonLink, WeekendLink, SessionLink + 1, trackId: SessionClassifiedPayloads.OtherSeedTrackId);
        var ack = await SendAsync(connection, otherTrack, FirstOccurredAt.AddMinutes(1));

        Assert.True(ack.Acknowledged, ack.RejectReason);
        var data = await LoadAsync(userId);
        Assert.Equal(2, data.Sessions.Count);
        var linked = Assert.Single(data.Sessions, s => s.SessionKey == LinkSessionKey);
        var detached = Assert.Single(data.Sessions, s => s.SessionKey == $"link:{SeasonLink}:{WeekendLink}:{SessionLink + 1}");
        Assert.Equal(season.Id, linked.SeasonId);
        Assert.Equal(weekend.Id, linked.RaceWeekendId);
        Assert.Null(detached.SeasonId);
        Assert.Null(detached.RaceWeekendId);
        Assert.NotEqual(linked.TrackId, detached.TrackId);
        Assert.Equal(GridSize * 2, data.ActiveResults.Count);

        // 시즌·주말은 그대로(새로 만들지도, 범위를 넓히지도 않는다).
        var seasonAfter = Assert.Single(data.Seasons);
        var weekendAfter = Assert.Single(data.Weekends);
        Assert.Equal((season.FirstSessionAt, season.LastSessionAt), (seasonAfter.FirstSessionAt, seasonAfter.LastSessionAt));
        Assert.Equal(season.UpdatedAt, seasonAfter.UpdatedAt);
        Assert.Equal(weekend.TrackId, weekendAfter.TrackId);
        Assert.Equal(weekend.FirstSessionAt, weekendAfter.FirstSessionAt);
        Assert.Equal(weekend.UpdatedAt, weekendAfter.UpdatedAt);
    }

    [Fact]
    public async Task LapFinished_PersistsSessionKey()
    {
        var (userId, _, deviceKey) = await RegisterWithDeviceAsync();
        await using var connection = await ConnectAsync(deviceKey);

        var ack = await connection.InvokeAsync<SubmitAck>("SubmitEvent", LapFinishedEnvelope());

        Assert.True(ack.Acknowledged, ack.RejectReason);
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var lap = await db.Laps.SingleAsync(l => l.UserId == userId);
        Assert.Equal(LinkSessionKey, lap.SessionKey);
    }

    // ── 헬퍼 ──

    private static object Payload(int carCount, int stintsPerCar)
        => SessionClassifiedPayloads.Build(carCount, stintsPerCar, SeasonLink, WeekendLink, SessionLink);

    private static object Envelope(object payload, DateTime occurredAt, Guid? eventId = null) => new
    {
        eventId = eventId ?? Guid.NewGuid(),
        gameCode = "F1_25",
        occurredAt,
        type = "SessionClassified",
        payload,
    };

    private static Task<SubmitAck> SendAsync(HubConnection connection, object payload, DateTime occurredAt)
        => connection.InvokeAsync<SubmitAck>("SubmitEvent", Envelope(payload, occurredAt));

    private static object LapFinishedEnvelope() => new
    {
        eventId = Guid.NewGuid(),
        gameCode = "F1_25",
        occurredAt = FirstOccurredAt,
        type = "LapFinished",
        payload = new
        {
            sessionRef = SessionClassifiedPayloads.SessionRef,
            lapNumber = 3,
            lapTimeMs = 91234,
            sectors = new[] { new { sectorNumber = 1, sectorTimeMs = 91234 } },
            isValid = true,
            isOutOrInLap = false,
            trackId = SessionClassifiedPayloads.SeedTrackId,
            sessionType = "Race",
            gameMode = "DriverCareer",
            seasonLinkId = SeasonLink,
            weekendLinkId = WeekendLink,
            sessionLinkId = SessionLink,
        },
    };

    /// <summary>새 사용자를 가입·로그인시키고 장치를 연결한다.</summary>
    private async Task<(Guid UserId, Guid DeviceId, string DeviceKey)> RegisterWithDeviceAsync()
    {
        var client = _factory.CreateClient();
        var userId = await TestApi.RegisterAndLoginAsync(client);
        var (deviceId, deviceKey) = await TestApi.PairDeviceAsync(client, "E2E-SESSION-PC");
        return (userId, deviceId, deviceKey);
    }

    private async Task<HubConnection> ConnectAsync(string deviceKey)
    {
        var connection = TestApi.BuildTelemetryConnection(_factory, deviceKey);
        await connection.StartAsync();
        return connection;
    }

    /// <summary>사용자의 시즌·주말·세션·결과·스틴트를 soft delete된 행까지 모두 읽는다.</summary>
    private async Task<UserData> LoadAsync(Guid userId)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var seasons = await db.Seasons.IgnoreQueryFilters().Where(s => s.UserId == userId).ToListAsync();
        var seasonIds = seasons.Select(s => s.Id).ToList();
        var weekends = await db.RaceWeekends.IgnoreQueryFilters().Where(w => seasonIds.Contains(w.SeasonId)).ToListAsync();
        var sessions = await db.GameSessions.IgnoreQueryFilters().Where(s => s.UserId == userId).ToListAsync();
        var sessionIds = sessions.Select(s => s.Id).ToList();
        var results = await db.SessionResults.IgnoreQueryFilters().Where(r => sessionIds.Contains(r.GameSessionId)).ToListAsync();
        var resultIds = results.Select(r => r.Id).ToList();
        var stints = await db.SessionResultTyreStints.IgnoreQueryFilters().Where(t => resultIds.Contains(t.SessionResultId)).ToListAsync();

        return new UserData(seasons, weekends, sessions, results, stints);
    }

    private sealed record UserData(
        List<Season> Seasons,
        List<RaceWeekend> Weekends,
        List<GameSession> Sessions,
        List<SessionResult> Results,
        List<SessionResultTyreStint> Stints)
    {
        public List<SessionResult> ActiveResults => Results.Where(r => !r.IsDeleted).ToList();

        public List<SessionResultTyreStint> ActiveStints => Stints.Where(s => !s.IsDeleted).ToList();
    }

    private sealed record SubmitAck(bool Acknowledged, string? RejectReason);
}
