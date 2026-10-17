using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Ingest;
using SimCenter.Application.Telemetry;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Seasons;

public class SessionClassificationIngestorTests
{
    private const string GameCode = "F1_25";
    private const int GameTrackId = 10;
    private const int OtherGameTrackId = 11;
    private const string SessionRef = "1844674407370955161";
    private const string LinkKey = "link:11:22:33";

    private static readonly DateTime Now = new(2026, 10, 17, 12, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime OccurredAt = Now.AddSeconds(-5);
    private static readonly JsonSerializerOptions WireOptions = new(JsonSerializerDefaults.Web);

    private readonly FakeSeasons _seasons = new();
    private readonly FakeSessions _sessions = new();
    private readonly FakeTracks _tracks = new();

    private readonly Guid _ownerId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private readonly Guid _deviceId = Guid.Parse("00000000-0000-0000-0000-0000000000e1");
    private readonly Guid _trackId = Guid.Parse("00000000-0000-0000-0000-0000000000c1");
    private readonly Guid _otherTrackId = Guid.Parse("00000000-0000-0000-0000-0000000000c2");

    private readonly AgentDevice _device;
    private readonly SessionClassificationIngestor _sut;

    public SessionClassificationIngestorTests()
    {
        _device = new AgentDevice { Id = _deviceId, UserId = _ownerId, Name = "SIM-PC", ApiKeyHash = "h:key" };
        _tracks.Items.Add(new Track { Id = _trackId, GameCode = GameCode, GameTrackId = GameTrackId, Name = "Silverstone" });
        _tracks.Items.Add(new Track { Id = _otherTrackId, GameCode = GameCode, GameTrackId = OtherGameTrackId, Name = "Spa" });

        _sut = new SessionClassificationIngestor(
            _seasons, _sessions, _tracks, new SequentialIdGenerator(), NullLogger<SessionClassificationIngestor>.Instance);
    }

    // ---- 입력 구성 ----

    private static ClassifiedResultDto PlayerCar() => new(
        CarIndex: 0, IsPlayer: true, Position: 1, GridPosition: 2, NumLaps: 29, Points: 25,
        NumPitStops: 1, NumPenalties: 0, ResultStatus: "Finished",
        BestLapTimeMs: 81234, TotalRaceTimeMs: 2_493_120, PenaltiesTimeMs: 0,
        DriverName: "S. LIM", GameDriverId: null, TeamId: 2, RaceNumber: 26, IsAiControlled: false,
        TyreStints: new List<TyreStintDto>
        {
            new(EndLap: 14, VisualCompound: "Medium", ActualCompound: "C3"),
            new(EndLap: 29, VisualCompound: "Hard", ActualCompound: "C2"),
        });

    private static ClassifiedResultDto AiCar(int carIndex = 1, int? gameDriverId = 9, string? name = "Driver Nine") => new(
        CarIndex: carIndex, IsPlayer: false, Position: carIndex + 1, GridPosition: carIndex + 1, NumLaps: 29, Points: 18,
        NumPitStops: 2, NumPenalties: 1, ResultStatus: "Finished",
        BestLapTimeMs: 81900, TotalRaceTimeMs: 2_500_000, PenaltiesTimeMs: 5_000,
        DriverName: name, GameDriverId: gameDriverId, TeamId: 3, RaceNumber: 9, IsAiControlled: true,
        TyreStints: new List<TyreStintDto> { new(EndLap: 29, VisualCompound: "Hard", ActualCompound: "C2") });

    private static SessionClassifiedPayloadDto BasePayload() => new(
        SessionRef: SessionRef,
        TrackId: GameTrackId,
        SessionType: "Race",
        SessionKind: "Race",
        GameMode: "DriverCareer",
        SeasonLinkId: 11,
        WeekendLinkId: 22,
        SessionLinkId: 33,
        TotalLaps: 29,
        AiDifficulty: 85,
        IsNetworkGame: false,
        Results: new List<ClassifiedResultDto> { PlayerCar(), AiCar() });

    private static TelemetryEnvelopeDto Envelope(SessionClassifiedPayloadDto payload, DateTime? occurredAt = null)
        => RawEnvelope(JsonSerializer.SerializeToElement(payload, WireOptions), occurredAt);

    private static TelemetryEnvelopeDto RawEnvelope(JsonElement payload, DateTime? occurredAt = null)
        => new(Guid.NewGuid(), GameCode, occurredAt ?? OccurredAt, "SessionClassified", payload);

    private Task<ClassificationOutcome> Apply(TelemetryEnvelopeDto envelope, DateTime? now = null)
        => _sut.ApplyAsync(envelope, _device, now ?? Now, CancellationToken.None);

    private async Task<ClassificationOutcome.Stored> ApplyStored(TelemetryEnvelopeDto envelope, DateTime? now = null)
        => Assert.IsType<ClassificationOutcome.Stored>(await Apply(envelope, now));

    private void AssertNothingAdded()
    {
        Assert.Equal(0, _seasons.SeasonAddCalls);
        Assert.Equal(0, _seasons.WeekendAddCalls);
        Assert.Equal(0, _sessions.AddCalls);
    }

    // ---- 생성 ----

    [Fact]
    public async Task Apply_CareerRace_CreatesSeasonWeekendSessionResultsAndStints()
    {
        var outcome = await Apply(Envelope(BasePayload()));

        Assert.Equal(new ClassificationOutcome.Stored(LinkKey, IsNew: true), outcome);

        var season = Assert.Single(_seasons.Seasons);
        Assert.NotEqual(Guid.Empty, season.Id);
        Assert.Equal(_ownerId, season.UserId);
        Assert.Equal(GameCode, season.GameCode);
        Assert.Equal(11, season.SeasonLinkId);
        Assert.Equal(GameMode.DriverCareer, season.GameMode);
        Assert.Equal(OccurredAt, season.FirstSessionAt);
        Assert.Equal(OccurredAt, season.LastSessionAt);
        Assert.Equal(Now, season.CreatedAt);

        var weekend = Assert.Single(_seasons.Weekends);
        Assert.NotEqual(Guid.Empty, weekend.Id);
        Assert.Equal(season.Id, weekend.SeasonId);
        Assert.Equal(22, weekend.WeekendLinkId);
        Assert.Equal(_trackId, weekend.TrackId);
        Assert.Equal(OccurredAt, weekend.FirstSessionAt);

        var session = Assert.Single(_sessions.Items);
        Assert.NotEqual(Guid.Empty, session.Id);
        Assert.Equal(_ownerId, session.UserId);
        Assert.Equal(_deviceId, session.AgentDeviceId);
        Assert.Equal(season.Id, session.SeasonId);
        Assert.Equal(weekend.Id, session.RaceWeekendId);
        Assert.Equal(GameCode, session.GameCode);
        Assert.Equal(LinkKey, session.SessionKey);
        Assert.Equal((11, 22, 33), (session.SeasonLinkId, session.WeekendLinkId, session.SessionLinkId));
        Assert.Equal(SessionRef, session.SessionRef);
        Assert.Equal(_trackId, session.TrackId);
        Assert.Equal(SessionType.Race, session.SessionType);
        Assert.Equal(SessionKind.Race, session.SessionKind);
        Assert.Equal(GameMode.DriverCareer, session.GameMode);
        Assert.Equal((29, 85, false), (session.TotalLaps, session.AiDifficulty, session.IsNetworkGame));
        Assert.Equal(OccurredAt, session.ClassifiedAt);
        Assert.Equal(Now, session.CreatedAt);
        Assert.Null(session.UpdatedAt);

        AssertCreatedResults(session);
    }

    private static void AssertCreatedResults(GameSession session)
    {
        Assert.Equal(2, session.Results.Count);
        var player = session.Results.Single(r => r.CarIndex == 0);
        Assert.NotEqual(Guid.Empty, player.Id);
        Assert.Equal(session.Id, player.GameSessionId);
        Assert.Equal("player", player.DriverKey);
        Assert.Equal("S. LIM", player.DriverName);
        Assert.True(player.IsPlayer);
        Assert.False(player.IsAiControlled);
        Assert.Null(player.GameDriverId);
        Assert.Equal((1, 2, 29, 25), (player.Position, player.GridPosition, player.NumLaps, player.Points));
        Assert.Equal((1, 0), (player.NumPitStops, player.NumPenalties));
        Assert.Equal(ResultStatus.Finished, player.ResultStatus);
        Assert.Equal((81234, 2_493_120, 0), (player.BestLapTimeMs, player.TotalRaceTimeMs, player.PenaltiesTimeMs));
        Assert.Equal((2, 26), (player.TeamId, player.RaceNumber));

        var stints = player.TyreStints.OrderBy(s => s.StintNumber).ToList();
        Assert.Equal(new[] { 1, 2 }, stints.Select(s => s.StintNumber));
        Assert.Equal(new[] { TyreCompound.Medium, TyreCompound.Hard }, stints.Select(s => s.VisualCompound));
        Assert.Equal(new[] { 14, 29 }, stints.Select(s => s.EndLap));
        Assert.Equal(new[] { "C3", "C2" }, stints.Select(s => s.ActualCompound));
        Assert.All(stints, s =>
        {
            Assert.NotEqual(Guid.Empty, s.Id);
            Assert.Equal(player.Id, s.SessionResultId);
        });

        var ai = session.Results.Single(r => r.CarIndex == 1);
        Assert.Equal("driver:9", ai.DriverKey);
        Assert.Equal(9, ai.GameDriverId);
        Assert.True(ai.IsAiControlled);
        Assert.Equal(5_000, ai.PenaltiesTimeMs);
        Assert.Single(ai.TyreStints);
    }

    [Fact]
    public async Task Apply_NonSeasonMode_CreatesSessionOnly()
    {
        var outcome = await Apply(Envelope(BasePayload() with { GameMode = "Online" }));

        Assert.Equal(new ClassificationOutcome.Stored($"uid:{SessionRef}", IsNew: true), outcome);
        var session = Assert.Single(_sessions.Items);
        Assert.Equal($"uid:{SessionRef}", session.SessionKey);
        Assert.Equal(GameMode.Online, session.GameMode);
        Assert.Null(session.SeasonId);
        Assert.Null(session.RaceWeekendId);
        Assert.Equal(0, _seasons.SeasonAddCalls);
        Assert.Equal(0, _seasons.WeekendAddCalls);
        Assert.Empty(_seasons.Seasons);
        Assert.Empty(_seasons.Weekends);
    }

    [Fact]
    public async Task Apply_SeasonModeWithoutSessionLink_UsesUidKeyButJoinsSeason()
    {
        var outcome = await Apply(Envelope(BasePayload() with { SessionLinkId = 0 }));

        Assert.Equal(new ClassificationOutcome.Stored($"uid:{SessionRef}", IsNew: true), outcome);
        var session = Assert.Single(_sessions.Items);
        Assert.NotNull(session.SeasonId);
        Assert.NotNull(session.RaceWeekendId);
        Assert.Single(_seasons.Seasons);
    }

    [Fact]
    public async Task Apply_ExistingSeasonAndWeekend_Reuses_AndTouches()
    {
        var firstAt = Now.AddMinutes(-30);
        var secondAt = Now.AddMinutes(-20);
        var thirdAt = Now.AddMinutes(-40);
        await ApplyStored(Envelope(BasePayload(), firstAt));
        var season = Assert.Single(_seasons.Seasons);
        var firstWeekend = Assert.Single(_seasons.Weekends);
        var laterNow = Now.AddHours(1);

        // 같은 시즌의 두 번째 주말.
        var secondWeekendOutcome = await ApplyStored(
            Envelope(BasePayload() with { SessionRef = "1002", WeekendLinkId = 23, SessionLinkId = 34 }, secondAt), laterNow);

        Assert.Equal("link:11:23:34", secondWeekendOutcome.SessionKey);
        Assert.Equal(1, _seasons.SeasonAddCalls);
        Assert.Equal(2, _seasons.WeekendAddCalls);
        Assert.Same(season, Assert.Single(_seasons.Seasons));
        Assert.Equal(firstAt, season.FirstSessionAt);
        Assert.Equal(secondAt, season.LastSessionAt);
        Assert.Equal(laterNow, season.UpdatedAt);
        var secondWeekend = _seasons.Weekends.Single(w => w.WeekendLinkId == 23);
        Assert.Equal(season.Id, secondWeekend.SeasonId);
        Assert.Equal(secondAt, secondWeekend.FirstSessionAt);
        Assert.Equal(season.Id, _sessions.Items.Single(s => s.SessionLinkId == 34).SeasonId);

        // 같은 주말의 다른 세션(더 이른 시각) — 주말·시즌을 새로 만들지 않고 첫 시각만 앞당긴다.
        await ApplyStored(Envelope(BasePayload() with { SessionRef = "1003", SessionLinkId = 35, SessionKind = "Qualifying1", SessionType = "Qualifying" }, thirdAt), laterNow);

        Assert.Equal(1, _seasons.SeasonAddCalls);
        Assert.Equal(2, _seasons.WeekendAddCalls);
        Assert.Equal(thirdAt, firstWeekend.FirstSessionAt);
        Assert.Equal(thirdAt, season.FirstSessionAt);
        Assert.Equal(secondAt, season.LastSessionAt);
    }

    // ---- 재분류(같은 키) ----

    [Fact]
    public async Task Apply_SameKeyNewer_MergesResults()
    {
        await ApplyStored(Envelope(BasePayload()));
        var season = Assert.Single(_seasons.Seasons);
        var session = Assert.Single(_sessions.Items);
        var playerRow = session.Results.Single(r => r.CarIndex == 0);
        var oldPlayerStints = playerRow.TyreStints.ToList();
        var droppedRow = session.Results.Single(r => r.CarIndex == 1);
        var otherDevice = new AgentDevice { Id = Guid.Parse("00000000-0000-0000-0000-0000000000e2"), UserId = _ownerId, Name = "LAPTOP", ApiKeyHash = "h:key2" };
        var laterNow = Now.AddHours(1);
        var classifiedAt = Now.AddMinutes(30);
        var reclassified = BasePayload() with
        {
            SessionRef = "5005",
            TotalLaps = 30,
            Results = new List<ClassifiedResultDto>
            {
                PlayerCar() with { Position = 2, Points = 18, TyreStints = new List<TyreStintDto> { new(30, "Soft", "C5") } },
                AiCar(carIndex: 2, gameDriverId: 4, name: "Driver Four"),
            },
        };

        var outcome = await _sut.ApplyAsync(Envelope(reclassified, classifiedAt), otherDevice, laterNow, CancellationToken.None);

        Assert.Equal(new ClassificationOutcome.Stored(LinkKey, IsNew: false), outcome);
        Assert.Equal(1, _sessions.AddCalls);
        Assert.Same(session, Assert.Single(_sessions.Items));
        Assert.Equal("5005", session.SessionRef);
        Assert.Equal(otherDevice.Id, session.AgentDeviceId);
        Assert.Equal(classifiedAt, session.ClassifiedAt);
        Assert.Equal(30, session.TotalLaps);
        Assert.Equal(laterNow, session.UpdatedAt);
        Assert.Equal(Now, session.CreatedAt);

        // Task 1 병합 규칙: 같은 carIndex는 제자리 갱신, 없어진 carIndex는 soft delete, 새 carIndex는 추가.
        Assert.Equal(3, session.Results.Count);
        Assert.Same(playerRow, session.Results.Single(r => r.CarIndex == 0));
        Assert.Equal(2, playerRow.Position);
        Assert.False(playerRow.IsDeleted);
        Assert.True(droppedRow.IsDeleted);
        var added = session.Results.Single(r => r.CarIndex == 2);
        Assert.False(added.IsDeleted);
        Assert.Equal("driver:4", added.DriverKey);
        Assert.Equal(session.Id, added.GameSessionId);
        Assert.All(oldPlayerStints, s => Assert.True(s.IsDeleted));
        var activeStint = Assert.Single(playerRow.TyreStints, s => !s.IsDeleted);
        Assert.Equal(TyreCompound.Soft, activeStint.VisualCompound);
        Assert.Equal(1, activeStint.StintNumber);

        // 시즌 범위는 새 시각까지 넓어진다.
        Assert.Equal(classifiedAt, season.LastSessionAt);
        Assert.Equal(OccurredAt, season.FirstSessionAt);
    }

    [Fact]
    public async Task Apply_SameKeySameTimestamp_Merges()
    {
        await ApplyStored(Envelope(BasePayload()));

        var outcome = await Apply(Envelope(BasePayload() with { TotalLaps = 31 }));

        Assert.Equal(new ClassificationOutcome.Stored(LinkKey, IsNew: false), outcome);
        Assert.Equal(31, Assert.Single(_sessions.Items).TotalLaps);
    }

    [Fact]
    public async Task Apply_SameKeyOlder_IsIgnored_AndTouchesNothing()
    {
        await ApplyStored(Envelope(BasePayload()));
        var season = Assert.Single(_seasons.Seasons);
        var weekend = Assert.Single(_seasons.Weekends);
        var session = Assert.Single(_sessions.Items);

        var outcome = await Apply(Envelope(BasePayload() with { SessionRef = "old", TotalLaps = 5 }, OccurredAt.AddMinutes(-10)), Now.AddHours(1));

        Assert.IsType<ClassificationOutcome.Ignored>(outcome);
        Assert.Equal((1, 1, 1), (_seasons.SeasonAddCalls, _seasons.WeekendAddCalls, _sessions.AddCalls));
        Assert.Equal((OccurredAt, OccurredAt), (season.FirstSessionAt, season.LastSessionAt));
        Assert.Null(season.UpdatedAt);
        Assert.Equal(OccurredAt, weekend.FirstSessionAt);
        Assert.Null(weekend.UpdatedAt);
        Assert.Equal((SessionRef, 29, OccurredAt), (session.SessionRef, session.TotalLaps, session.ClassifiedAt));
        Assert.Null(session.UpdatedAt);
        Assert.All(session.Results, r => Assert.Null(r.UpdatedAt));
    }

    [Theory]
    [InlineData("track")]
    [InlineData("kind")]
    public async Task Apply_SameKeyDifferentTrackOrKind_StoresUnderUidKey_WithoutSeason(string mismatch)
    {
        await ApplyStored(Envelope(BasePayload()));
        var season = Assert.Single(_seasons.Seasons);
        var weekend = Assert.Single(_seasons.Weekends);
        var existing = Assert.Single(_sessions.Items);
        var conflicting = mismatch == "track"
            ? BasePayload() with { SessionRef = "777", TrackId = OtherGameTrackId }
            : BasePayload() with { SessionRef = "777", SessionKind = "Race2" };
        var laterAt = Now.AddMinutes(1);

        var outcome = await Apply(Envelope(conflicting, laterAt), Now.AddHours(1));

        Assert.Equal(new ClassificationOutcome.Stored("uid:777", IsNew: true), outcome);
        Assert.Equal(2, _sessions.Items.Count);
        var stored = _sessions.Items.Single(s => s.SessionKey == "uid:777");
        Assert.Null(stored.SeasonId);
        Assert.Null(stored.RaceWeekendId);
        Assert.Equal(laterAt, stored.ClassifiedAt);

        // 시즌·주말·기존 세션은 그대로.
        Assert.Equal((1, 1), (_seasons.SeasonAddCalls, _seasons.WeekendAddCalls));
        Assert.Equal((OccurredAt, OccurredAt), (season.FirstSessionAt, season.LastSessionAt));
        Assert.Null(season.UpdatedAt);
        Assert.Equal(OccurredAt, weekend.FirstSessionAt);
        Assert.Equal(_trackId, weekend.TrackId);
        Assert.Equal((SessionRef, OccurredAt, LinkKey), (existing.SessionRef, existing.ClassifiedAt, existing.SessionKey));
        Assert.Null(existing.UpdatedAt);
        Assert.Equal(2, existing.Results.Count(r => !r.IsDeleted));
    }

    [Fact]
    public async Task Apply_NewSessionLinkAtDifferentTrackInExistingWeekend_StoresWithoutMembership_AndTouchesNothing()
    {
        // 같은 (시즌, 주말)인데 트랙이 다른 새 세션 링크 — 주말에 합류시키면 Standings가 한 레이스를 조용히 버린다.
        await ApplyStored(Envelope(BasePayload()));
        var season = Assert.Single(_seasons.Seasons);
        var weekend = Assert.Single(_seasons.Weekends);
        var firstSession = Assert.Single(_sessions.Items);
        var otherTrackRace = BasePayload() with { SessionRef = "888", SessionLinkId = 34, TrackId = OtherGameTrackId };
        var laterAt = Now.AddMinutes(1);

        var outcome = await Apply(Envelope(otherTrackRace, laterAt), Now.AddHours(1));

        Assert.Equal(new ClassificationOutcome.Stored("link:11:22:34", IsNew: true), outcome);
        Assert.Equal(2, _sessions.Items.Count);
        var stored = _sessions.Items.Single(s => s.SessionLinkId == 34);
        Assert.Equal(_otherTrackId, stored.TrackId);
        Assert.Null(stored.SeasonId);
        Assert.Null(stored.RaceWeekendId);
        Assert.Equal(laterAt, stored.ClassifiedAt);
        Assert.Equal(2, stored.Results.Count);

        // 시즌·주말·기존 세션은 그대로(Touch도 하지 않는다).
        Assert.Equal((1, 1), (_seasons.SeasonAddCalls, _seasons.WeekendAddCalls));
        Assert.Equal((OccurredAt, OccurredAt), (season.FirstSessionAt, season.LastSessionAt));
        Assert.Null(season.UpdatedAt);
        Assert.Equal(OccurredAt, weekend.FirstSessionAt);
        Assert.Null(weekend.UpdatedAt);
        Assert.Equal(_trackId, weekend.TrackId);
        Assert.Equal((season.Id, weekend.Id), (firstSession.SeasonId, firstSession.RaceWeekendId));
        Assert.Null(firstSession.UpdatedAt);

        // 같은 입력을 다시 보내도 같은 세션(link 키)에 병합되고 멤버십은 여전히 없다.
        var resend = await Apply(Envelope(otherTrackRace, laterAt.AddMinutes(1)), Now.AddHours(2));
        Assert.Equal(new ClassificationOutcome.Stored("link:11:22:34", IsNew: false), resend);
        Assert.Equal(2, _sessions.Items.Count);
        Assert.Null(stored.SeasonId);
        Assert.Null(stored.RaceWeekendId);
        Assert.Null(season.UpdatedAt);
    }

    [Fact]
    public async Task Apply_ConflictingUidKeyAlsoMismatched_IsIgnored()
    {
        // uid 키가 이미 다른 트랙의 세션이면 더 내려갈 대체 키가 없다 — 덮어쓰지 않고 무시한다.
        var online = BasePayload() with { GameMode = "Online" };
        await ApplyStored(Envelope(online));
        var existing = Assert.Single(_sessions.Items);

        var outcome = await Apply(Envelope(online with { TrackId = OtherGameTrackId }, Now.AddMinutes(1)));

        Assert.IsType<ClassificationOutcome.Ignored>(outcome);
        Assert.Equal(1, _sessions.AddCalls);
        Assert.Equal(_trackId, existing.TrackId);
        Assert.Equal(OccurredAt, existing.ClassifiedAt);
        Assert.Null(existing.UpdatedAt);
    }

    // ---- 정규화 · 대체값 ----

    [Fact]
    public async Task Apply_BlankDriverName_IsStoredAsNull()
    {
        var payload = BasePayload() with { Results = new List<ClassifiedResultDto> { PlayerCar(), AiCar(carIndex: 1, gameDriverId: null, name: "   ") } };

        await ApplyStored(Envelope(payload));

        var row = Assert.Single(_sessions.Items).Results.Single(r => r.CarIndex == 1);
        Assert.Null(row.DriverName);
        Assert.Equal($"car:{SessionRef}:1", row.DriverKey);
    }

    [Fact]
    public async Task Apply_PaddedDriverName_IsTrimmed()
    {
        var payload = BasePayload() with { Results = new List<ClassifiedResultDto> { PlayerCar(), AiCar(carIndex: 1, gameDriverId: null, name: "  Max Power ") } };

        await ApplyStored(Envelope(payload));

        var row = Assert.Single(_sessions.Items).Results.Single(r => r.CarIndex == 1);
        Assert.Equal("Max Power", row.DriverName);
        Assert.Equal("name:MAX POWER#9", row.DriverKey);
    }

    [Fact]
    public async Task Apply_NulPaddedDriverName_IsCutAtNulAndKeyedByCleanName()
    {
        var payload = BasePayload() with
        {
            Results = new List<ClassifiedResultDto> { PlayerCar(), AiCar(carIndex: 1, gameDriverId: null, name: "ABC\0\0") },
        };

        await ApplyStored(Envelope(payload));

        var row = Assert.Single(_sessions.Items).Results.Single(r => r.CarIndex == 1);
        Assert.Equal("ABC", row.DriverName);
        Assert.Equal("name:ABC#9", row.DriverKey);
    }

    [Theory]
    [InlineData("\0\0\0")]
    [InlineData(" \0ABC")]
    public async Task Apply_NameEmptyBeforeNul_IsStoredAsNullWithCarKey(string name)
    {
        var payload = BasePayload() with
        {
            Results = new List<ClassifiedResultDto> { PlayerCar(), AiCar(carIndex: 1, gameDriverId: null, name: name) },
        };

        await ApplyStored(Envelope(payload));

        var row = Assert.Single(_sessions.Items).Results.Single(r => r.CarIndex == 1);
        Assert.Null(row.DriverName);
        Assert.Equal($"car:{SessionRef}:1", row.DriverKey);
    }

    [Fact]
    public async Task Apply_NulPaddedActualCompound_IsCutAtNul()
    {
        var stints = new List<TyreStintDto> { new(EndLap: 29, VisualCompound: "Hard", ActualCompound: "C3\0") };
        var payload = BasePayload() with { Results = new List<ClassifiedResultDto> { PlayerCar() with { TyreStints = stints } } };

        await ApplyStored(Envelope(payload));

        var stint = Assert.Single(Assert.Single(Assert.Single(_sessions.Items).Results).TyreStints);
        Assert.Equal("C3", stint.ActualCompound);
    }

    [Fact]
    public async Task Apply_NulPaddedStrings_NeverReachStoredEntities()
    {
        // PostgreSQL 텍스트는 NUL을 저장하지 못한다 — 어떤 엔티티 문자열에도 '\0'이 남으면 안 된다.
        var stints = new List<TyreStintDto>
        {
            new(EndLap: 14, VisualCompound: "Medium", ActualCompound: "C3\0\0"),
            new(EndLap: 29, VisualCompound: "Hard", ActualCompound: "\0"),
        };
        var payload = BasePayload() with
        {
            Results = new List<ClassifiedResultDto>
            {
                PlayerCar() with { DriverName = "S. LIM\0\0\0", TyreStints = stints },
                AiCar(carIndex: 1, gameDriverId: null, name: "Driver Nine\0\0") with { TyreStints = stints },
                AiCar(carIndex: 2, gameDriverId: null, name: "\0\0\0") with { TyreStints = stints },
            },
        };

        await ApplyStored(Envelope(payload));

        var session = Assert.Single(_sessions.Items);
        var entities = new List<object> { session, Assert.Single(_seasons.Seasons), Assert.Single(_seasons.Weekends) };
        entities.AddRange(session.Results);
        entities.AddRange(session.Results.SelectMany(r => r.TyreStints));
        var strings = entities.SelectMany(StringValues).ToList();
        Assert.NotEmpty(strings);
        Assert.DoesNotContain(strings, s => s.Contains('\0'));
        Assert.Equal("name:DRIVER NINE#9", session.Results.Single(r => r.CarIndex == 1).DriverKey);
        Assert.Equal($"car:{SessionRef}:2", session.Results.Single(r => r.CarIndex == 2).DriverKey);
        Assert.Null(session.Results.Single(r => r.CarIndex == 2).DriverName);
        Assert.Equal(new string?[] { "C3", null }, session.Results.Single(r => r.CarIndex == 0).TyreStints.OrderBy(s => s.StintNumber).Select(s => s.ActualCompound));
    }

    [Fact]
    public async Task Apply_SessionRefWithNul_RejectsAndAddsNothing()
    {
        var outcome = await Apply(Envelope(BasePayload() with { SessionRef = "1844\0" }));

        var rejected = Assert.IsType<ClassificationOutcome.Rejected>(outcome);
        Assert.StartsWith("SessionClassified 검증 실패: ", rejected.Reason);
        Assert.Equal(0, _tracks.LookupCalls);
        AssertNothingAdded();
    }

    private static IEnumerable<string> StringValues(object entity)
        => entity.GetType().GetProperties()
            .Where(p => p.PropertyType == typeof(string) && p.GetIndexParameters().Length == 0)
            .Select(p => (string?)p.GetValue(entity))
            .OfType<string>();

    [Theory]
    [InlineData("TimeTrial", "DriverCareer")]
    [InlineData("Race", "TimeTrial")]
    [InlineData("timetrial", "Other")]
    public async Task Apply_TimeTrial_IsIgnored(string sessionType, string gameMode)
    {
        var outcome = await Apply(Envelope(BasePayload() with { SessionType = sessionType, GameMode = gameMode }));

        Assert.IsType<ClassificationOutcome.Ignored>(outcome);
        Assert.Equal(0, _tracks.LookupCalls);
        AssertNothingAdded();
    }

    [Fact]
    public async Task Apply_FutureOccurredAt_IsClampedToServerSkew()
    {
        var outcome = await Apply(Envelope(BasePayload(), Now.AddHours(3)));

        Assert.IsType<ClassificationOutcome.Stored>(outcome);
        Assert.Equal(TimeSpan.FromMinutes(5), SessionClassificationIngestor.MaxClockSkew);
        var expected = Now.AddMinutes(5);
        Assert.Equal(expected, Assert.Single(_sessions.Items).ClassifiedAt);
        var season = Assert.Single(_seasons.Seasons);
        Assert.Equal((expected, expected), (season.FirstSessionAt, season.LastSessionAt));
        Assert.Equal(expected, Assert.Single(_seasons.Weekends).FirstSessionAt);
    }

    [Theory]
    [InlineData(DateTimeKind.Unspecified)]
    [InlineData(DateTimeKind.Local)]
    public async Task Apply_NonUtcOccurredAt_IsStoredAsUtc(DateTimeKind kind)
    {
        // Npgsql은 timestamptz에 Utc가 아닌 DateTime을 쓰면 예외를 낸다 — 같은 입력에 항상 실패하지 않도록 Utc로 맞춘다.
        var occurredAt = kind == DateTimeKind.Local
            ? OccurredAt.ToLocalTime()
            : DateTime.SpecifyKind(OccurredAt, DateTimeKind.Unspecified);

        await ApplyStored(Envelope(BasePayload(), occurredAt));

        var stored = Assert.Single(_sessions.Items).ClassifiedAt;
        Assert.Equal(DateTimeKind.Utc, stored.Kind);
        Assert.Equal(OccurredAt, stored);
        var season = Assert.Single(_seasons.Seasons);
        Assert.Equal(DateTimeKind.Utc, season.FirstSessionAt.Kind);
        Assert.Equal(DateTimeKind.Utc, season.LastSessionAt.Kind);
    }

    [Fact]
    public async Task Apply_UnknownEnumStrings_FallBackToDefaults()
    {
        var payload = BasePayload() with
        {
            SessionKind = "Sprint",
            GameMode = "NewMode",
            Results = new List<ClassifiedResultDto>
            {
                PlayerCar() with
                {
                    ResultStatus = "Overtime",
                    TyreStints = new List<TyreStintDto> { new(EndLap: 29, VisualCompound: "Hyper", ActualCompound: "C3") },
                },
            },
        };

        var outcome = await Apply(Envelope(payload));

        Assert.IsType<ClassificationOutcome.Stored>(outcome);
        var session = Assert.Single(_sessions.Items);
        Assert.Equal(SessionKind.Unknown, session.SessionKind);
        Assert.Equal(GameMode.Other, session.GameMode);
        Assert.Null(session.SeasonId);
        Assert.Equal($"uid:{SessionRef}", session.SessionKey);
        Assert.Empty(_seasons.Seasons);
        var row = Assert.Single(session.Results);
        Assert.Equal(ResultStatus.Unknown, row.ResultStatus);
        Assert.Equal(TyreCompound.Unknown, Assert.Single(row.TyreStints).VisualCompound);
    }

    [Fact]
    public async Task Apply_MissingParticipant_UsesSessionScopedCarKey()
    {
        var payload = BasePayload() with
        {
            Results = new List<ClassifiedResultDto> { PlayerCar(), AiCar(carIndex: 5, gameDriverId: null, name: null) with { RaceNumber = null } },
        };

        await ApplyStored(Envelope(payload));

        var row = Assert.Single(_sessions.Items).Results.Single(r => r.CarIndex == 5);
        Assert.Equal($"car:{SessionRef}:5", row.DriverKey);
        Assert.Null(row.DriverName);
    }

    // ---- Reject · 불변식 ----

    [Fact]
    public async Task Apply_MalformedPayload_Rejects()
    {
        var outcome = await Apply(RawEnvelope(JsonSerializer.SerializeToElement(new[] { 1, 2, 3 })));

        Assert.Equal(new ClassificationOutcome.Rejected("SessionClassified payload 파싱 실패"), outcome);
        Assert.Equal(0, _tracks.LookupCalls);
        AssertNothingAdded();
    }

    [Fact]
    public async Task Apply_WrongFieldType_RejectsAsMalformed()
    {
        using var document = JsonDocument.Parse("""{"sessionRef":"1","trackId":"ten","results":[]}""");

        var outcome = await Apply(RawEnvelope(document.RootElement.Clone()));

        Assert.Equal(new ClassificationOutcome.Rejected("SessionClassified payload 파싱 실패"), outcome);
        AssertNothingAdded();
    }

    [Fact]
    public async Task Apply_NullOrMissingPayload_RejectsAsEmpty()
    {
        using var nullDocument = JsonDocument.Parse("null");

        var nullOutcome = await Apply(RawEnvelope(nullDocument.RootElement.Clone()));
        var missingOutcome = await Apply(RawEnvelope(default));

        var expected = new ClassificationOutcome.Rejected("SessionClassified payload가 비어 있습니다.");
        Assert.Equal(expected, nullOutcome);
        Assert.Equal(expected, missingOutcome);
        AssertNothingAdded();
    }

    [Fact]
    public async Task Apply_InvalidPayload_RejectsWithDetail()
    {
        var outcome = await Apply(Envelope(BasePayload() with { Results = new List<ClassifiedResultDto>() }));

        var rejected = Assert.IsType<ClassificationOutcome.Rejected>(outcome);
        Assert.StartsWith("SessionClassified 검증 실패: ", rejected.Reason);
        Assert.Contains("results", rejected.Reason);
        Assert.Equal(0, _tracks.LookupCalls);
        AssertNothingAdded();
    }

    [Fact]
    public async Task Apply_UnknownTrack_Rejects()
    {
        var outcome = await Apply(Envelope(BasePayload() with { TrackId = 99 }));

        Assert.Equal(new ClassificationOutcome.Rejected("트랙 매핑 없음(gameCode=F1_25, trackId=99)"), outcome);
        AssertNothingAdded();
    }

    // ---- Fakes ----

    private sealed class FakeSeasons : ISeasonRepository
    {
        public List<Season> Seasons { get; } = new();
        public List<RaceWeekend> Weekends { get; } = new();
        public int SeasonAddCalls { get; private set; }
        public int WeekendAddCalls { get; private set; }

        public Task<Season?> GetByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default)
            => Task.FromResult(Seasons.FirstOrDefault(s =>
                !s.IsDeleted && s.UserId == userId && s.GameCode == gameCode && s.SeasonLinkId == seasonLinkId));

        public Task<RaceWeekend?> GetWeekendAsync(Guid seasonId, long weekendLinkId, CancellationToken cancellationToken = default)
            => Task.FromResult(Weekends.FirstOrDefault(w =>
                !w.IsDeleted && w.SeasonId == seasonId && w.WeekendLinkId == weekendLinkId));

        public Task AddAsync(Season season, CancellationToken cancellationToken = default)
        {
            SeasonAddCalls++;
            Seasons.Add(season);
            return Task.CompletedTask;
        }

        public Task AddWeekendAsync(RaceWeekend weekend, CancellationToken cancellationToken = default)
        {
            WeekendAddCalls++;
            Weekends.Add(weekend);
            return Task.CompletedTask;
        }
    }

    private sealed class FakeSessions : IGameSessionRepository
    {
        public List<GameSession> Items { get; } = new();
        public int AddCalls { get; private set; }

        public Task<GameSession?> GetByKeyWithResultsAsync(Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
            => Task.FromResult(Items.FirstOrDefault(s =>
                !s.IsDeleted && s.UserId == userId && s.GameCode == gameCode && s.SessionKey == sessionKey));

        public Task AddAsync(GameSession session, CancellationToken cancellationToken = default)
        {
            AddCalls++;
            Items.Add(session);
            return Task.CompletedTask;
        }
    }

    private sealed class FakeTracks : ITrackRepository
    {
        public List<Track> Items { get; } = new();
        public int LookupCalls { get; private set; }

        public Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken cancellationToken = default)
        {
            LookupCalls++;
            return Task.FromResult(Items.FirstOrDefault(t => t.GameCode == gameCode && t.GameTrackId == gameTrackId));
        }

        public Task<Track?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
            => Task.FromResult(Items.FirstOrDefault(t => t.Id == id));

        public Task<IReadOnlyList<Track>> GetAllAsync(CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<Track>>(Items.ToList());
    }

    private sealed class SequentialIdGenerator : IIdGenerator
    {
        private int _counter;

        public Guid NewId()
        {
            _counter++;
            return new Guid(_counter, 0, 0, new byte[8]);
        }
    }
}
