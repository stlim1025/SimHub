using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Rankings;
using SimCenter.Application.Rankings.Notifications;
using SimCenter.Application.Telemetry;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Telemetry;

public class TelemetryIngestServiceTests
{
    private const string RigCode = "A-01";
    private const string GameCode = "F1_25";
    private const int GameTrackId = 7;

    private static readonly DateTime Now = new(2026, 7, 7, 9, 30, 0, DateTimeKind.Utc);
    private static readonly JsonSerializerOptions WireOptions =
        new(JsonSerializerDefaults.Web) { Converters = { new JsonStringEnumConverter() } };

    private readonly FakeProcessedEventRepository _processed = new();
    private readonly FakeSimRigRepository _rigs = new();
    private readonly FakeDrivingSessionRepository _sessions = new();
    private readonly FakeTrackRepository _tracks = new();
    private readonly FakeLapRepository _laps = new();
    private readonly FakeUnitOfWork _uow = new();
    private readonly FakeRankingService _ranking = new();
    private readonly FakeRankingNotifier _notifier = new();

    private readonly Guid _userId = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private readonly Guid _rigId = Guid.Parse("00000000-0000-0000-0000-0000000000e1");
    private readonly Guid _trackId = Guid.Parse("00000000-0000-0000-0000-0000000000c7");
    private readonly Guid _sessionId = Guid.Parse("00000000-0000-0000-0000-0000000000d1");

    private readonly TelemetryIngestService _sut;

    public TelemetryIngestServiceTests()
    {
        _rigs.Items.Add(new SimRig { Id = _rigId, StoreId = Guid.NewGuid(), RigCode = RigCode, DisplayName = "1번" });
        _tracks.Items.Add(new Track { Id = _trackId, GameCode = GameCode, GameTrackId = GameTrackId, Name = "Silverstone" });

        _sut = new TelemetryIngestService(
            _processed, _rigs, _sessions, _tracks, _laps, _uow,
            new SequentialIdGenerator(), new FakeClock(Now), _ranking, _notifier,
            NullLogger<TelemetryIngestService>.Instance);
    }

    private void GiveActiveSession() => _sessions.Items.Add(new DrivingSession
    {
        Id = _sessionId,
        UserId = _userId,
        SimRigId = _rigId,
        StoreId = Guid.NewGuid(),
        GameCode = GameCode,
        Status = SessionStatus.Active,
        StartedAt = Now.AddMinutes(-5),
    });

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

        return new TelemetryEnvelopeDto(
            eventId ?? Guid.NewGuid(), RigCode, GameCode, Now, "LapFinished", payload);
    }

    [Fact]
    public async Task LapFinished_WithActiveSession_PersistsLapWithSectors_AndAcks()
    {
        GiveActiveSession();

        var result = await _sut.IngestAsync(LapFinished(), RigCode);

        Assert.True(result.Acknowledged);
        var lap = Assert.Single(_laps.Items);
        Assert.Equal(_userId, lap.UserId);
        Assert.Equal(_sessionId, lap.DrivingSessionId);
        Assert.Equal(_trackId, lap.TrackId);
        Assert.Equal(83452, lap.LapTimeMs);
        Assert.Equal(3, lap.Sectors.Count);
        Assert.True(lap.IsRankingEligible);
        Assert.Equal(Now, lap.SetAt);
        Assert.Equal(1, _uow.SaveCount);
        Assert.Single(_processed.Items); // 멱등 기록됨
    }

    [Theory]
    [InlineData(false, false, SessionType.TimeTrial)]   // 무효
    [InlineData(true, true, SessionType.TimeTrial)]     // 아웃/인랩
    [InlineData(true, false, SessionType.Race)]         // 비 TimeTrial
    public async Task LapFinished_NotEligibleConditions_SavedButNotRankingEligible(
        bool isValid, bool isOutOrInLap, SessionType sessionType)
    {
        GiveActiveSession();

        await _sut.IngestAsync(LapFinished(isValid: isValid, isOutOrInLap: isOutOrInLap, sessionType: sessionType), RigCode);

        var lap = Assert.Single(_laps.Items);
        Assert.False(lap.IsRankingEligible);
    }

    [Fact]
    public async Task EligibleLap_Broadcasts_LapRecorded_PersonalBest_AndRankingUpdated()
    {
        GiveActiveSession();

        await _sut.IngestAsync(LapFinished(), RigCode);

        var recorded = Assert.Single(_notifier.LapRecords);
        Assert.Equal(_userId, recorded.UserId);
        Assert.Equal(_trackId, recorded.TrackId);
        Assert.True(recorded.IsRankingEligible);

        var pb = Assert.Single(_notifier.PersonalBests);
        Assert.Equal(83452, pb.LapTimeMs);
        Assert.Null(pb.PreviousBestMs); // 첫 기록이라 이전 최고 없음.

        var snapshot = Assert.Single(_notifier.RankingUpdates);
        Assert.Equal(_trackId, snapshot.TrackId);
        Assert.Equal(1, _ranking.RankingCalls);
    }

    [Fact]
    public async Task EligibleLap_SlowerThanExistingBest_NoPersonalBest_ButStillRankingUpdated()
    {
        GiveActiveSession();
        // 더 빠른 기존 최고(랭킹적격)를 미리 심는다.
        _laps.Items.Add(new Lap
        {
            Id = Guid.NewGuid(),
            DrivingSessionId = _sessionId,
            UserId = _userId,
            TrackId = _trackId,
            GameCode = GameCode,
            SessionType = SessionType.TimeTrial,
            LapNumber = 1,
            LapTimeMs = 80000, // 들어오는 83452보다 빠름.
            IsValid = true,
            IsRankingEligible = true,
            SetAt = Now.AddMinutes(-10),
        });

        await _sut.IngestAsync(LapFinished(), RigCode);

        Assert.Empty(_notifier.PersonalBests);          // PB 아님.
        Assert.Single(_notifier.RankingUpdates);         // 랭킹은 여전히 갱신.
        Assert.Single(_notifier.LapRecords);
    }

    [Fact]
    public async Task NonEligibleValidLap_BroadcastsLapRecorded_ButNotRanking()
    {
        GiveActiveSession();

        // Race 세션 = 유효하지만 랭킹 비적격.
        await _sut.IngestAsync(LapFinished(sessionType: SessionType.Race), RigCode);

        Assert.Single(_notifier.LapRecords);     // 유효 랩이므로 LapRecorded는 발행.
        Assert.Empty(_notifier.RankingUpdates);  // 비적격이라 랭킹 미브로드캐스트.
        Assert.Empty(_notifier.PersonalBests);
        Assert.Equal(0, _ranking.RankingCalls);
    }

    [Fact]
    public async Task InvalidLap_DoesNotBroadcastLapRecorded()
    {
        GiveActiveSession();

        await _sut.IngestAsync(LapFinished(isValid: false), RigCode);

        Assert.Empty(_notifier.LapRecords);
        Assert.Empty(_notifier.RankingUpdates);
    }

    [Fact]
    public async Task DuplicateEventId_IsIdempotent_NoSecondPersist()
    {
        GiveActiveSession();
        var envelope = LapFinished(eventId: Guid.Parse("11111111-1111-1111-1111-111111111111"));

        await _sut.IngestAsync(envelope, RigCode);
        var second = await _sut.IngestAsync(envelope, RigCode);

        Assert.True(second.Acknowledged);
        Assert.Single(_laps.Items);   // 두 번째는 저장 안 됨
        Assert.Equal(1, _uow.SaveCount);
    }

    [Fact]
    public async Task NoActiveSession_DropsAndAcks_NoLapSaved()
    {
        // 세션 미부여.
        var result = await _sut.IngestAsync(LapFinished(), RigCode);

        Assert.True(result.Acknowledged);
        Assert.Empty(_laps.Items);
        Assert.Equal(0, _uow.SaveCount);
    }

    [Fact]
    public async Task UnknownTrack_Rejects()
    {
        GiveActiveSession();

        var result = await _sut.IngestAsync(LapFinished(trackId: 999), RigCode);

        Assert.False(result.Acknowledged);
        Assert.Empty(_laps.Items);
    }

    [Fact]
    public async Task NonLapFinishedEvent_Acks_WithoutPersist()
    {
        GiveActiveSession();
        var envelope = new TelemetryEnvelopeDto(
            Guid.NewGuid(), RigCode, GameCode, Now, "LapStarted",
            JsonSerializer.SerializeToElement(new { sessionRef = "s", lapNumber = 2 }, WireOptions));

        var result = await _sut.IngestAsync(envelope, RigCode);

        Assert.True(result.Acknowledged);
        Assert.Empty(_laps.Items);
    }

    [Fact]
    public async Task UnknownAuthenticatedRig_Rejects()
    {
        GiveActiveSession();

        var result = await _sut.IngestAsync(LapFinished(), "Z-99");

        Assert.False(result.Acknowledged);
        Assert.Empty(_laps.Items);
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

    private sealed class FakeSimRigRepository : ISimRigRepository
    {
        public List<SimRig> Items { get; } = new();

        public Task<SimRig?> GetByRigCodeAsync(string rigCode, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.RigCode == rigCode));

        public Task<SimRig?> GetByApiKeyHashAsync(string apiKeyHash, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.ApiKeyHash == apiKeyHash));
    }

    private sealed class FakeDrivingSessionRepository : IDrivingSessionRepository
    {
        public List<DrivingSession> Items { get; } = new();

        public Task<DrivingSession?> GetByIdAsync(Guid id, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.Id == id));

        public Task<DrivingSession?> GetActiveByRigAsync(Guid simRigId, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.SimRigId == simRigId && x.Status == SessionStatus.Active));

        public Task<DrivingSession?> GetActiveByUserAsync(Guid userId, CancellationToken ct = default)
            => Task.FromResult(Items.FirstOrDefault(x => x.UserId == userId && x.Status == SessionStatus.Active));

        public Task<IReadOnlyList<DrivingSession>> GetActiveSessionsByUserAsync(Guid userId, CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<DrivingSession>>(
                Items.Where(x => x.UserId == userId && x.Status == SessionStatus.Active).ToList());

        public Task AddAsync(DrivingSession session, CancellationToken ct = default)
        {
            Items.Add(session);
            return Task.CompletedTask;
        }
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

        public Task AddAsync(Lap lap, CancellationToken ct = default)
        {
            Items.Add(lap);
            return Task.CompletedTask;
        }

        public Task<IReadOnlyList<RankingLapRow>> GetRankingAsync(
            Guid trackId, string gameCode, SessionType sessionType, DateTime fromUtc, DateTime toUtc, int top, CancellationToken ct = default)
            => Task.FromResult<IReadOnlyList<RankingLapRow>>(new List<RankingLapRow>());

        public Task<(IReadOnlyList<Lap> Items, int Total)> GetMyLapsAsync(
            Guid userId, Guid? trackId, SessionType? sessionType, int skip, int take, CancellationToken ct = default)
            => Task.FromResult(((IReadOnlyList<Lap>)Items, Items.Count));

        public Task<Lap?> GetPersonalBestLapAsync(Guid userId, Guid trackId, string gameCode, CancellationToken ct = default)
            => Task.FromResult(Items
                .Where(l => l.UserId == userId && l.TrackId == trackId && l.GameCode == gameCode && l.IsRankingEligible)
                .OrderBy(l => l.LapTimeMs)
                .FirstOrDefault());
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
            Guid userId, Guid? trackId, SessionType? sessionType, int page, int pageSize, CancellationToken ct = default)
            => throw new NotImplementedException();
    }

    private sealed class FakeRankingNotifier : IRankingNotifier
    {
        public List<RankingSnapshotDto> RankingUpdates { get; } = new();
        public List<LapRecordedNotice> LapRecords { get; } = new();
        public List<PersonalBestNotice> PersonalBests { get; } = new();

        public Task RankingUpdatedAsync(RankingSnapshotDto snapshot, CancellationToken ct = default)
        {
            RankingUpdates.Add(snapshot);
            return Task.CompletedTask;
        }

        public Task LapRecordedAsync(LapRecordedNotice notice, CancellationToken ct = default)
        {
            LapRecords.Add(notice);
            return Task.CompletedTask;
        }

        public Task PersonalBestAchievedAsync(PersonalBestNotice notice, CancellationToken ct = default)
        {
            PersonalBests.Add(notice);
            return Task.CompletedTask;
        }
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
