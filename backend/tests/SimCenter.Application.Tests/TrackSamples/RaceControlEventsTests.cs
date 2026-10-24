using SimCenter.Application.TrackSamples;

namespace SimCenter.Application.Tests.TrackSamples;

/// <summary>내 랩 이벤트 → 깃발 구간·리타이어(세션 시간).</summary>
public sealed class RaceControlEventsTests
{
    /// <summary>내 차 결승선 통과: 1랩 끝 80초, 2랩 끝 160초, 3랩 끝 240초.</summary>
    private static readonly IReadOnlyList<int> Crossings = [80_000, 160_000, 240_000];

    private const int RaceEndMs = 300_000;

    private static PlayerLapEvents Lap(int number, params string[] events)
        => new(number, 80_000, $$"""{"events": [{{string.Join(",", events)}}]}""");

    private static string Event(string code, int lapTimeMs, string details = "{}")
        => $$"""{"code": "{{code}}", "lapTimeMs": {{lapTimeMs}}, "details": {{details}}}""";

    [Fact]
    public void VirtualSafetyCar_DeployedAndEnded_IsOnePeriodInSessionTime()
    {
        var (flags, _) = RaceControlEvents.Build(
            [
                Lap(2, Event("SCAR", 10_000, """{"safetyCarType": 2, "eventType": 0}""")),
                Lap(3, Event("SCAR", 5_000, """{"safetyCarType": 2, "eventType": 3}""")),
            ],
            Crossings,
            RaceEndMs);

        var flag = Assert.Single(flags);
        Assert.Equal(RaceFlagKind.VirtualSafetyCar, flag.Kind);
        Assert.Equal(90_000, flag.FromMs);                // 2랩 시작 80초 + 10초
        Assert.Equal(165_000, flag.ToMs);                 // 3랩 시작 160초 + 5초
    }

    [Fact]
    public void SafetyCar_UndoneByFlashback_IsDropped()
    {
        var (flags, _) = RaceControlEvents.Build(
            [
                Lap(2,
                    Event("SCAR", 10_000, """{"safetyCarType": 1, "eventType": 0}"""),
                    Event("FLBK", 12_000, """{"flashbackSessionTimeMs": 85000}""")),
            ],
            Crossings,
            RaceEndMs);

        Assert.Empty(flags);
    }

    [Fact]
    public void SafetyCar_NeverEnded_RunsToRaceEnd()
    {
        var (flags, _) = RaceControlEvents.Build(
            [Lap(3, Event("SCAR", 1_000, """{"safetyCarType": 1, "eventType": 0}"""))],
            Crossings,
            RaceEndMs);

        Assert.Equal(new RaceFlagPeriod(RaceFlagKind.SafetyCar, 161_000, RaceEndMs), Assert.Single(flags));
    }

    [Fact]
    public void RedFlag_EndsAtLightsOut()
    {
        var (flags, _) = RaceControlEvents.Build(
            [Lap(2, Event("RDFL", 20_000), Event("LGOT", 70_000))],
            Crossings,
            RaceEndMs);

        Assert.Equal(new RaceFlagPeriod(RaceFlagKind.RedFlag, 100_000, 150_000), Assert.Single(flags));
    }

    [Fact]
    public void Retirement_RepeatedOnLaterLaps_CountsOnceAtTheFirst()
    {
        var (_, retirements) = RaceControlEvents.Build(
            [
                Lap(2, Event("RTMT", 30_000, """{"vehicleIndex": 7}""")),
                Lap(3, Event("RTMT", 2_000, """{"vehicleIndex": 7}""")),
            ],
            Crossings,
            RaceEndMs);

        Assert.Equal(new RaceRetirement(7, 110_000), Assert.Single(retirements));
    }

    [Fact]
    public void BrokenDetails_AreSkipped()
    {
        var (flags, retirements) = RaceControlEvents.Build(
            [new PlayerLapEvents(2, 80_000, "not json"), new PlayerLapEvents(3, 80_000, null)],
            Crossings,
            RaceEndMs);

        Assert.Empty(flags);
        Assert.Empty(retirements);
    }
}
