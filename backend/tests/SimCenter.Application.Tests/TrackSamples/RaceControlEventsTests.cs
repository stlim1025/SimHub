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

    /// <summary>랩 끝 세션 상태(세이프티카 상태·지금까지 세이프티카·버추얼 횟수)를 함께 실은 랩.</summary>
    private static PlayerLapEvents LapEnding(int number, int status, int safetyCars, int virtualSafetyCars, params string[] events)
        => new(number, 80_000,
            $$$"""{"events": [{{{string.Join(",", events)}}}], "session": {"safetyCarStatus": {{{status}}}, "numSafetyCarPeriods": {{{safetyCars}}}, "numVirtualSafetyCarPeriods": {{{virtualSafetyCars}}}}}""");

    [Fact]
    public void VirtualSafetyCar_ClearAtLapEndAndNeverCounted_IsDropped()
    {
        // 1랩 추월 이벤트가 몰려 종료(또는 되감기) 이벤트가 버려진 경우: 출동 뒤 랩 끝 상태는 0, 버추얼 횟수도 그대로 0.
        var (flags, _) = RaceControlEvents.Build(
            [
                LapEnding(1, status: 0, safetyCars: 0, virtualSafetyCars: 0, Event("SCAR", 13_933, """{"safetyCarType": 2, "eventType": 0}""")),
                LapEnding(2, status: 0, safetyCars: 0, virtualSafetyCars: 0),
            ],
            Crossings,
            RaceEndMs);

        Assert.Empty(flags);
    }

    [Fact]
    public void SafetyCar_EndEventLost_EndsAtTheFirstClearLapEnd()
    {
        var (flags, _) = RaceControlEvents.Build(
            [
                LapEnding(2, status: 1, safetyCars: 1, virtualSafetyCars: 0, Event("SCAR", 10_000, """{"safetyCarType": 1, "eventType": 0}""")),
                LapEnding(3, status: 0, safetyCars: 1, virtualSafetyCars: 0),
            ],
            Crossings,
            RaceEndMs);

        Assert.Equal(new RaceFlagPeriod(RaceFlagKind.SafetyCar, 90_000, 240_000), Assert.Single(flags));
    }

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
    public void YellowFlag_SectorChanges_BecomePeriodsWithTheirSectors()
    {
        var (flags, _) = RaceControlEvents.Build(
            [
                Lap(2,
                    Event("YELLOW", 10_000, """{"sectors": [2]}"""),
                    Event("YELLOW", 20_000, """{"sectors": [2, 3]}"""),
                    Event("YELLOW", 30_000, """{"sectors": []}""")),
            ],
            Crossings,
            RaceEndMs);

        Assert.Equal(2, flags.Count);
        Assert.Equal((RaceFlagKind.YellowFlag, 90_000, 100_000), (flags[0].Kind, flags[0].FromMs, flags[0].ToMs));
        Assert.Equal([2], flags[0].Sectors!);
        Assert.Equal((RaceFlagKind.YellowFlag, 100_000, 110_000), (flags[1].Kind, flags[1].FromMs, flags[1].ToMs));
        Assert.Equal([2, 3], flags[1].Sectors!);
    }

    [Fact]
    public void YellowFlag_UndoneByFlashback_IsDropped()
    {
        var (flags, _) = RaceControlEvents.Build(
            [
                Lap(2,
                    Event("YELLOW", 10_000, """{"sectors": [1]}"""),
                    Event("FLBK", 12_000, """{"flashbackSessionTimeMs": 85000}""")),
            ],
            Crossings,
            RaceEndMs);

        Assert.Empty(flags);
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
