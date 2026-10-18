using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Outbox;
using SimCenter.Agent.Infrastructure.Sinks;
using Xunit.Abstractions;

namespace SimCenter.Agent.Infrastructure.Tests;

/// <summary>
/// LapFinished의 랩 상세 필드(docs/15 §4.3) wire JSON 계약과, 봉투 한도를 넘을 때의 트레이스 대체 순서(5m → 10m → 20m → 트레이스 제거, D-45)를
/// 실제 <see cref="OutboxTelemetrySink"/>로 고정한다. 크기는 싱크가 Outbox에 넣은 JSON의 UTF-8 바이트를 잰다.
/// </summary>
public sealed class OutboxTelemetrySinkLapDetailTests : IAsyncLifetime
{
    private const int TraceResolutionM = 5;
    private const int LargeValue = 1_000_000;            // 7자리 + 쉼표 = 칸마다 8바이트
    private const int WireBytesPerLargeSample = 7 * 8;   // 채널 7개
    private const int OversizedSectorCount = 5000;
    private const int SpaLengthM = 7004;
    private const int SpaLapTimeMs = 106_000;

    private static readonly DateTime OccurredAt = new(2026, 10, 18, 9, 0, 0, DateTimeKind.Utc);

    private readonly ITestOutputHelper _output;
    private readonly CapturingLogger<OutboxTelemetrySink> _logger = new();
    private readonly TelemetryOutbox _outbox = new(Options.Create(new AgentOptions { OutboxPath = ":memory:" }));
    private readonly OutboxTelemetrySink _sut;

    public OutboxTelemetrySinkLapDetailTests(ITestOutputHelper output)
    {
        _output = output;
        _sut = new OutboxTelemetrySink(_outbox, _logger);
    }

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync() => await _outbox.DisposeAsync();

    [Fact]
    public async Task LapFinished_WireJson_UsesContractPropertyNames()
    {
        await _sut.EmitAsync(Envelope(Lap(Snapshot(), new LapConditions(Weather.LightRain, 21, 31, 4), Trace(4, value: 7))));

        var json = await SingleOutboxJsonAsync();
        _output.WriteLine(json);
        using var doc = JsonDocument.Parse(json);
        var payload = doc.RootElement.GetProperty("payload");

        var car = payload.GetProperty("car");
        Assert.Equal(
            new[]
            {
                "teamId", "visualTyreCompound", "actualTyreCompound", "tyreAgeLaps", "tyreWearStart", "tyreWearEnd",
                "tyreDamage", "brakeDamage", "frontLeftWingDamage", "frontRightWingDamage", "rearWingDamage", "floorDamage",
                "diffuserDamage", "sidepodDamage", "gearboxDamage", "engineDamage", "fuelStartKg", "fuelEndKg",
                "fuelRemainingLaps", "ersStoreStartJ", "ersStoreEndJ", "ersDeployedJ", "ersHarvestedJ", "details",
            }.Order(),
            Names(car).Order());
        foreach (var wheels in new[] { "tyreWearStart", "tyreWearEnd", "tyreDamage", "brakeDamage" })
        {
            Assert.Equal(new[] { "frontLeft", "frontRight", "rearLeft", "rearRight" }.Order(), Names(car.GetProperty(wheels)).Order());
        }

        Assert.Equal(1, car.GetProperty("teamId").GetInt32());
        Assert.Equal(27.5, car.GetProperty("tyreWearStart").GetProperty("frontLeft").GetDouble());
        Assert.Equal(24.4, car.GetProperty("fuelStartKg").GetDouble(), precision: 4);
        Assert.Equal(1_494_000, car.GetProperty("ersStoreStartJ").GetInt32());   // 줄은 정수 J

        var conditions = payload.GetProperty("conditions");
        Assert.Equal(new[] { "weather", "airTempC", "trackTempC", "rainForecastPercent" }.Order(), Names(conditions).Order());
        Assert.Equal("LightRain", conditions.GetProperty("weather").GetString());   // enum은 문자열
        Assert.Equal(21, conditions.GetProperty("airTempC").GetInt32());

        var trace = payload.GetProperty("trace");
        Assert.Equal(
            new[] { "resolutionM", "timeMs", "speedKph", "throttle", "brake", "steer", "gear", "rpm", "extra" }.Order(),
            Names(trace).Order());
        Assert.Equal(TraceResolutionM, trace.GetProperty("resolutionM").GetInt32());
        Assert.Equal(new[] { 7, 7, 7, 7 }, trace.GetProperty("gear").EnumerateArray().Select(v => v.GetInt32()));
    }

    [Fact]
    public async Task LapFinished_WithoutDetail_WritesNulls()
    {
        await _sut.EmitAsync(Envelope(Lap(car: null, conditions: null, trace: null)));

        using var doc = JsonDocument.Parse(await SingleOutboxJsonAsync());
        var payload = doc.RootElement.GetProperty("payload");
        Assert.Equal(JsonValueKind.Null, payload.GetProperty("car").ValueKind);
        Assert.Equal(JsonValueKind.Null, payload.GetProperty("conditions").ValueKind);
        Assert.Equal(JsonValueKind.Null, payload.GetProperty("trace").ValueKind);
    }

    [Fact]
    public async Task TraceExtra_IsWrittenAsNameToNumberArrayMap_WithNamesUnchanged()
    {
        var extra = new Dictionary<string, IReadOnlyList<double>>
        {
            ["tyreSurfaceTempFL"] = new[] { 91d, 92.5, 93d, 94d },
            ["wheelSlipRatioPctRR"] = new[] { -1.25, 0d, 0.5, 2d },
        };

        await _sut.EmitAsync(Envelope(Lap(car: null, conditions: null, Trace(4, value: 7) with { Extra = extra })));

        using var doc = JsonDocument.Parse(await SingleOutboxJsonAsync());
        var wire = doc.RootElement.GetProperty("payload").GetProperty("trace").GetProperty("extra");
        Assert.Equal(new[] { "tyreSurfaceTempFL", "wheelSlipRatioPctRR" }, Names(wire));   // 사전 키는 바꾸지 않는다(이미 camelCase)
        Assert.Equal(new[] { 91, 92.5, 93, 94 }, wire.GetProperty("tyreSurfaceTempFL").EnumerateArray().Select(v => v.GetDouble()));
        Assert.Equal("[-1.25,0,0.5,2]", wire.GetProperty("wheelSlipRatioPctRR").GetRawText());
    }

    [Fact]
    public async Task CarDetails_AreWrittenAsNestedObjects_WithEventsAndSessionHistory()
    {
        var details = new Dictionary<string, object?>
        {
            ["setup"] = new Dictionary<string, object?> { ["frontWing"] = (byte)30, ["tyrePressureFL"] = 22.3, ["fuelLoad"] = null },
            ["tyreSets"] = new Dictionary<string, object?> { ["sets"] = new object?[] { new Dictionary<string, object?> { ["fitted"] = true } } },
            ["events"] = new[] { new LapEventEntry("PENA", 15_250, new Dictionary<string, object?> { ["penaltyType"] = 5 }) },
            ["sessionHistory"] = new LapHistoryEntry(5, 83_452, 27_010, 30_110, 26_332, true, true, true, false),
        };

        await _sut.EmitAsync(Envelope(Lap(Snapshot() with { Details = details }, conditions: null, trace: null)));

        var json = await SingleOutboxJsonAsync();
        _output.WriteLine(json);
        using var doc = JsonDocument.Parse(json);
        var wire = doc.RootElement.GetProperty("payload").GetProperty("car").GetProperty("details");
        Assert.Equal(30, wire.GetProperty("setup").GetProperty("frontWing").GetInt32());
        Assert.Equal(22.3, wire.GetProperty("setup").GetProperty("tyrePressureFL").GetDouble());
        Assert.Equal(JsonValueKind.Null, wire.GetProperty("setup").GetProperty("fuelLoad").ValueKind);
        Assert.True(wire.GetProperty("tyreSets").GetProperty("sets")[0].GetProperty("fitted").GetBoolean());
        var penalty = Assert.Single(wire.GetProperty("events").EnumerateArray());
        Assert.Equal(new[] { "code", "lapTimeMs", "details" }, Names(penalty));
        Assert.Equal("PENA", penalty.GetProperty("code").GetString());
        Assert.Equal(15_250, penalty.GetProperty("lapTimeMs").GetInt32());
        Assert.Equal(5, penalty.GetProperty("details").GetProperty("penaltyType").GetInt32());
        var history = wire.GetProperty("sessionHistory");
        Assert.Equal(
            new[] { "lapNumber", "lapTimeMs", "sector1TimeMs", "sector2TimeMs", "sector3TimeMs", "lapValid", "sector1Valid", "sector2Valid", "sector3Valid" },
            Names(history));
        Assert.False(history.GetProperty("sector3Valid").GetBoolean());
    }

    [Fact]
    public async Task CarSnapshot_MissingFields_AreWrittenAsNull()
    {
        var car = Snapshot() with { FuelStartKg = null, TyreWearStart = null, TeamId = null };

        await _sut.EmitAsync(Envelope(Lap(car, conditions: null, trace: null)));

        using var doc = JsonDocument.Parse(await SingleOutboxJsonAsync());
        var wire = doc.RootElement.GetProperty("payload").GetProperty("car");
        Assert.Equal(JsonValueKind.Null, wire.GetProperty("fuelStartKg").ValueKind);
        Assert.Equal(JsonValueKind.Null, wire.GetProperty("tyreWearStart").ValueKind);
        Assert.Equal(JsonValueKind.Null, wire.GetProperty("teamId").ValueKind);
    }

    [Theory]
    [InlineData(1_200, 10, 600)]    // 5m로는 넘고 10m면 들어간다
    [InlineData(2_400, 20, 600)]    // 10m로도 넘고 20m면 들어간다
    public async Task OversizedTrace_IsDownsampledUntilItFits(int samples, int expectedResolutionM, int expectedSamples)
    {
        var lap = Lap(Snapshot(), conditions: null, Trace(samples, LargeValue));
        Assert.True(samples * WireBytesPerLargeSample > OutboxTelemetrySink.MaxEnvelopeBytes, "전제: 5m 트레이스는 한도 초과");

        await _sut.EmitAsync(Envelope(lap));

        var json = await SingleOutboxJsonAsync();
        Assert.True(Utf8Bytes(json) <= OutboxTelemetrySink.MaxEnvelopeBytes, $"{Utf8Bytes(json)} bytes");
        using var doc = JsonDocument.Parse(json);
        var trace = doc.RootElement.GetProperty("payload").GetProperty("trace");
        Assert.Equal(expectedResolutionM, trace.GetProperty("resolutionM").GetInt32());
        Assert.Equal(expectedSamples, trace.GetProperty("timeMs").GetArrayLength());
        Assert.Equal(expectedSamples, trace.GetProperty("rpm").GetArrayLength());
        Assert.DoesNotContain(_logger.Entries, e => e.Level >= LogLevel.Warning);
    }

    [Fact]
    public async Task OversizedTraceEvenAt20m_IsDropped_AndLapIsStillEnqueued()
    {
        var lap = Lap(Snapshot(), new LapConditions(Weather.Clear, 21, 31, null), Trace(5_000, LargeValue));

        await _sut.EmitAsync(Envelope(lap));

        using var doc = JsonDocument.Parse(await SingleOutboxJsonAsync());
        var payload = doc.RootElement.GetProperty("payload");
        Assert.Equal(JsonValueKind.Null, payload.GetProperty("trace").ValueKind);
        Assert.Equal(83_452, payload.GetProperty("lapTimeMs").GetInt32());              // 랩은 그대로
        Assert.Equal(JsonValueKind.Object, payload.GetProperty("car").ValueKind);        // 스냅샷도 그대로
        var warning = Assert.Single(_logger.Entries, e => e.Level >= LogLevel.Warning);
        Assert.Equal(LogLevel.Warning, warning.Level);
    }

    [Fact]
    public async Task OversizedLapEvenWithoutTrace_IsDropped()
    {
        var sectors = Enumerable.Range(1, OversizedSectorCount).Select(n => new LapSectorDto(n, 30_000)).ToArray();
        var lap = Lap(Snapshot(), conditions: null, Trace(4, value: 1)) with { Sectors = sectors };

        await _sut.EmitAsync(Envelope(lap));

        Assert.Equal(0, await _outbox.CountAsync());
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Error);
    }

    [Fact]
    public async Task RealisticSpaLapAt5m_FitsUnderLimit()
    {
        // Spa(약 7km) 1랩 5m = 1,401칸, 채널마다 게임에서 나올 법한 자릿수(시간 6자리, RPM 5자리, 스티어 음수 포함).
        var samples = (SpaLengthM / TraceResolutionM) + 1;
        var lap = Lap(Snapshot(), new LapConditions(Weather.Overcast, 18, 27, 35), RealisticTrace(samples));

        await _sut.EmitAsync(Envelope(lap));

        var json = await SingleOutboxJsonAsync();
        var bytes = Utf8Bytes(json);
        _output.WriteLine($"Spa 7,004m @5m ({samples} samples) LapFinished envelope: {bytes} bytes (limit {OutboxTelemetrySink.MaxEnvelopeBytes})");
        Assert.True(bytes <= OutboxTelemetrySink.MaxEnvelopeBytes, $"{bytes} bytes");
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(TraceResolutionM, doc.RootElement.GetProperty("payload").GetProperty("trace").GetProperty("resolutionM").GetInt32());
        Assert.Empty(_logger.Entries);
    }

    // ---- 헬퍼 ----

    private static TelemetryEnvelope Envelope(LapFinished payload) =>
        new(Guid.NewGuid(), "F1_25", OccurredAt, TelemetryEventType.LapFinished, payload);

    private static LapFinished Lap(LapCarSnapshot? car, LapConditions? conditions, LapTrace? trace) => new(
        SessionRef: "1844674407370955161",
        LapNumber: 5,
        LapTimeMs: 83_452,
        Sectors: [new LapSectorDto(1, 27_010), new LapSectorDto(2, 30_110), new LapSectorDto(3, 26_332)],
        IsValid: true,
        IsOutOrInLap: false,
        TrackId: 10,
        SessionType: SessionType.TimeTrial,
        GameMode: GameMode.TimeTrial,
        Car: car,
        Conditions: conditions,
        Trace: trace);

    private static LapCarSnapshot Snapshot() => new(
        TeamId: 1,
        VisualTyreCompound: 16,
        ActualTyreCompound: 18,
        TyreAgeLaps: 3,
        TyreWearStart: new WheelSet<float>(27.5f, 14f, 20f, 14f),
        TyreWearEnd: new WheelSet<float>(31f, 18f, 24f, 18f),
        TyreDamage: new WheelSet<int>(0, 0, 0, 0),
        BrakeDamage: new WheelSet<int>(0, 0, 0, 0),
        FrontLeftWingDamage: 0,
        FrontRightWingDamage: 10,
        RearWingDamage: 0,
        FloorDamage: 0,
        DiffuserDamage: 0,
        SidepodDamage: 20,
        GearboxDamage: 10,
        EngineDamage: 30,
        FuelStartKg: 24.4f,
        FuelEndKg: 22.7f,
        FuelRemainingLaps: 13.1f,
        ErsStoreStartJ: 1_494_000,
        ErsStoreEndJ: 988_000,
        ErsDeployedJ: 2_100_000,
        ErsHarvestedJ: 1_600_000);

    private static LapTrace Trace(int samples, int value)
    {
        var channel = Enumerable.Repeat(value, samples).ToArray();
        return new LapTrace(TraceResolutionM, channel, channel, channel, channel, channel, channel, channel);
    }

    /// <summary>자릿수가 실제와 비슷한 1랩 트레이스(시간 0~106초, 속도 80~340, RPM 9,000~12,500, 스티어 −100~100).</summary>
    private static LapTrace RealisticTrace(int samples)
    {
        int[] Channel(Func<int, int> value) => Enumerable.Range(0, samples).Select(value).ToArray();
        return new LapTrace(
            TraceResolutionM,
            TimeMs: Channel(i => i * SpaLapTimeMs / samples),
            SpeedKph: Channel(i => 80 + (i * 37 % 261)),
            Throttle: Channel(i => i % 9 == 0 ? 0 : 100 - (i * 7 % 60)),
            Brake: Channel(i => i % 9 == 0 ? 100 - (i % 30) : 0),
            Steer: Channel(i => (i * 13 % 201) - 100),
            Gear: Channel(i => 2 + (i % 7)),
            Rpm: Channel(i => 9_000 + (i * 31 % 3_500)));
    }

    private static IEnumerable<string> Names(JsonElement element) => element.EnumerateObject().Select(p => p.Name);

    private async Task<string> SingleOutboxJsonAsync()
    {
        var pending = await _outbox.GetPendingAsync(max: 10);
        return Assert.Single(pending).PayloadJson;
    }

    private static int Utf8Bytes(string json) => Encoding.UTF8.GetByteCount(json);

    private sealed class CapturingLogger<T> : ILogger<T>
    {
        public List<(LogLevel Level, string Message)> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Entries.Add((logLevel, formatter(state, exception)));
    }
}
