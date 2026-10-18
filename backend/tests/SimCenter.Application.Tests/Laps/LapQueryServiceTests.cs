using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Laps;

/// <summary>랩 상세·트레이스 조회(15 §4.2, D-46): 매핑, 비교 대상, 세션 연결, 404(D-34).</summary>
public class LapQueryServiceTests
{
    private const string GameCode = "F1_25";
    private const string SessionKey = "link:11:22:33";

    private static readonly Guid Me = Guid.Parse("00000000-0000-0000-0000-0000000000a1");
    private static readonly Guid Other = Guid.Parse("00000000-0000-0000-0000-0000000000a2");
    private static readonly Guid Jeddah = Guid.Parse("00000000-0000-0000-0000-0000000000c5");
    private static readonly Guid Monza = Guid.Parse("00000000-0000-0000-0000-0000000000c6");
    private static readonly DateTime T0 = new(2026, 10, 18, 9, 0, 0, DateTimeKind.Utc);

    private readonly FakeLapQueryRepository _laps = new();
    private readonly FakeSessionLookup _sessions = new();
    private readonly LapQueryService _sut;

    public LapQueryServiceTests() => _sut = new LapQueryService(_laps, _sessions, NullLogger<LapQueryService>.Instance);

    private LapRow AddLap(Guid userId, int lapTimeMs, bool isValid = true, Guid? trackId = null, DateTime? setAt = null,
        int? teamId = null, Weather? weather = null, bool hasTrace = false, string? sessionKey = null)
    {
        var row = FakeLapQueryRepository.Row(
            Guid.NewGuid(), trackId ?? Jeddah, lapTimeMs, isValid, setAt ?? T0, teamId, weather, hasTrace, sessionKey, "DriverCareer");
        _laps.Laps.Add((userId, row));
        return row;
    }

    [Fact]
    public async Task Detail_MapsLapTrackAndSnapshot()
    {
        var lap = AddLap(Me, 98_448, teamId: 8, weather: Weather.Overcast, hasTrace: true);
        _laps.Snapshots[lap.LapId] = FullSnapshot(lap.LapId);

        var detail = await _sut.GetMyLapAsync(Me, lap.LapId);

        Assert.Equal(lap.LapId, detail.Lap.LapId);
        Assert.Equal(new TeamRefDto("McLaren", "#FF8000"), detail.Lap.Team);
        Assert.Equal("Overcast", detail.Lap.Weather);
        Assert.True(detail.Lap.HasTrace);
        Assert.Equal("DriverCareer", detail.Lap.GameMode);
        Assert.Equal(Jeddah, detail.TrackId);
        Assert.Equal("SA", detail.CountryCode);

        var car = Assert.IsType<LapCarSnapshotDto>(detail.Car);
        Assert.Equal(16, car.VisualTyreCompound);
        Assert.Equal(new WheelValuesDto(27, 14, 20, 15), car.TyreWearStart);
        Assert.Equal(new WheelValuesDto(31, 18, 24, 19), car.TyreWearEnd);
        Assert.Equal(new WheelValuesDto(5, 6, 7, 8), car.TyreDamage);
        Assert.Equal(new WheelValuesDto(1, 2, 3, 4), car.BrakeDamage);
        Assert.Equal(10, car.FrontRightWingDamage);
        Assert.Equal(30, car.EngineDamage);
        Assert.Equal(22.7, car.FuelEndKg);
        Assert.Equal(-0.5, car.FuelRemainingLaps);
        Assert.Equal(1_600_000d, car.ErsHarvestedJ);
        Assert.Equal(new LapConditionsDto("Overcast", 21, 31, 4), detail.Conditions);
    }

    [Fact]
    public async Task Detail_WithoutSnapshot_HasNullCarAndConditions()
    {
        var lap = AddLap(Me, 98_448);

        var detail = await _sut.GetMyLapAsync(Me, lap.LapId);

        Assert.Null(detail.Car);
        Assert.Null(detail.Conditions);
        Assert.Null(detail.Lap.Team);
    }

    [Fact]
    public async Task Detail_ConditionsOnlySnapshot_HasNullCar()
    {
        var lap = AddLap(Me, 98_448);
        _laps.Snapshots[lap.LapId] = new LapSnapshot { LapId = lap.LapId, Weather = Weather.Storm };

        var detail = await _sut.GetMyLapAsync(Me, lap.LapId);

        Assert.Null(detail.Car);
        Assert.Equal(new LapConditionsDto("Storm", null, null, null), detail.Conditions);
    }

    [Fact]
    public async Task Detail_CarOnlySnapshot_WithPartialWheels_HasNullWheelGroup()
    {
        var lap = AddLap(Me, 98_448);
        _laps.Snapshots[lap.LapId] = new LapSnapshot
        {
            LapId = lap.LapId,
            TyreWearEndFrontLeft = 10, TyreWearEndFrontRight = 10, TyreWearEndRearLeft = 10, // RearRight 없음
            EngineDamage = 0,
        };

        var detail = await _sut.GetMyLapAsync(Me, lap.LapId);

        var car = Assert.IsType<LapCarSnapshotDto>(detail.Car);
        Assert.Null(car.TyreWearEnd);
        Assert.Equal(0, car.EngineDamage);
        Assert.Null(detail.Conditions);
    }

    [Fact]
    public async Task Detail_Comparison_IsFastestValidLapOnSameTrack()
    {
        var current = AddLap(Me, 98_448, setAt: T0.AddMinutes(10));
        AddLap(Me, 95_000, isValid: false);                       // 더 빠르지만 무효 → 제외
        AddLap(Me, 96_000, trackId: Monza);                       // 다른 트랙 → 제외
        AddLap(Other, 90_000);                                     // 남의 랩 → 제외
        var best = AddLap(Me, 97_003, setAt: T0.AddMinutes(5), hasTrace: true);
        AddLap(Me, 97_003, setAt: T0.AddMinutes(7));               // 같은 시간이면 먼저 세운 랩

        var detail = await _sut.GetMyLapAsync(Me, current.LapId);

        var comparison = Assert.IsType<LapComparisonDto>(detail.Comparison);
        Assert.Equal(best.LapId, comparison.LapId);
        Assert.Equal(97_003, comparison.LapTimeMs);
        Assert.Equal(best.SetAt, comparison.SetAt);
        Assert.True(comparison.HasTrace);
        Assert.Equal(best.Sectors, comparison.Sectors);
    }

    [Fact]
    public async Task Detail_Comparison_CanBeTheLapItself()
    {
        var current = AddLap(Me, 97_003);
        AddLap(Me, 98_000);

        var detail = await _sut.GetMyLapAsync(Me, current.LapId);

        Assert.Equal(current.LapId, detail.Comparison!.LapId);
    }

    [Fact]
    public async Task Detail_NoValidLapOnTrack_ComparisonIsNull()
    {
        var current = AddLap(Me, 97_003, isValid: false);

        var detail = await _sut.GetMyLapAsync(Me, current.LapId);

        Assert.Null(detail.Comparison);
    }

    [Fact]
    public async Task Detail_SessionId_FromSameSessionKey()
    {
        var sessionId = Guid.NewGuid();
        _sessions.Sessions[(Me, GameCode, SessionKey)] = sessionId;
        var linked = AddLap(Me, 97_003, sessionKey: SessionKey);
        var unlinked = AddLap(Me, 97_100, sessionKey: "uid:999");

        Assert.Equal(sessionId, (await _sut.GetMyLapAsync(Me, linked.LapId)).SessionId);
        Assert.Null((await _sut.GetMyLapAsync(Me, unlinked.LapId)).SessionId);
    }

    [Fact]
    public async Task Detail_WithoutSessionKey_DoesNotLookUpSession()
    {
        var lap = AddLap(Me, 97_003, sessionKey: null);

        var detail = await _sut.GetMyLapAsync(Me, lap.LapId);

        Assert.Null(detail.SessionId);
        Assert.Equal(0, _sessions.CallCount);
    }

    [Fact]
    public async Task Detail_OtherUsersLapOrUnknown_IsNotFound()
    {
        var others = AddLap(Other, 97_003);

        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMyLapAsync(Me, others.LapId));
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMyLapAsync(Me, Guid.NewGuid()));
    }

    [Fact]
    public async Task Trace_RestoresChannels()
    {
        var lap = AddLap(Me, 97_003, hasTrace: true);
        var channels = new LapTraceChannels([0, 80, 160], [100, 120, 140], [100, 100, 90], [0, 0, 20], [-5, 0, 5], [6, 7, 7], [11_000, 11_500, 11_200]);
        _laps.Traces[lap.LapId] = new LapTelemetryTrace
        {
            LapId = lap.LapId, ResolutionM = 5, SampleCount = 3, Payload = LapTraceCodec.Encode(channels),
        };

        var trace = await _sut.GetMyLapTraceAsync(Me, lap.LapId);

        Assert.Equal(lap.LapId, trace.LapId);
        Assert.Equal(5, trace.ResolutionM);
        Assert.Equal(3, trace.SampleCount);
        Assert.Equal(channels.TimeMs, trace.TimeMs);
        Assert.Equal(channels.SpeedKph, trace.SpeedKph);
        Assert.Equal(channels.Throttle, trace.Throttle);
        Assert.Equal(channels.Brake, trace.Brake);
        Assert.Equal(channels.Steer, trace.Steer);
        Assert.Equal(channels.Gear, trace.Gear);
        Assert.Equal(channels.Rpm, trace.Rpm);
    }

    [Fact]
    public async Task Trace_MissingOrOtherUsers_IsNotFound()
    {
        var withoutTrace = AddLap(Me, 97_003);
        var others = AddLap(Other, 97_003, hasTrace: true);
        _laps.Traces[others.LapId] = new LapTelemetryTrace { LapId = others.LapId, ResolutionM = 5, SampleCount = 0 };

        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMyLapTraceAsync(Me, withoutTrace.LapId));
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetMyLapTraceAsync(Me, others.LapId));
    }

    [Fact]
    public async Task Trace_CorruptPayload_Throws()
    {
        var lap = AddLap(Me, 97_003, hasTrace: true);
        _laps.Traces[lap.LapId] = new LapTelemetryTrace { LapId = lap.LapId, ResolutionM = 5, SampleCount = 1, Payload = [9, 9, 9] };

        await Assert.ThrowsAsync<InvalidDataException>(() => _sut.GetMyLapTraceAsync(Me, lap.LapId));
    }

    private static LapSnapshot FullSnapshot(Guid lapId) => new()
    {
        LapId = lapId,
        TeamId = 8,
        VisualTyreCompound = 16, ActualTyreCompound = 18, TyreAgeLaps = 3,
        TyreWearStartFrontLeft = 27, TyreWearStartFrontRight = 14, TyreWearStartRearLeft = 20, TyreWearStartRearRight = 15,
        TyreWearEndFrontLeft = 31, TyreWearEndFrontRight = 18, TyreWearEndRearLeft = 24, TyreWearEndRearRight = 19,
        TyreDamageFrontLeft = 5, TyreDamageFrontRight = 6, TyreDamageRearLeft = 7, TyreDamageRearRight = 8,
        BrakeDamageFrontLeft = 1, BrakeDamageFrontRight = 2, BrakeDamageRearLeft = 3, BrakeDamageRearRight = 4,
        FrontLeftWingDamage = 0, FrontRightWingDamage = 10, RearWingDamage = 0, FloorDamage = 0,
        DiffuserDamage = 0, SidepodDamage = 20, GearboxDamage = 10, EngineDamage = 30,
        FuelStartKg = 24.4, FuelEndKg = 22.7, FuelRemainingLaps = -0.5,
        ErsStoreStartJ = 1_494_000, ErsStoreEndJ = 988_000, ErsDeployedJ = 2_100_000, ErsHarvestedJ = 1_600_000,
        Weather = Weather.Overcast, AirTempC = 21, TrackTempC = 31, RainForecastPercent = 4,
    };

    /// <summary>세션 ID 조회만 구현한다.</summary>
    private sealed class FakeSessionLookup : IGameSessionQueryRepository
    {
        public Dictionary<(Guid UserId, string GameCode, string SessionKey), Guid> Sessions { get; } = new();
        public int CallCount { get; private set; }

        public Task<Guid?> FindMySessionIdAsync(
            Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
        {
            CallCount++;
            return Task.FromResult(Sessions.TryGetValue((userId, gameCode, sessionKey), out var id) ? id : (Guid?)null);
        }

        public Task<(IReadOnlyList<SessionSummaryRow> Items, int Total)> GetMyPageAsync(
            Guid userId, SessionType? sessionType, int skip, int take, CancellationToken cancellationToken = default)
            => throw new NotImplementedException();

        public Task<GameSession?> GetMineDetailAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
            => throw new NotImplementedException();
    }
}
