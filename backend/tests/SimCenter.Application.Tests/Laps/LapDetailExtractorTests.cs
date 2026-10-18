using System.Text.Json;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Laps.Ingest;
using SimCenter.Application.Tests.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Laps;

/// <summary>
/// LapFinished 선택 영역 해석(15 §5): 맞는 영역은 저장할 엔티티로, 틀린 영역은 그 영역만 버리고 경고(랩은 언제나 저장).
/// </summary>
public class LapDetailExtractorTests
{
    private static readonly Guid EventId = Guid.Parse("33333333-3333-3333-3333-333333333333");
    private static readonly Guid LapId = Guid.Parse("00000000-0000-0000-0000-00000000aaaa");
    private static readonly DateTime Now = new(2026, 10, 18, 9, 0, 0, DateTimeKind.Utc);

    private readonly ListLogger<LapDetailExtractor> _logger = new();
    private readonly LapDetailExtractor _sut;

    public LapDetailExtractorTests() => _sut = new LapDetailExtractor(new FixedIdGenerator(), _logger);

    private static JsonElement Json(object value) => LapDetailSamples.ToElement(value);

    [Fact]
    public void Snapshot_FromContractShapedJson_MapsEveryField()
    {
        var snapshot = _sut.BuildSnapshot(
            EventId, Json(LapDetailSamples.CarWire()), Json(LapDetailSamples.ConditionsWire()), LapId, Now);

        Assert.NotNull(snapshot);
        Assert.Equal(LapId, snapshot.LapId);
        Assert.Equal(FixedIdGenerator.Id, snapshot.Id);
        Assert.Equal(Now, snapshot.CreatedAt);
        Assert.Equal(1, snapshot.TeamId);
        Assert.Equal((16, 18, 3), (snapshot.VisualTyreCompound, snapshot.ActualTyreCompound, snapshot.TyreAgeLaps));
        // 바퀴 이름이 그대로 열로 간다(FL·FR·RL·RR 순서를 섞지 않는다).
        Assert.Equal((27d, 14d, 20d, 15d), (snapshot.TyreWearStartFrontLeft, snapshot.TyreWearStartFrontRight, snapshot.TyreWearStartRearLeft, snapshot.TyreWearStartRearRight));
        Assert.Equal((31d, 18d, 24d, 19d), (snapshot.TyreWearEndFrontLeft, snapshot.TyreWearEndFrontRight, snapshot.TyreWearEndRearLeft, snapshot.TyreWearEndRearRight));
        Assert.Equal((5d, 6d, 7d, 8d), (snapshot.TyreDamageFrontLeft, snapshot.TyreDamageFrontRight, snapshot.TyreDamageRearLeft, snapshot.TyreDamageRearRight));
        Assert.Equal((1d, 2d, 3d, 4d), (snapshot.BrakeDamageFrontLeft, snapshot.BrakeDamageFrontRight, snapshot.BrakeDamageRearLeft, snapshot.BrakeDamageRearRight));
        Assert.Equal((0, 10, 0, 0), (snapshot.FrontLeftWingDamage, snapshot.FrontRightWingDamage, snapshot.RearWingDamage, snapshot.FloorDamage));
        Assert.Equal((0, 20, 10, 30), (snapshot.DiffuserDamage, snapshot.SidepodDamage, snapshot.GearboxDamage, snapshot.EngineDamage));
        Assert.Equal((24.4, 22.7, 13.1), (snapshot.FuelStartKg, snapshot.FuelEndKg, snapshot.FuelRemainingLaps));
        Assert.Equal((1_494_000d, 988_000d, 2_100_000d, 1_600_000d), (snapshot.ErsStoreStartJ, snapshot.ErsStoreEndJ, snapshot.ErsDeployedJ, snapshot.ErsHarvestedJ));
        Assert.Equal(Weather.Clear, snapshot.Weather);
        Assert.Equal((21, 31, 4), (snapshot.AirTempC, snapshot.TrackTempC, snapshot.RainForecastPercent));
        Assert.Empty(_logger.Warnings);
    }

    [Fact]
    public void Snapshot_NoParts_IsNull_WithoutWarning()
    {
        Assert.Null(_sut.BuildSnapshot(EventId, car: null, conditions: null, LapId, Now));
        Assert.Null(_sut.BuildSnapshot(EventId, JsonNull(), JsonNull(), LapId, Now)); // "car": null
        Assert.Empty(_logger.Warnings);
    }

    [Fact]
    public void Snapshot_InvalidCar_KeepsConditions_AndWarns()
    {
        var badCar = new { fuelStartKg = 500.0, teamId = 1 };

        var snapshot = _sut.BuildSnapshot(EventId, Json(badCar), Json(LapDetailSamples.ConditionsWire()), LapId, Now);

        Assert.NotNull(snapshot);
        Assert.Null(snapshot.TeamId);
        Assert.Null(snapshot.FuelStartKg);
        Assert.False(snapshot.HasCarData());
        Assert.Equal(Weather.Clear, snapshot.Weather);
        var warning = Assert.Single(_logger.Warnings);
        Assert.Contains("car", warning);
        Assert.Contains("fuelStartKg", warning);
        Assert.Contains(EventId.ToString(), warning);
    }

    [Fact]
    public void Snapshot_InvalidConditions_KeepsCar_AndWarns()
    {
        var badConditions = new { weather = "Clear", airTempC = 120 };

        var snapshot = _sut.BuildSnapshot(EventId, Json(LapDetailSamples.CarWire()), Json(badConditions), LapId, Now);

        Assert.NotNull(snapshot);
        Assert.True(snapshot.HasCarData());
        Assert.False(snapshot.HasConditionsData());
        Assert.Contains("conditions", Assert.Single(_logger.Warnings));
    }

    [Fact]
    public void Snapshot_BothInvalid_IsNull()
    {
        var snapshot = _sut.BuildSnapshot(EventId, Json(new { engineDamage = 150 }), Json(new { trackTempC = -60 }), LapId, Now);

        Assert.Null(snapshot);
        Assert.Equal(2, _logger.Warnings.Count());
    }

    [Theory]
    [InlineData("\"oops\"")]                         // 객체가 아님
    [InlineData("[1,2,3]")]                          // 배열
    [InlineData("{\"fuelStartKg\":\"abc\"}")]        // 숫자 자리에 글자
    [InlineData("{\"tyreAgeLaps\":2.5}")]            // 정수 자리에 실수
    [InlineData("{\"tyreWearEnd\":[1,2,3,4]}")]      // 바퀴 묶음 모양이 다름
    public void Snapshot_MalformedCar_IsDiscarded_NotThrown(string carJson)
    {
        var car = JsonDocument.Parse(carJson).RootElement.Clone();

        var snapshot = _sut.BuildSnapshot(EventId, car, conditions: null, LapId, Now);

        Assert.Null(snapshot);
        Assert.Contains("car", Assert.Single(_logger.Warnings));
    }

    [Fact]
    public void Snapshot_UnknownWeather_StoresNullWeather_KeepsRest()
    {
        var conditions = new { weather = "Sandstorm", airTempC = 35, trackTempC = 50, rainForecastPercent = 0 };

        var snapshot = _sut.BuildSnapshot(EventId, car: null, Json(conditions), LapId, Now);

        Assert.NotNull(snapshot);
        Assert.Null(snapshot.Weather);
        Assert.Equal(35, snapshot.AirTempC);
        Assert.Empty(_logger.Warnings);
    }

    [Theory]
    [InlineData("lightRain", Weather.LightRain)]
    [InlineData("HeavyRain", Weather.HeavyRain)]
    [InlineData("STORM", Weather.Storm)]
    public void Snapshot_WeatherName_IsCaseInsensitive(string name, Weather expected)
    {
        var snapshot = _sut.BuildSnapshot(EventId, car: null, Json(new { weather = name }), LapId, Now);

        Assert.Equal(expected, snapshot!.Weather);
    }

    [Fact]
    public void Snapshot_EmptyObjects_AreNull()
    {
        // 영역은 왔지만 값이 하나도 없으면 행을 만들지 않는다.
        Assert.Null(_sut.BuildSnapshot(EventId, Json(new { }), Json(new { }), LapId, Now));
    }

    [Fact]
    public void Trace_Valid_IsCompressedWithResolutionAndCount()
    {
        var trace = _sut.BuildTrace(EventId, Json(LapDetailSamples.TraceWire(samples: 12, resolutionM: 10)), LapId, Now);

        Assert.NotNull(trace);
        Assert.Equal(LapId, trace.LapId);
        Assert.Equal(10, trace.ResolutionM);
        Assert.Equal(12, trace.SampleCount);
        var restored = LapTraceCodec.Decode(trace.Payload);
        var expected = LapDetailSamples.ValidTrace(12, 10);
        Assert.Equal(expected.TimeMs, restored.TimeMs);
        Assert.Equal(expected.Steer, restored.Steer);
        Assert.Equal(expected.Rpm, restored.Rpm);
        Assert.Empty(_logger.Warnings);
    }

    [Fact]
    public void Trace_Missing_IsNull_WithoutWarning()
    {
        Assert.Null(_sut.BuildTrace(EventId, trace: null, LapId, Now));
        Assert.Empty(_logger.Warnings);
    }

    [Fact]
    public void Trace_Invalid_IsDiscarded_AndWarns()
    {
        var bad = new { resolutionM = 5, timeMs = new[] { 0, 100 }, speedKph = new[] { 100 } };

        Assert.Null(_sut.BuildTrace(EventId, Json(bad), LapId, Now));
        Assert.Contains("trace", Assert.Single(_logger.Warnings));
    }

    [Fact]
    public void Trace_Malformed_IsDiscarded_NotThrown()
    {
        var bad = new { resolutionM = "five", timeMs = "nope" };

        Assert.Null(_sut.BuildTrace(EventId, Json(bad), LapId, Now));
        Assert.Single(_logger.Warnings);
    }

    // ── D-49: trace.extra · car.details ──

    [Fact]
    public void Trace_WithExtra_StoresChannelsInBlob()
    {
        var wire = TraceWithExtra(new Dictionary<string, object> { ["clutch"] = Repeat(0.25), ["brakeTempFL"] = Repeat(512.37) });

        var trace = _sut.BuildTrace(EventId, Json(wire), LapId, Now);

        var extra = LapTraceCodec.Decode(trace!.Payload).Extra;
        Assert.NotNull(extra);
        Assert.Equal(Repeat(0.25), extra["clutch"]);
        Assert.Equal(Repeat(512.37), extra["brakeTempFL"]);
        Assert.Empty(_logger.Warnings);
    }

    [Theory]
    [InlineData("{\"bad-name\":[1,1,1,1,1,1,1,1,1,1]}")]       // 이름 규칙 위반
    [InlineData("{\"clutch\":[1,2]}")]                           // 길이 불일치
    [InlineData("{\"clutch\":[1,1,1,1,1,1,1,1,1,\"x\"]}")]      // 숫자가 아님
    [InlineData("[1,2,3]")]                                      // 객체가 아님
    public void Trace_InvalidExtra_KeepsSevenChannels_DropsExtraOnly(string extraJson)
    {
        var wire = TraceWithExtra(JsonDocument.Parse(extraJson).RootElement.Clone());

        var trace = _sut.BuildTrace(EventId, Json(wire), LapId, Now);

        Assert.NotNull(trace);
        var restored = LapTraceCodec.Decode(trace.Payload);
        Assert.Null(restored.Extra);
        Assert.Equal(LapDetailSamples.ValidTrace().TimeMs, restored.TimeMs);
        Assert.Contains("trace.extra", Assert.Single(_logger.Warnings));
    }

    [Fact]
    public void Snapshot_CarDetails_StoredVerbatim()
    {
        const string details = "{\"setup\":{\"frontWing\":5},\"events\":[{\"code\":\"COLL\",\"t\":12.5}]}";
        var car = new { teamId = 1, details = JsonDocument.Parse(details).RootElement.Clone() };

        var snapshot = _sut.BuildSnapshot(EventId, Json(car), conditions: null, LapId, Now);

        Assert.Equal(details, snapshot!.Details);
        Assert.True(snapshot.HasCarData());
        Assert.Empty(_logger.Warnings);
    }

    [Theory]
    [InlineData("[1,2]")]                       // 객체가 아님
    [InlineData("{\"note\":\"a\\u0000b\"}")]    // jsonb가 거부하는 NUL
    public void Snapshot_UnstorableDetails_DropsDetailsOnly(string detailsJson)
    {
        var car = new { teamId = 1, engineDamage = 30, details = JsonDocument.Parse(detailsJson).RootElement.Clone() };

        var snapshot = _sut.BuildSnapshot(EventId, Json(car), conditions: null, LapId, Now);

        Assert.NotNull(snapshot);
        Assert.Null(snapshot.Details);
        Assert.Equal(30, snapshot.EngineDamage);
        Assert.Contains("car.details", Assert.Single(_logger.Warnings));
    }

    [Fact]
    public void Snapshot_OversizedDetails_DropsDetailsOnly()
    {
        var car = new { teamId = 1, engineDamage = 30, details = new { blob = new string('x', LapDetailExtractor.MaxCarDetailsBytes) } };

        var snapshot = _sut.BuildSnapshot(EventId, Json(car), conditions: null, LapId, Now);

        Assert.Null(snapshot!.Details);
        Assert.Contains("크기", Assert.Single(_logger.Warnings));
    }

    // ── D-51: 어시스트 열 ──

    [Fact]
    public void Snapshot_Assists_AreReadFromDetails()
    {
        var car = new
        {
            teamId = 1,
            details = new
            {
                status = new { tractionControl = 2, antiLockBrakes = 1 },
                session = new { steeringAssist = 1, brakingAssist = 3, gearboxAssist = 3, dynamicRacingLine = 2 },
            },
        };

        var snapshot = _sut.BuildSnapshot(EventId, Json(car), conditions: null, LapId, Now);

        Assert.Equal(new LapAssistValues(2, 1, 1, 3, 3, 2), LapAssistValues.From(snapshot));
    }

    [Fact]
    public void Snapshot_UnstorableDetails_StillKeepsAssists()
    {
        var car = new
        {
            teamId = 1,
            details = new { status = new { tractionControl = 1 }, blob = new string('x', LapDetailExtractor.MaxCarDetailsBytes) },
        };

        var snapshot = _sut.BuildSnapshot(EventId, Json(car), conditions: null, LapId, Now);

        Assert.Null(snapshot!.Details);
        Assert.Equal(1, snapshot.TractionControl);
    }

    [Fact]
    public void Snapshot_WithoutDetails_HasNoAssists()
    {
        var snapshot = _sut.BuildSnapshot(EventId, Json(new { teamId = 1, engineDamage = 3 }), conditions: null, LapId, Now);

        Assert.Equal(LapAssistValues.Unknown, LapAssistValues.From(snapshot));
    }

    private static double[] Repeat(double value) => Enumerable.Repeat(value, 10).ToArray();

    /// <summary>표본 10개 트레이스 + extra.</summary>
    private static Dictionary<string, object?> TraceWithExtra(object extra)
    {
        var t = LapDetailSamples.ValidTrace();
        return new Dictionary<string, object?>
        {
            ["resolutionM"] = t.ResolutionM,
            ["timeMs"] = t.TimeMs,
            ["speedKph"] = t.SpeedKph,
            ["throttle"] = t.Throttle,
            ["brake"] = t.Brake,
            ["steer"] = t.Steer,
            ["gear"] = t.Gear,
            ["rpm"] = t.Rpm,
            ["extra"] = extra,
        };
    }

    private static JsonElement JsonNull() => JsonDocument.Parse("null").RootElement.Clone();

    private sealed class FixedIdGenerator : IIdGenerator
    {
        public static readonly Guid Id = Guid.Parse("00000000-0000-0000-0000-00000000bbbb");

        public Guid NewId() => Id;
    }
}
