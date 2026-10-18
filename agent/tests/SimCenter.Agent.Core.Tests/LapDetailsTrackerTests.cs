using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

/// <summary>
/// 랩 스냅샷 <c>car.details</c>(D-49, docs/15 §8): 묶음은 최신 값·랩을 넘어 유지, 이벤트는 랩마다 비움·상한, 플레이어 Session History의 그 랩 칸,
/// 값 다듬기(NaN·무한대 → null, 실수 셋째 자리, 모르는 형 → null)와 원본 불변.
/// </summary>
public class LapDetailsTrackerTests
{
    private readonly LapDetailsTracker _sut = new();

    private static CarDetailsFrame Section(string name, params (string Key, object? Value)[] values) =>
        new("s", name, values.ToDictionary(value => value.Key, value => value.Value));

    private static GameEventFrame Event(string code, params (string Key, object? Value)[] details) =>
        new("s", code, details.ToDictionary(detail => detail.Key, detail => detail.Value));

    private static LapHistoryEntry History(int lap, int lapTimeMs) => new(lap, lapTimeMs, 30_000, 30_000, lapTimeMs - 60_000, true, true, true, true);

    private static IReadOnlyDictionary<string, object?> AsSection(object? value) =>
        Assert.IsAssignableFrom<IReadOnlyDictionary<string, object?>>(value);

    [Fact]
    public void Build_NothingReceived_IsNull()
    {
        Assert.Null(_sut.Build(lapNumber: 1));
    }

    [Fact]
    public void Build_SectionsUseLatestValue_AndSurviveLapChange()
    {
        _sut.OnSection(Section("setup", ("frontWing", 10)));
        _sut.OnSection(Section("setup", ("frontWing", 12)));
        _sut.OnSection(Section("damage", ("engineBlown", false)));
        _sut.StartLap();

        var details = _sut.Build(lapNumber: 2)!;

        Assert.Equal(12, AsSection(details["setup"])["frontWing"]);
        Assert.Equal(false, AsSection(details["damage"])["engineBlown"]);
    }

    [Fact]
    public void Build_EventsCarryLapTime_AndResetEachLap()
    {
        _sut.OnSection(Section("setup", ("frontWing", 10)));   // 다음 랩도 details가 있게
        _sut.OnEvent(Event("COLL", ("vehicle1Index", 3), ("vehicle2Index", 5)), lapTimeMs: 12_345);
        _sut.OnEvent(Event("FLBK"), lapTimeMs: -10);

        var first = (LapEventEntry[])_sut.Build(lapNumber: 1)![LapDetailsTracker.EventsKey]!;
        _sut.StartLap();
        var second = (LapEventEntry[])_sut.Build(lapNumber: 2)![LapDetailsTracker.EventsKey]!;

        Assert.Equal(new[] { "COLL", "FLBK" }, first.Select(entry => entry.Code));
        Assert.Equal(new[] { 12_345, 0 }, first.Select(entry => entry.LapTimeMs));   // 음수는 0
        Assert.Equal(5, first[0].Details["vehicle2Index"]);
        Assert.Empty(second);
    }

    [Fact]
    public void Build_SectionsWithoutEvents_StillWritesEmptyEventList()
    {
        _sut.OnSection(Section("status", ("maxRpm", 13_000)));

        var details = _sut.Build(lapNumber: 1)!;

        Assert.Empty((LapEventEntry[])details[LapDetailsTracker.EventsKey]!);
        Assert.False(details.ContainsKey(LapDetailsTracker.DroppedEventsKey));
    }

    [Fact]
    public void OnEvent_BeyondLimit_IsCountedNotKept()
    {
        for (var i = 0; i < LapDetailsTracker.MaxEventsPerLap + 3; i++)
        {
            _sut.OnEvent(Event("OVTK"), lapTimeMs: i);
        }

        var details = _sut.Build(lapNumber: 1)!;

        Assert.Equal(LapDetailsTracker.MaxEventsPerLap, ((LapEventEntry[])details[LapDetailsTracker.EventsKey]!).Length);
        Assert.Equal(3, details[LapDetailsTracker.DroppedEventsKey]);
    }

    [Fact]
    public void Build_PlayerSessionHistory_AddsThatLapOnly()
    {
        _sut.OnSessionHistory(new SessionHistoryFrame("s", 0, IsPlayer: true, [History(1, 90_000), History(2, 89_000)]));
        _sut.OnSessionHistory(new SessionHistoryFrame("s", 7, IsPlayer: false, [History(1, 70_000), History(2, 71_000)]));

        var details = _sut.Build(lapNumber: 2)!;

        Assert.Equal(History(2, 89_000), details[LapDetailsTracker.SessionHistoryKey]);
    }

    [Fact]
    public void Build_SessionHistoryWithoutThatLap_IsOmitted()
    {
        _sut.OnSessionHistory(new SessionHistoryFrame("s", 0, IsPlayer: true, [History(1, 90_000)]));

        var details = _sut.Build(lapNumber: 2)!;

        Assert.False(details.ContainsKey(LapDetailsTracker.SessionHistoryKey));
    }

    [Fact]
    public void Build_SanitizesValues_WithoutChangingSource()
    {
        var nested = new Dictionary<string, object?> { ["wear"] = float.NaN, ["delta"] = 0.123456 };
        var section = Section(
            "tyreSets",
            ("nan", double.NaN),
            ("inf", float.PositiveInfinity),
            ("camber", -3.50000012f),
            ("name", "LIM"),
            ("count", 3),
            ("sets", new object?[] { nested, 7 }),
            ("unknown", new Uri("https://example.com")));
        _sut.OnSection(section);

        var tyreSets = AsSection(_sut.Build(lapNumber: 1)!["tyreSets"]);

        Assert.Null(tyreSets["nan"]);
        Assert.Null(tyreSets["inf"]);
        Assert.Equal(-3.5, tyreSets["camber"]);
        Assert.Equal("LIM", tyreSets["name"]);
        Assert.Equal(3, tyreSets["count"]);
        Assert.Null(tyreSets["unknown"]);
        var sets = Assert.IsType<object?[]>(tyreSets["sets"]);
        var set = AsSection(sets[0]);
        Assert.Null(set["wear"]);
        Assert.Equal(0.123, set["delta"]);
        Assert.Equal(7, sets[1]);
        Assert.Equal(float.NaN, nested["wear"]);   // 원본은 그대로
    }

    [Fact]
    public void Sanitize_TooDeep_IsNull()
    {
        var level5 = new Dictionary<string, object?> { ["x"] = 1 };
        var level4 = new Dictionary<string, object?> { ["e"] = level5, ["y"] = 2 };
        var level3 = new Dictionary<string, object?> { ["d"] = level4 };
        var level2 = new Dictionary<string, object?> { ["c"] = level3 };
        var root = new Dictionary<string, object?> { ["b"] = level2 };

        var sanitized = DetailValues.Sanitize(root);

        var d = AsSection(AsSection(AsSection(sanitized["b"])["c"])["d"]);   // 4단계(MaxDepth)까지는 남는다
        Assert.Equal(2, d["y"]);
        Assert.Null(d["e"]);                                                // 5단계는 null
    }

    [Fact]
    public void Reset_ForgetsEverything()
    {
        _sut.OnSection(Section("setup", ("frontWing", 10)));
        _sut.OnEvent(Event("PENA"), lapTimeMs: 1);
        _sut.OnSessionHistory(new SessionHistoryFrame("s", 0, IsPlayer: true, [History(1, 90_000)]));

        _sut.Reset();

        Assert.Null(_sut.Build(lapNumber: 1));
    }
}
