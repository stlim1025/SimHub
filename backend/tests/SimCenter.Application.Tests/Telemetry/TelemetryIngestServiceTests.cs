using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Laps.Ingest;
using SimCenter.Application.Rankings;
using SimCenter.Application.Rankings.Notifications;
using SimCenter.Application.Seasons.Ingest;
using SimCenter.Application.Telemetry;
using SimCenter.Application.Tests.Laps;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Telemetry;

public class TelemetryIngestServiceTests
{
    private const string GameCode = "F1_25";
    private const int GameTrackId = 7;
    private const string RevokedDeviceReason = "연결이 해제된 장치입니다.";

    private static readonly DateTime Now = new(2026, 7, 7, 9, 30, 0, DateTimeKind.Utc);
    private static readonly JsonSerializerOptions WireOptions =
        new(JsonSerializerDefaults.Web) { Converters = { new JsonStringEnumConverter() } };

    private readonly FakeProcessedEventRepository _processed = new();
    private readonly FakeAgentDeviceRepository _devices = new();
    private readonly FakeTrackRepository _tracks = new();
    private readonly FakeLapRepository _laps = new();
    private readonly FakeClassificationIngestor _classification = new();
    private readonly FakeUnitOfWork _uow = new();
    private readonly FakeRankingService _ranking = new();
    private readonly FakeRankingNotifier _notifier = new();
    private readonly LapsBackedQueryRepository _lapQueries;

    private readonly Guid _ownerId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private readonly Guid _deviceId = Guid.Parse("00000000-0000-0000-0000-0000000000e1");
    private readonly Guid _trackId = Guid.Parse("00000000-0000-0000-0000-0000000000c7");

    private readonly AgentDevice _device;
    private readonly TelemetryIngestService _sut;

    public TelemetryIngestServiceTests()
    {
        _device = new AgentDevice { Id = _deviceId, UserId = _ownerId, Name = "SIM-PC", ApiKeyHash = "h:key" };
        _devices.Items.Add(_device);
        _tracks.Items.Add(new Track { Id = _trackId, GameCode = GameCode, GameTrackId = GameTrackId, Name = "Silverstone" });

        _lapQueries = new LapsBackedQueryRepository(_laps, _tracks);

        var ids = new SequentialIdGenerator();
        _sut = new TelemetryIngestService(
            _processed, _devices, _tracks, _laps, _classification, _uow,
            ids, new FakeClock(Now), _ranking, _notifier, _lapQueries,
            new LapDetailExtractor(ids, NullLogger<LapDetailExtractor>.Instance),
            NullLogger<TelemetryIngestService>.Instance);
    }

    /// <summary>랩 + 선택 영역(15 §4.3). null인 영역은 싣지 않는다(옛 Agent).</summary>
    private static TelemetryEnvelopeDto LapFinishedWithDetail(
        object? car = null, object? conditions = null, object? trace = null, string? gameMode = null)
    {
        var payload = new Dictionary<string, object?>
        {
            ["sessionRef"] = "0xSESSION",
            ["lapNumber"] = 4,
            ["lapTimeMs"] = 83452,
            ["sectors"] = new[] { new { sectorNumber = 1, sectorTimeMs = 83452 } },
            ["isValid"] = true,
            ["isOutOrInLap"] = false,
            ["trackId"] = GameTrackId,
            ["sessionType"] = nameof(SessionType.TimeTrial),
        };
        AddIfPresent(payload, "car", car);
        AddIfPresent(payload, "conditions", conditions);
        AddIfPresent(payload, "trace", trace);
        AddIfPresent(payload, "gameMode", gameMode);

        return new TelemetryEnvelopeDto(
            Guid.NewGuid(), GameCode, Now, "LapFinished", JsonSerializer.SerializeToElement(payload, WireOptions));
    }

    private static void AddIfPresent(Dictionary<string, object?> payload, string key, object? value)
    {
        if (value is not null)
        {
            payload[key] = value;
        }
    }

    private TelemetryEnvelopeDto LapFinished(
        Guid? eventId = null,
        bool isValid = true,
        bool isOutOrInLap = false,
        SessionType sessionType = SessionType.TimeTrial,
        int trackId = GameTrackId)
    {
        var payload = JsonSerializer.SerializeToElement(new
        {
            sessionRef = "0xSESSION",
            lapNumber = 4,
            lapTimeMs = 83452,
            sectors = new[]
            {
                new { sectorNumber = 1, sectorTimeMs = 27010 },
                new { sectorNumber = 2, sectorTimeMs = 30110 },
                new { sectorNumber = 3, sectorTimeMs = 26332 },
            },
            isValid,
            isOutOrInLap,
            trackId,
            sessionType = sessionType.ToString(),
        }, WireOptions);

        return new TelemetryEnvelopeDto(eventId ?? Guid.NewGuid(), GameCode, Now, "LapFinished", payload);
    }

    /// <summary>랩 이벤트. <paramref name="context"/>가 null이면 옛 Agent처럼 모드·링크 필드를 아예 싣지 않는다.</summary>
    private static TelemetryEnvelopeDto LapFinishedWith(string sessionRef, (string GameMode, long Season, long Weekend, long Session)? context)
    {
        var payload = new Dictionary<string, object?>
        {
            ["sessionRef"] = sessionRef,
            ["lapNumber"] = 4,
            ["lapTimeMs"] = 83452,
            ["sectors"] = new[] { new { sectorNumber = 1, sectorTimeMs = 83452 } },
            ["isValid"] = true,
            ["isOutOrInLap"] = false,
            ["trackId"] = GameTrackId,
            ["sessionType"] = nameof(SessionType.Race),
        };

        if (context is { } c)
        {
            payload["gameMode"] = c.GameMode;
            payload["seasonLinkId"] = c.Season;
            payload["weekendLinkId"] = c.Weekend;
            payload["sessionLinkId"] = c.Session;
        }

        return new TelemetryEnvelopeDto(
            Guid.NewGuid(), GameCode, Now, "LapFinished", JsonSerializer.SerializeToElement(payload, WireOptions));
    }

    private static TelemetryEnvelopeDto SessionClassifiedEvent() => new(
        Guid.NewGuid(), GameCode, Now, "SessionClassified",
        JsonSerializer.SerializeToElement(new { sessionRef = "s" }, WireOptions));

    private static TelemetryEnvelopeDto NonLapEvent(string type) => new(
        Guid.NewGuid(), GameCode, Now, type,
        JsonSerializer.SerializeToElement(new { sessionRef = "s", lapNumber = 2 }, WireOptions));

    [Fact]
    public async Task LapFinished_FromDevice_AttributesToDeviceOwner()
    {
        var result = await _sut.IngestAsync(LapFinished(), _deviceId);

        Assert.True(result.Acknowledged);
        var lap = Assert.Single(_laps.Items);
        Assert.Equal(_ownerId, lap.UserId);
        Assert.Equal(_deviceId, lap.AgentDeviceId);
        Assert.Equal(_trackId, lap.TrackId);
        Assert.Equal(83452, lap.LapTimeMs);
        Assert.Equal(3, lap.Sectors.Count);
        Assert.True(lap.IsRankingEligible);
        Assert.Equal(Now, lap.SetAt);
        Assert.Equal(Now, _device.LastSeenAt); // 랩 저장과 같은 커밋에 포함된다.
        Assert.Equal(1, _uow.SaveCount);
        Assert.Single(_processed.Items); // 멱등 기록됨
    }

    [Theory]
    [InlineData("missing")]
    [InlineData("revoked")]
    public async Task AnyEvent_FromMissingOrRevokedDevice_Rejects(string scenario)
    {
        var deviceId = _deviceId;
        if (scenario == "missing")
        {
            deviceId = Guid.NewGuid();
        }
        else
        {
            _device.IsDeleted = true; // 연결 해제 = soft delete → 전역 필터로 조회되지 않는다.
        }

        var lapResult = await _sut.IngestAsync(LapFinished(), deviceId);
        var otherResult = await _sut.IngestAsync(NonLapEvent("SessionStarted"), deviceId);

        Assert.False(lapResult.Acknowledged);
        Assert.Equal(RevokedDeviceReason, lapResult.RejectReason);
        Assert.False(otherResult.Acknowledged);
        Assert.Equal(RevokedDeviceReason, otherResult.RejectReason);
        Assert.Empty(_laps.Items);
        Assert.Empty(_processed.Items);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task LastSeenAt_WrittenWhenNull_SkippedWithinOneMinute_WrittenAfter()
    {
        // 1) 수신 이력 없음 → 지금 시각으로 기록.
        await _sut.IngestAsync(NonLapEvent("LapStarted"), _deviceId);
        Assert.Equal(Now, _device.LastSeenAt);
        Assert.Equal(1, _uow.SaveCount);

        // 2) 30초 전에 기록됨 → 1분이 안 지났으므로 쓰지 않는다.
        var recent = Now.AddSeconds(-30);
        _device.LastSeenAt = recent;
        await _sut.IngestAsync(NonLapEvent("LapStarted"), _deviceId);
        Assert.Equal(recent, _device.LastSeenAt);
        Assert.Equal(1, _uow.SaveCount);

        // 3) 61초 전에 기록됨 → 다시 기록.
        _device.LastSeenAt = Now.AddSeconds(-61);
        await _sut.IngestAsync(NonLapEvent("LapStarted"), _deviceId);
        Assert.Equal(Now, _device.LastSeenAt);
        Assert.Equal(2, _uow.SaveCount);
    }

    [Fact]
    public async Task NonLapEvent_UpdatesLastSeenAt_WithSingleSave()
    {
        var result = await _sut.IngestAsync(NonLapEvent("SessionStarted"), _deviceId);

        Assert.True(result.Acknowledged);
        Assert.Equal(Now, _device.LastSeenAt);
        Assert.Equal(1, _uow.SaveCount);
        Assert.Empty(_laps.Items);
    }

    [Fact]
    public async Task NonLapEvent_WithRecentLastSeen_AcksWithoutSave()
    {
        _device.LastSeenAt = Now.AddSeconds(-10);

        var result = await _sut.IngestAsync(NonLapEvent("LapStarted"), _deviceId);

        Assert.True(result.Acknowledged);
        Assert.Equal(0, _uow.SaveCount);
        Assert.Empty(_laps.Items);
    }

    [Fact]
    public async Task DuplicateEvent_IsAckedBeforeDeviceCheck()
    {
        var eventId = Guid.Parse("22222222-2222-2222-2222-222222222222");
        _processed.Items.Add(new ProcessedEvent { EventId = eventId, EventType = "LapFinished", ProcessedAt = Now });

        var result = await _sut.IngestAsync(LapFinished(eventId: eventId), Guid.NewGuid()); // 없는 장치

        Assert.True(result.Acknowledged);
        Assert.Empty(_laps.Items);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Theory]
    [InlineData(false, false, SessionType.TimeTrial)]   // 무효
    [InlineData(true, true, SessionType.TimeTrial)]     // 아웃/인랩
    [InlineData(true, false, SessionType.Race)]         // 비 TimeTrial
    public async Task LapFinished_NotEligibleConditions_SavedButNotRankingEligible(
        bool isValid, bool isOutOrInLap, SessionType sessionType)
    {
        await _sut.IngestAsync(LapFinished(isValid: isValid, isOutOrInLap: isOutOrInLap, sessionType: sessionType), _deviceId);

        var lap = Assert.Single(_laps.Items);
        Assert.False(lap.IsRankingEligible);
    }

    [Fact]
    public async Task EligibleLap_Broadcasts_LapRecorded_PersonalBest_AndRankingUpdated()
    {
        await _sut.IngestAsync(LapFinished(), _deviceId);

        var recorded = Assert.Single(_notifier.LapRecords);
        Assert.Equal(_ownerId, recorded.UserId);
        Assert.Equal(_trackId, recorded.Notice.TrackId);
        Assert.True(recorded.Notice.IsRankingEligible);

        var pb = Assert.Single(_notifier.PersonalBests);
        Assert.Equal(_ownerId, pb.UserId);
        Assert.Equal(83452, pb.LapTimeMs);
        Assert.Null(pb.PreviousBestMs); // 첫 기록이라 이전 최고 없음.

        var snapshot = Assert.Single(_notifier.RankingUpdates);
        Assert.Equal(_trackId, snapshot.TrackId);
        Assert.Equal(1, _ranking.RankingCalls);
    }

    [Fact]
    public async Task EligibleLap_SlowerThanExistingBest_NoPersonalBest_ButStillRankingUpdated()
    {
        // 더 빠른 기존 최고(랭킹적격)를 미리 심는다.
        _laps.Items.Add(new Lap
        {
            Id = Guid.NewGuid(),
            AgentDeviceId = _deviceId,
            UserId = _ownerId,
            TrackId = _trackId,
            GameCode = GameCode,
            SessionType = SessionType.TimeTrial,
            LapNumber = 1,
            LapTimeMs = 80000, // 들어오는 83452보다 빠름.
            IsValid = true,
            IsRankingEligible = true,
            SetAt = Now.AddMinutes(-10),
        });

        await _sut.IngestAsync(LapFinished(), _deviceId);

        Assert.Empty(_notifier.PersonalBests);          // PB 아님.
        Assert.Single(_notifier.RankingUpdates);         // 랭킹은 여전히 갱신.
        Assert.Single(_notifier.LapRecords);
    }

    [Fact]
    public async Task NonEligibleValidLap_BroadcastsLapRecorded_ButNotRanking()
    {
        // Race 세션 = 유효하지만 랭킹 비적격.
        await _sut.IngestAsync(LapFinished(sessionType: SessionType.Race), _deviceId);

        Assert.Single(_notifier.LapRecords);     // 유효 랩이므로 LapRecorded는 발행.
        Assert.Empty(_notifier.RankingUpdates);  // 비적격이라 랭킹 미브로드캐스트.
        Assert.Empty(_notifier.PersonalBests);
        Assert.Equal(0, _ranking.RankingCalls);
    }

    [Fact]
    public async Task InvalidLap_StillSendsLapRecorded_ButNotRanking()
    {
        // D-50: 내 랩 목록은 무효 랩도 보이므로 무효 랩도 주인에게 알린다(랭킹은 아님).
        await _sut.IngestAsync(LapFinished(isValid: false), _deviceId);

        var recorded = Assert.Single(_notifier.LapRecords);
        Assert.False(recorded.Notice.IsValid);
        Assert.Empty(_notifier.RankingUpdates);
    }

    [Fact]
    public async Task SavedLap_SendsLapRecorded_ToOwner_WithSameLapDtoAsMyLaps()
    {
        await _sut.IngestAsync(LapFinished(), _deviceId);

        var lap = Assert.Single(_laps.Items);
        var (userId, notice) = Assert.Single(_notifier.LapRecords);
        Assert.Equal(_ownerId, userId);

        // GET /me/laps와 같은 매퍼 결과 + trackId(docs/15 §9, D-50).
        var expected = LapDtoMapper.ToLapDto((await _lapQueries.GetMineAsync(_ownerId, lap.Id))!);
        Assert.Equal(expected.Sectors, notice.Sectors);
        Assert.Equal(expected.Team, notice.Team);
        Assert.Equal(expected.Weather, notice.Weather);
        Assert.Equal(expected.IsRankingEligible, notice.IsRankingEligible);
        Assert.Equal(lap.Id, notice.LapId);
        Assert.Equal("Silverstone", notice.TrackName);
        Assert.Equal(GameCode, notice.GameCode);
        Assert.Equal(nameof(SessionType.TimeTrial), notice.SessionType);
        Assert.Equal(83452, notice.LapTimeMs);
        Assert.Equal(3, notice.Sectors.Count);
        Assert.Equal(4, notice.LapNumber);
        Assert.Equal(Now, notice.SetAt);
        Assert.False(notice.HasTrace);
        Assert.Equal(_trackId, notice.TrackId);
    }

    [Fact]
    public async Task DuplicateOrRejectedLap_DoesNotSendLapRecorded()
    {
        var envelope = LapFinished(eventId: Guid.Parse("22222222-2222-2222-2222-222222222222"));
        await _sut.IngestAsync(envelope, _deviceId);
        await _sut.IngestAsync(envelope, _deviceId);                   // 중복
        await _sut.IngestAsync(LapFinished(trackId: 999), _deviceId);  // 트랙 매핑 없음 → Reject

        Assert.Single(_notifier.LapRecords);
        Assert.Equal(1, _lapQueries.GetMineCalls);
    }

    [Fact]
    public async Task LapRecordedFailure_DoesNotBreakIngest_OrOtherBroadcasts()
    {
        _notifier.ThrowOnLapRecorded = true;

        var result = await _sut.IngestAsync(LapFinished(), _deviceId);

        Assert.True(result.Acknowledged);
        Assert.Single(_laps.Items);
        Assert.Single(_processed.Items);
        Assert.Single(_notifier.PersonalBests);   // 다른 브로드캐스트는 그대로.
        Assert.Single(_notifier.RankingUpdates);
    }

    [Fact]
    public async Task LapRowLookupFailure_DoesNotBreakIngest()
    {
        _lapQueries.ThrowOnGetMine = true;

        var result = await _sut.IngestAsync(LapFinished(), _deviceId);

        Assert.True(result.Acknowledged);
        Assert.Empty(_notifier.LapRecords);
        Assert.Single(_notifier.RankingUpdates);
    }

    [Fact]
    public async Task DuplicateEventId_IsIdempotent_NoSecondPersist()
    {
        var envelope = LapFinished(eventId: Guid.Parse("11111111-1111-1111-1111-111111111111"));

        await _sut.IngestAsync(envelope, _deviceId);
        var second = await _sut.IngestAsync(envelope, _deviceId);

        Assert.True(second.Acknowledged);
        Assert.Single(_laps.Items);   // 두 번째는 저장 안 됨
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task UnknownTrack_Rejects_ButStillRecordsLastSeen()
    {
        var result = await _sut.IngestAsync(LapFinished(trackId: 999), _deviceId);

        Assert.False(result.Acknowledged);
        Assert.Empty(_laps.Items);
        Assert.Empty(_processed.Items);
        Assert.Equal(Now, _device.LastSeenAt);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task MalformedLapPayload_Rejects()
    {
        var envelope = new TelemetryEnvelopeDto(
            Guid.NewGuid(), GameCode, Now, "LapFinished",
            JsonSerializer.SerializeToElement(new { lapTimeMs = "not-a-number" }, WireOptions));

        var result = await _sut.IngestAsync(envelope, _deviceId);

        Assert.False(result.Acknowledged);
        Assert.Empty(_laps.Items);
    }

    // ── SessionClassified 배선 ──

    [Fact]
    public async Task SessionClassified_Stored_RecordsProcessedEventAndSavesOnce()
    {
        _classification.Outcome = new ClassificationOutcome.Stored("link:11:22:33", IsNew: true);
        var envelope = SessionClassifiedEvent();

        var result = await _sut.IngestAsync(envelope, _deviceId);

        Assert.True(result.Acknowledged);
        var processed = Assert.Single(_processed.Items);
        Assert.Equal(envelope.EventId, processed.EventId);
        Assert.Equal("SessionClassified", processed.EventType);
        Assert.Equal(Now, processed.ProcessedAt);
        Assert.Equal(1, _uow.SaveCount); // 결과 저장(추적 변경) + 멱등 기록 + LastSeenAt이 한 커밋.
        Assert.Equal(Now, _device.LastSeenAt);
        Assert.Equal(1, _classification.CallCount);
        Assert.Empty(_laps.Items);
    }

    [Fact]
    public async Task SessionClassified_Ignored_StillRecordsProcessedEvent()
    {
        _classification.Outcome = new ClassificationOutcome.Ignored("Time Trial");

        var result = await _sut.IngestAsync(SessionClassifiedEvent(), _deviceId);

        Assert.True(result.Acknowledged);
        var processed = Assert.Single(_processed.Items);
        Assert.Equal("SessionClassified", processed.EventType);
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task SessionClassified_Rejected_SavesOnlyLastSeen()
    {
        _classification.Outcome = new ClassificationOutcome.Rejected("x");

        // LastSeenAt이 바뀌지 않으면(1분 이내) 저장하지 않는다.
        _device.LastSeenAt = Now.AddSeconds(-10);
        var recent = await _sut.IngestAsync(SessionClassifiedEvent(), _deviceId);
        Assert.False(recent.Acknowledged);
        Assert.Equal("x", recent.RejectReason);
        Assert.Equal(0, _uow.SaveCount);

        // LastSeenAt이 바뀐 경우에만 한 번 저장한다.
        _device.LastSeenAt = null;
        var stale = await _sut.IngestAsync(SessionClassifiedEvent(), _deviceId);
        Assert.False(stale.Acknowledged);
        Assert.Equal("x", stale.RejectReason);
        Assert.Equal(1, _uow.SaveCount);
        Assert.Equal(Now, _device.LastSeenAt);

        Assert.Empty(_processed.Items); // Reject는 멱등 기록을 남기지 않는다.
        Assert.Equal(2, _classification.CallCount);
    }

    [Fact]
    public async Task SessionClassified_FromRevokedDevice_RejectsBeforeIngestor()
    {
        _device.IsDeleted = true;

        var result = await _sut.IngestAsync(SessionClassifiedEvent(), _deviceId);

        Assert.False(result.Acknowledged);
        Assert.Equal(RevokedDeviceReason, result.RejectReason);
        Assert.Equal(0, _classification.CallCount);
        Assert.Empty(_processed.Items);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task SessionClassified_PassesDeviceAndServerTimeToIngestor()
    {
        await _sut.IngestAsync(SessionClassifiedEvent(), _deviceId);

        Assert.Same(_device, _classification.LastDevice);
        Assert.Equal(Now, _classification.LastNow);
    }

    // ── Lap.SessionKey ──

    [Fact]
    public async Task LapFinished_WithCareerContext_StoresLinkSessionKey()
    {
        await _sut.IngestAsync(LapFinishedWith("0xSESSION", ("DriverCareer", 11, 22, 33)), _deviceId);

        Assert.Equal("link:11:22:33", Assert.Single(_laps.Items).SessionKey);
    }

    [Fact]
    public async Task LapFinished_WithoutContext_StoresUidKey()
    {
        await _sut.IngestAsync(LapFinished(), _deviceId); // 기존 페이로드(모드·링크 필드 없음)

        Assert.Equal("uid:0xSESSION", Assert.Single(_laps.Items).SessionKey);
    }

    [Fact]
    public async Task LapFinished_UnknownGameModeString_StoresUidKey()
    {
        await _sut.IngestAsync(LapFinishedWith("0xSESSION", ("SomeFutureMode", 11, 22, 33)), _deviceId);

        Assert.Equal("uid:0xSESSION", Assert.Single(_laps.Items).SessionKey);
    }

    [Fact]
    public async Task LapFinished_OverlongSessionRef_StoresNullKey()
    {
        var tooLong = new string('1', 33);

        var result = await _sut.IngestAsync(LapFinishedWith(tooLong, null), _deviceId);

        Assert.True(result.Acknowledged); // 키를 못 만들어도 랩은 저장된다.
        var lap = Assert.Single(_laps.Items);
        Assert.Null(lap.SessionKey);
    }

    [Fact]
    public async Task LapFinished_MaxLengthSessionRef_StoresUidKey()
    {
        var maxLength = new string('1', 32);

        await _sut.IngestAsync(LapFinishedWith(maxLength, null), _deviceId);

        Assert.Equal($"uid:{maxLength}", Assert.Single(_laps.Items).SessionKey);
    }

    [Fact]
    public async Task LapFinished_SessionRefWithNul_StoresNullKey()
    {
        // PostgreSQL 텍스트 열은 NUL을 저장하지 못한다 → 키를 만들지 않아야 랩 저장이 매번 실패하지 않는다.
        var result = await _sut.IngestAsync(LapFinishedWith("12\u000034", null), _deviceId);

        Assert.True(result.Acknowledged);
        Assert.Null(Assert.Single(_laps.Items).SessionKey);
    }

    [Fact]
    public async Task LapFinished_EmptySessionRef_StoresNullKey()
    {
        await _sut.IngestAsync(LapFinishedWith(string.Empty, null), _deviceId);

        Assert.Null(Assert.Single(_laps.Items).SessionKey);
    }

    // ── 스냅샷·트레이스·게임 모드(15 §5) ──

    [Fact]
    public async Task LapFinished_WithCarConditionsTrace_SavesAllInOneCommit()
    {
        var result = await _sut.IngestAsync(
            LapFinishedWithDetail(LapDetailSamples.CarWire(), LapDetailSamples.ConditionsWire(), LapDetailSamples.TraceWire(20)),
            _deviceId);

        Assert.True(result.Acknowledged);
        var lap = Assert.Single(_laps.Items);
        Assert.NotNull(lap.Snapshot);
        Assert.Equal(lap.Id, lap.Snapshot.LapId);
        Assert.Equal(1, lap.Snapshot.TeamId);
        Assert.Equal(Weather.Clear, lap.Snapshot.Weather);
        var trace = Assert.Single(_laps.Traces);
        Assert.Equal(lap.Id, trace.LapId);
        Assert.Equal(20, trace.SampleCount);
        Assert.Equal(1, _uow.SaveCount); // 랩·스냅샷·트레이스·멱등 기록이 한 커밋.
        Assert.Single(_processed.Items);
    }

    [Fact]
    public async Task LapFinished_WithInvalidSnapshotAndTrace_StillSavesLap()
    {
        var badCar = new { engineDamage = 999 };
        var badTrace = new { resolutionM = 5, timeMs = new[] { 1, 2 } };

        var result = await _sut.IngestAsync(LapFinishedWithDetail(badCar, conditions: null, badTrace), _deviceId);

        Assert.True(result.Acknowledged); // 랩은 절대 거부하지 않는다.
        var lap = Assert.Single(_laps.Items);
        Assert.Null(lap.Snapshot);
        Assert.Empty(_laps.Traces);
        Assert.Single(_notifier.RankingUpdates);
    }

    [Fact]
    public async Task LapFinished_WithoutDetailParts_SavesLapWithoutSnapshotOrTrace()
    {
        await _sut.IngestAsync(LapFinished(), _deviceId); // 옛 Agent 페이로드

        var lap = Assert.Single(_laps.Items);
        Assert.Null(lap.Snapshot);
        Assert.Null(lap.GameMode);
        Assert.Empty(_laps.Traces);
    }

    [Theory]
    [InlineData("DriverCareer", "DriverCareer")]
    [InlineData("SomeFutureMode", "SomeFutureMode")]   // 모르는 값도 그대로
    [InlineData("", null)]
    [InlineData("1234567890123456789012345678901", null)] // 31자 > 열 길이 30
    [InlineData("Driver\u0000Career", null)]            // NUL은 PostgreSQL에 저장할 수 없다
    public async Task LapFinished_GameMode_StoredAsReceivedWhenStorable(string gameMode, string? expected)
    {
        var result = await _sut.IngestAsync(LapFinishedWithDetail(gameMode: gameMode), _deviceId);

        Assert.True(result.Acknowledged);
        Assert.Equal(expected, Assert.Single(_laps.Items).GameMode);
    }

    // ── Fakes ──

    private sealed class FakeProcessedEventRepository : IProcessedEventRepository
    {
        public List<ProcessedEvent> Items { get; } = new();

        public Task<bool> ExistsAsync(Guid eventId, CancellationToken ct = default)
            => Task.FromResult(Items.Any(x => x.EventId == eventId));

        public Task AddAsync(ProcessedEvent processedEvent, CancellationToken ct = default)
        {
            Items.Add(processedEvent);
            return Task.CompletedTask;
        }
    }

    private sealed class FakeAgentDeviceRepository : IAgentDeviceRepository
    {
        public List<AgentDevice> Items { get; } = new();

        public Task AddAsync(AgentDevice device, CancellationToken ct = default)
        {
            Items.Add(device);
            return Task.CompletedTask;
        }

        // 전역 soft-delete 필터를 모사: 해제된 장치는 조회되지 않는다.
        public Task<AgentDevice?> GetByIdAsync(Guid id, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.Id == id && !x.IsDeleted));

        public Task<AgentDevice?> GetByApiKeyHashAsync(string hash, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.ApiKeyHash == hash && !x.IsDeleted));

        public Task<IReadOnlyList<AgentDevice>> GetByUserAsync(Guid userId, CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<AgentDevice>>(
                Items.Where(x => x.UserId == userId && !x.IsDeleted).ToList());
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

    private sealed class FakeLapRepository : ILapRepository
    {
        public List<Lap> Items { get; } = new();
        public List<LapTelemetryTrace> Traces { get; } = new();

        public Task AddAsync(Lap lap, CancellationToken ct = default)
        {
            Items.Add(lap);
            return Task.CompletedTask;
        }

        public Task AddTraceAsync(LapTelemetryTrace trace, CancellationToken ct = default)
        {
            Traces.Add(trace);
            return Task.CompletedTask;
        }

        public Task<IReadOnlyList<RankingLapRow>> GetRankingAsync(
            Guid trackId, string gameCode, SessionType sessionType, DateTime fromUtc, DateTime toUtc, int top, CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<RankingLapRow>>(new List<RankingLapRow>());

        public Task<IReadOnlyList<MyTrackSummaryRow>> GetMyTrackSummariesAsync(Guid userId, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<Lap?> GetPersonalBestLapAsync(Guid userId, Guid trackId, string gameCode, CancellationToken ct = default)
            => Task.FromResult(Items
                .Where(l => l.UserId == userId && l.TrackId == trackId && l.GameCode == gameCode && l.IsRankingEligible)
                .OrderBy(l => l.LapTimeMs)
                .FirstOrDefault());
    }

    private sealed class FakeClassificationIngestor : ISessionClassificationIngestor
    {
        public ClassificationOutcome Outcome { get; set; } = new ClassificationOutcome.Stored("uid:s", IsNew: true);
        public int CallCount { get; private set; }
        public AgentDevice? LastDevice { get; private set; }
        public DateTime? LastNow { get; private set; }

        public Task<ClassificationOutcome> ApplyAsync(
            TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, CancellationToken ct = default)
        {
            CallCount++;
            LastDevice = device;
            LastNow = now;
            return Task.FromResult(Outcome);
        }
    }

    private sealed class FakeRankingService : IRankingService
    {
        public int RankingCalls { get; private set; }

        public Task<RankingSnapshotDto> GetRankingAsync(
            Guid trackId, string gameCode, RankingPeriod period, DateOnly? date, CancellationToken ct = default)
        {
            RankingCalls++;
            return Task.FromResult(new RankingSnapshotDto(
                trackId, "Silverstone", gameCode, period.ToString().ToLowerInvariant(), "2026-07",
                new List<RankingEntryDto>()));
        }

        public Task<TrackListResponse> GetTracksAsync(CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<MyLapsResponse> GetMyLapsAsync(
            Guid userId, Guid? trackId, SessionType? sessionType, bool validOnly, MyLapsSort sort, int page, int pageSize,
            CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<MyTracksResponse> GetMyTracksAsync(Guid userId, CancellationToken ct = default)
            => throw new NotImplementedException();
    }

    private sealed class FakeRankingNotifier : IRankingNotifier
    {
        public List<RankingSnapshotDto> RankingUpdates { get; } = new();
        public List<(Guid UserId, LapRecordedNotice Notice)> LapRecords { get; } = new();
        public bool ThrowOnLapRecorded { get; set; }
        public List<PersonalBestNotice> PersonalBests { get; } = new();

        public Task RankingUpdatedAsync(RankingSnapshotDto snapshot, CancellationToken ct = default)
        {
            RankingUpdates.Add(snapshot);
            return Task.CompletedTask;
        }

        public Task LapRecordedAsync(Guid userId, LapRecordedNotice notice, CancellationToken ct = default)
        {
            if (ThrowOnLapRecorded)
            {
                throw new InvalidOperationException("hub down");
            }

            LapRecords.Add((userId, notice));
            return Task.CompletedTask;
        }

        public Task PersonalBestAchievedAsync(PersonalBestNotice notice, CancellationToken ct = default)
        {
            PersonalBests.Add(notice);
            return Task.CompletedTask;
        }
    }

    /// <summary>저장된 랩 엔티티를 읽기 행으로 비추는 조회 저장소(실제 구현의 프로젝션을 흉내 낸다).</summary>
    private sealed class LapsBackedQueryRepository : ILapQueryRepository
    {
        private readonly FakeLapRepository _laps;
        private readonly FakeTrackRepository _tracks;

        public LapsBackedQueryRepository(FakeLapRepository laps, FakeTrackRepository tracks)
        {
            _laps = laps;
            _tracks = tracks;
        }

        public int GetMineCalls { get; private set; }
        public bool ThrowOnGetMine { get; set; }

        public Task<LapRow?> GetMineAsync(Guid userId, Guid lapId, CancellationToken ct = default)
        {
            if (ThrowOnGetMine)
            {
                throw new InvalidOperationException("db down");
            }

            GetMineCalls++;
            var lap = _laps.Items.FirstOrDefault(l => l.Id == lapId && l.UserId == userId);
            if (lap is null)
            {
                return Task.FromResult<LapRow?>(null);
            }

            var track = _tracks.Items.Single(t => t.Id == lap.TrackId);
            return Task.FromResult<LapRow?>(new LapRow(
                lap.Id, lap.TrackId, track.Name, track.CountryCode, lap.GameCode, lap.SessionType, lap.LapNumber, lap.LapTimeMs,
                lap.IsValid, lap.IsRankingEligible, lap.SetAt, lap.GameMode, lap.SessionKey, lap.Snapshot?.TeamId,
                lap.Snapshot?.Weather, _laps.Traces.Any(t => t.LapId == lap.Id),
                lap.Sectors.OrderBy(s => s.SectorNumber).Select(s => new LapSectorDto(s.SectorNumber, s.SectorTimeMs)).ToList(),
                lap.UserId));
        }

        public Task<(IReadOnlyList<LapRow> Items, int Total)> GetMyPageAsync(
            Guid userId, MyLapsFilter filter, MyLapsSort sort, int skip, int take, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<LapRow?> FindFastestAsync(LapComparisonCriteria criteria, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<LapRow?> GetComparableAsync(Guid userId, Guid lapId, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<LapRow?> GetSharedAsync(Guid lapId, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<LapDriverRow?> GetDriverAsync(Guid userId, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<LapSnapshot?> GetSnapshotAsync(Guid lapId, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<LapTelemetryTrace?> GetSharedTraceAsync(Guid lapId, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<LapTelemetryTrace?> GetMyTraceAsync(Guid userId, Guid lapId, CancellationToken ct = default)
            => throw new NotImplementedException();

        public Task<LapTelemetryTrace?> GetComparableTraceAsync(Guid userId, Guid lapId, CancellationToken ct = default)
            => throw new NotImplementedException();
    }

    private sealed class FakeUnitOfWork : IUnitOfWork
    {
        public int SaveCount { get; private set; }

        public Task<int> SaveChangesAsync(CancellationToken ct = default)
        {
            SaveCount++;
            return Task.FromResult(1);
        }
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

    private sealed class FakeClock : IClock
    {
        public FakeClock(DateTime utcNow) => UtcNow = utcNow;

        public DateTime UtcNow { get; }
    }
}
