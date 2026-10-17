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
/// 싱크가 만든 wire JSON의 계약(camelCase·문자열 enum·null 기록)과 크기 검사(12 §5.5)를 실제 <see cref="OutboxTelemetrySink"/>로 고정한다.
/// 크기는 추정이 아니라 싱크가 Outbox에 넣은 JSON의 UTF-8 바이트를 잰다.
/// </summary>
public sealed class OutboxTelemetrySinkSizeTests : IAsyncLifetime
{
    private const int MaxCars = 24;
    private const int MaxTyreStints = 8;
    private const int RealisticNameLength = 10;
    private const int ValidationMaxNameLength = 64;       // 백엔드 MaxDriverNameLength
    private const int ValidationMaxActualCompoundLength = 10;   // 백엔드 MaxActualCompoundLength
    private const int OversizedCompoundLength = 200;
    private const int OversizedNameLength = 400;
    private const int OversizedSectorCount = 5000;
    private const string NonAsciiChar = "가";                 // 기본 인코더는 \uXXXX(6바이트)로 escape한다

    private static readonly DateTime OccurredAt = new(2026, 10, 17, 9, 0, 0, DateTimeKind.Utc);

    private readonly ITestOutputHelper _output;
    private readonly CapturingLogger<OutboxTelemetrySink> _logger = new();
    private readonly TelemetryOutbox _outbox = new(Options.Create(new AgentOptions { OutboxPath = ":memory:" }));
    private readonly OutboxTelemetrySink _sut;

    public OutboxTelemetrySinkSizeTests(ITestOutputHelper output)
    {
        _output = output;
        _sut = new OutboxTelemetrySink(_outbox, _logger);
    }

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync() => await _outbox.DisposeAsync();

    [Fact]
    public async Task SessionClassified_IsCamelCaseWithStringEnums()
    {
        var stints = new[]
        {
            new TyreStint(14, TyreCompound.Medium, "C3"),
            new TyreStint(29, TyreCompound.Hard, null),
        };
        var payload = Classified(
            Result(carIndex: 3, name: "S. LIM", stints: stints) with
            {
                IsPlayer = true,
                GameDriverId = null,
                ResultStatus = ResultStatus.Finished,
            });

        await _sut.EmitAsync(Envelope(payload));

        using var doc = JsonDocument.Parse(await SingleOutboxJsonAsync());
        var root = doc.RootElement;
        Assert.Equal("SessionClassified", root.GetProperty("type").GetString());

        var p = root.GetProperty("payload");
        Assert.Equal("SessionClassified", p.GetProperty("type").GetString());   // 베이스 속성이 기존 이벤트처럼 함께 실린다
        Assert.Equal("Race", p.GetProperty("sessionType").GetString());
        Assert.Equal("Race", p.GetProperty("sessionKind").GetString());
        Assert.Equal("DriverCareer", p.GetProperty("gameMode").GetString());
        Assert.Equal(2_847_561_234L, p.GetProperty("seasonLinkId").GetInt64());   // uint > int.MaxValue
        Assert.Equal(99_112_233L, p.GetProperty("weekendLinkId").GetInt64());
        Assert.Equal(44_556_677L, p.GetProperty("sessionLinkId").GetInt64());
        Assert.Equal(29, p.GetProperty("totalLaps").GetInt32());
        Assert.False(p.GetProperty("isNetworkGame").GetBoolean());

        var result = Assert.Single(p.GetProperty("results").EnumerateArray());
        Assert.Equal(3, result.GetProperty("carIndex").GetInt32());
        Assert.True(result.GetProperty("isPlayer").GetBoolean());
        Assert.Equal("Finished", result.GetProperty("resultStatus").GetString());
        Assert.Equal("S. LIM", result.GetProperty("driverName").GetString());
        Assert.Equal(JsonValueKind.Null, result.GetProperty("gameDriverId").ValueKind);   // null도 기록된다
        Assert.Equal(26, result.GetProperty("raceNumber").GetInt32());

        var wireStints = result.GetProperty("tyreStints");
        Assert.Equal(2, wireStints.GetArrayLength());
        Assert.Equal(14, wireStints[0].GetProperty("endLap").GetInt32());
        Assert.Equal("Medium", wireStints[0].GetProperty("visualCompound").GetString());
        Assert.Equal("C3", wireStints[0].GetProperty("actualCompound").GetString());
        Assert.Equal("Hard", wireStints[1].GetProperty("visualCompound").GetString());
        Assert.Equal(JsonValueKind.Null, wireStints[1].GetProperty("actualCompound").ValueKind);
    }

    [Fact]
    public async Task LapFinished_CarriesSeasonLinkFields_AsNumbersAndModeString()
    {
        var payload = new LapFinished(
            "s", 4, 83_452, [new LapSectorDto(1, 27_010)], true, false, 7, SessionType.Race,
            GameMode.MyTeamCareer, 2_847_561_234, 99_112_233, 44_556_677);

        await _sut.EmitAsync(new TelemetryEnvelope(Guid.NewGuid(), "F1_25", OccurredAt, TelemetryEventType.LapFinished, payload));

        using var doc = JsonDocument.Parse(await SingleOutboxJsonAsync());
        var p = doc.RootElement.GetProperty("payload");
        Assert.Equal("MyTeamCareer", p.GetProperty("gameMode").GetString());
        Assert.Equal(2_847_561_234L, p.GetProperty("seasonLinkId").GetInt64());
        Assert.Equal(99_112_233L, p.GetProperty("weekendLinkId").GetInt64());
        Assert.Equal(44_556_677L, p.GetProperty("sessionLinkId").GetInt64());
    }

    [Fact]
    public async Task MaxRealisticPayload_IsEnqueued_UnderLimit()
    {
        // 24대 × 스틴트 8개, 이름이 모두 비ASCII(escape되어 글자당 6바이트).
        var payload = Classified(Cars(MaxCars, nameLength: RealisticNameLength, stints: LongestLabelStints(MaxTyreStints)));

        await _sut.EmitAsync(Envelope(payload));

        var json = await SingleOutboxJsonAsync();
        var bytes = Utf8Bytes(json);
        _output.WriteLine($"realistic max payload (24 cars x 8 stints, {RealisticNameLength} non-ASCII chars): {bytes} bytes");
        Assert.True(bytes <= OutboxTelemetrySink.MaxEnvelopeBytes, $"{bytes} bytes");
        Assert.Equal(MaxCars * MaxTyreStints, CountStints(json));   // 스틴트는 그대로 남아 있다
        Assert.Empty(_logger.Entries);
    }

    [Fact]
    public async Task ValidationMaxPayload_RealWireSize_IsMeasuredAndEnqueued()
    {
        // 검증 한도 끝까지: 24대 × 스틴트 8개 × 이름 64자(비ASCII) × 컴파운드 라벨 10자.
        var payload = Classified(Cars(MaxCars, nameLength: ValidationMaxNameLength, stints: LongestLabelStints(MaxTyreStints)));

        await _sut.EmitAsync(Envelope(payload));

        var json = await SingleOutboxJsonAsync();
        var bytes = Utf8Bytes(json);
        _output.WriteLine($"validation max payload (24 cars x 8 stints, {ValidationMaxNameLength} non-ASCII chars): {bytes} bytes");
        Assert.True(bytes <= OutboxTelemetrySink.MaxEnvelopeBytes, $"{bytes} bytes");
        Assert.Equal(MaxCars * MaxTyreStints, CountStints(json));
    }

    [Fact]
    public async Task OversizedSessionClassified_IsEnqueuedWithoutStints()
    {
        // 이름은 짧고 스틴트만으로 한도를 넘는다(컴파운드 라벨이 비정상적으로 긴 경우).
        var stints = Enumerable.Range(0, MaxTyreStints)
            .Select(lap => new TyreStint(lap + 1, TyreCompound.Hard, new string('C', OversizedCompoundLength)))
            .ToArray();
        var payload = Classified(Cars(MaxCars, nameLength: RealisticNameLength, stints: stints));
        Assert.True(Utf8Bytes(Serialize(payload)) > OutboxTelemetrySink.MaxEnvelopeBytes, "전제: 스틴트 포함 시 한도 초과");

        await _sut.EmitAsync(Envelope(payload));

        var json = await SingleOutboxJsonAsync();
        var bytes = Utf8Bytes(json);
        _output.WriteLine($"oversized payload after dropping stints: {bytes} bytes");
        Assert.True(bytes <= OutboxTelemetrySink.MaxEnvelopeBytes, $"{bytes} bytes");

        using var doc = JsonDocument.Parse(json);
        var results = doc.RootElement.GetProperty("payload").GetProperty("results");
        Assert.Equal(MaxCars, results.GetArrayLength());
        foreach (var result in results.EnumerateArray())
        {
            Assert.Equal(0, result.GetProperty("tyreStints").GetArrayLength());            // tyreStints == []
            Assert.Equal(RealisticNameLength, result.GetProperty("driverName").GetString()!.Length);   // 나머지는 그대로
        }

        var warning = Assert.Single(_logger.Entries);
        Assert.Equal(LogLevel.Warning, warning.Level);
    }

    [Fact]
    public async Task OversizedEvenWithoutStints_IsDropped()
    {
        var payload = Classified(Cars(MaxCars, nameLength: OversizedNameLength, stints: LongestLabelStints(MaxTyreStints)));

        await _sut.EmitAsync(Envelope(payload));

        Assert.Equal(0, await _outbox.CountAsync());
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Error);
    }

    [Fact]
    public async Task OversizedOtherEventType_IsDropped()
    {
        var sectors = Enumerable.Range(1, OversizedSectorCount).Select(n => new LapSectorDto(n, 30_000)).ToArray();
        var payload = new LapFinished("s", 1, 83_000, sectors, true, false, 7, SessionType.TimeTrial);

        await _sut.EmitAsync(new TelemetryEnvelope(Guid.NewGuid(), "F1_25", OccurredAt, TelemetryEventType.LapFinished, payload));

        Assert.Equal(0, await _outbox.CountAsync());
        var error = Assert.Single(_logger.Entries);
        Assert.Equal(LogLevel.Error, error.Level);
    }

    [Fact]
    public async Task NormalSizedEvent_IsEnqueuedWithoutLogs()
    {
        await _sut.EmitAsync(Envelope(Classified(Cars(22, nameLength: RealisticNameLength, stints: LongestLabelStints(3)))));

        Assert.Equal(1, await _outbox.CountAsync());
        Assert.Empty(_logger.Entries);
    }

    // ---- 헬퍼 ----

    private static TelemetryEnvelope Envelope(SessionClassified payload) =>
        new(Guid.NewGuid(), "F1_25", OccurredAt, TelemetryEventType.SessionClassified, payload);

    private static SessionClassified Classified(params ClassifiedResult[] results) => Classified((IReadOnlyList<ClassifiedResult>)results);

    private static SessionClassified Classified(IReadOnlyList<ClassifiedResult> results) => new(
        SessionRef: "1844674407370955161",
        TrackId: 10,
        SessionType: SessionType.Race,
        SessionKind: SessionKind.Race,
        GameMode: GameMode.DriverCareer,
        SeasonLinkId: 2_847_561_234,
        WeekendLinkId: 99_112_233,
        SessionLinkId: 44_556_677,
        TotalLaps: 29,
        AiDifficulty: 85,
        IsNetworkGame: false,
        Results: results);

    private static ClassifiedResult Result(int carIndex, string? name, IReadOnlyList<TyreStint> stints) => new(
        CarIndex: carIndex,
        IsPlayer: false,
        Position: carIndex + 1,
        GridPosition: carIndex + 1,
        NumLaps: 29,
        Points: 25,
        NumPitStops: 1,
        NumPenalties: 0,
        ResultStatus: ResultStatus.Finished,
        BestLapTimeMs: 81_234,
        TotalRaceTimeMs: 2_493_120,
        PenaltiesTimeMs: 0,
        DriverName: name,
        GameDriverId: 9,
        TeamId: 2,
        RaceNumber: 26,
        IsAiControlled: true,
        TyreStints: stints);

    private static IReadOnlyList<ClassifiedResult> Cars(int count, int nameLength, IReadOnlyList<TyreStint> stints) =>
        Enumerable.Range(0, count)
            .Select(carIndex => Result(carIndex, string.Concat(Enumerable.Repeat(NonAsciiChar, nameLength)), stints))
            .ToArray();

    // 가장 긴 enum 문자열(Intermediate)과 검증 한도(10자) 길이의 컴파운드 라벨을 가진 스틴트 n개.
    private static IReadOnlyList<TyreStint> LongestLabelStints(int count) =>
        Enumerable.Range(0, count)
            .Select(lap => new TyreStint(lap + 1, TyreCompound.Intermediate, new string('I', ValidationMaxActualCompoundLength)))
            .ToArray();

    private async Task<string> SingleOutboxJsonAsync()
    {
        var pending = await _outbox.GetPendingAsync(max: 10);
        return Assert.Single(pending).PayloadJson;
    }

    private static int Utf8Bytes(string json) => Encoding.UTF8.GetByteCount(json);

    // 싱크와 같은 옵션·같은 봉투 모양으로 직렬화한 크기 — "전제" 확인용(싱크 안에서 어떻게 줄이는지와 무관).
    private static string Serialize(SessionClassified payload) => JsonSerializer.Serialize(
        new { eventId = Guid.NewGuid(), gameCode = "F1_25", occurredAt = OccurredAt, type = "SessionClassified", payload = (object)payload },
        OutboxTelemetrySink.WireJson);

    private static int CountStints(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("payload").GetProperty("results").EnumerateArray()
            .Sum(result => result.GetProperty("tyreStints").GetArrayLength());
    }

    private sealed class CapturingLogger<T> : ILogger<T>
    {
        public List<(LogLevel Level, string Message)> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Entries.Add((logLevel, formatter(state, exception)));
    }
}
