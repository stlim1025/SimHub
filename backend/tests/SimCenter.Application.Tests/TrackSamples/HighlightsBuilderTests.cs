using SimCenter.Application.TrackSamples;

namespace SimCenter.Application.Tests.TrackSamples;

/// <summary>레이스 표본 → 타임라인(되감기 정리)·하이라이트 두 묶음.</summary>
public sealed class HighlightsBuilderTests
{
    /// <summary>합성 서킷: 길이 600m 원, 차는 50m/s(한 랩 12초), 표본은 100ms마다.</summary>
    private const double TrackLength = 600;
    private const double SpeedMps = 50;
    private const int StepMs = 100;
    private const int RaceMs = 60_000;
    private static readonly double Radius = TrackLength / (2 * Math.PI);

    private const byte Player = 0;

    /// <summary>표본 하나에 얹을 표시(상태 비트·표시 비트 2·그 순간부터의 손상).</summary>
    private sealed record Mark(int TimeMs, byte Car, byte Status = 0, byte Flags2 = 0, byte Damage = 0);

    /// <summary>
    /// [offsets]의 차들이 같은 속도로 [fromMs]~[toMs] 달린다. 차마다 출발 위치만 다르다(m, 출발선 앞).
    /// [absent]가 참인 (차, 시각)은 표본을 넣지 않고(피트 레인·출발 전), [statusAt]은 표시가 없는 표본의 상태 비트.
    /// </summary>
    private static DecodedTrackSamples Race(
        IReadOnlyDictionary<byte, double> offsets, int fromMs = 0, int toMs = RaceMs, Func<byte, int, bool>? absent = null,
        Func<byte, int, byte>? statusAt = null, params Mark[] marks)
    {
        var time = new List<int>();
        var car = new List<byte>();
        var distance = new List<float>();
        var x = new List<float>();
        var z = new List<float>();
        var status = new List<byte>();
        var flags2 = new List<byte>();
        var damage = new List<byte>();
        for (var t = fromMs; t <= toMs; t += StepMs)
        {
            foreach (var (index, offset) in offsets)
            {
                if (absent?.Invoke(index, t) == true)
                {
                    continue;
                }

                var lapDistance = (offset + SpeedMps * t / 1000.0) % TrackLength;
                var angle = lapDistance / Radius;
                var mark = marks.FirstOrDefault(m => m.Car == index && m.TimeMs == t);
                time.Add(t);
                car.Add(index);
                distance.Add((float)lapDistance);
                x.Add((float)(Radius * Math.Cos(angle)));
                z.Add((float)(Radius * Math.Sin(angle)));
                status.Add(mark?.Status ?? statusAt?.Invoke(index, t) ?? 0);
                flags2.Add(mark?.Flags2 ?? 0);
                damage.Add(marks.Where(m => m.Car == index && m.TimeMs <= t).Select(m => m.Damage).DefaultIfEmpty((byte)0).Max());
            }
        }

        var count = time.Count;
        return new DecodedTrackSamples(
            5, [.. time], [.. car], [.. distance], [.. x], [.. z], new ushort[count], [.. status],
            Enumerable.Repeat((ushort)180, count).ToArray(), Enumerable.Repeat((sbyte)6, count).ToArray(),
            Enumerable.Repeat((byte)100, count).ToArray(), new byte[count], new byte[count], new float[count],
            new sbyte[count], new ushort[count], new ushort[count],
            new float[count], new float[count], [.. damage], [.. flags2]);
    }

    private static readonly IReadOnlyList<HighlightCarDto> Cars =
    [
        new(1, "LEADER", "#fff", false, 1),
        new(Player, "ME", "#fff", true, 2),
        new(2, "THIRD", "#fff", false, 3),
    ];

    private static HighlightsResponse Build(DecodedTrackSamples samples, IReadOnlyList<RaceFlagPeriod>? flags = null)
        => HighlightsBuilder.Build(Guid.Empty, Guid.Empty, "F1_25", 5, RaceTimeline.Build([samples]), TrackLength, Cars, flags ?? [], []);

    [Fact]
    public void Timeline_WhenTimeGoesBack_DropsSamplesAfterTheRewind()
    {
        // 첫 조각은 0~10초를 달렸고, 둘째 조각은 플래시백으로 5초부터 다시 달렸다(다른 위치).
        var first = Race(new Dictionary<byte, double> { [1] = 0 }, 0, 10_000);
        var second = Race(new Dictionary<byte, double> { [1] = 100 }, 5_000, 8_000);

        var timeline = RaceTimeline.Build([first, second]);
        var samples = timeline.Cars[1];

        Assert.Equal(0, timeline.StartMs);
        Assert.Equal(8_000, timeline.EndMs);
        Assert.True(samples.Zip(samples.Skip(1)).All(p => p.First.TimeMs < p.Second.TimeMs));
        Assert.Equal(400f, timeline.SampleAt(1, 6_000)!.Value.LapDistanceM, 1);   // 100 + 50m/s × 6초
    }

    [Fact]
    public void Timeline_CrossingsAreWhereLapDistanceWraps()
    {
        var timeline = RaceTimeline.Build([Race(new Dictionary<byte, double> { [1] = 0 })]);

        var crossings = timeline.CrossingsOf(1, TrackLength);

        Assert.Equal([12_000, 24_000, 36_000, 48_000, 60_000], crossings);
    }

    [Fact]
    public void Overtake_BetweenCloseCars_IsInBothReels_WithBothCars()
    {
        var samples = Race(
            new Dictionary<byte, double> { [1] = 30, [Player] = 20, [2] = 10 },
            marks: [new Mark(30_000, 2, Flags2: RaceSample.OvertookFlag), new Mark(30_000, Player, Flags2: RaceSample.OvertakenFlag)]);

        var result = Build(samples);

        var clip = Assert.Single(result.Race, c => c.Kind == nameof(HighlightKind.Overtake));
        Assert.Equal(2, clip.FocusCar);
        Assert.Equal(Player, clip.OtherCar);
        Assert.Equal(30_000, clip.EventMs);
        Assert.Equal(3, clip.Lap);                        // 30초 = 3랩째
        Assert.Contains(clip.Cars, c => c.CarIndex == 2);
        Assert.Contains(clip.Cars, c => c.CarIndex == Player);
        Assert.Contains(result.Mine, c => c.Kind == nameof(HighlightKind.Overtake));
    }

    [Fact]
    public void Overtake_FlagsOnFarApartCars_AreIgnored()
    {
        var samples = Race(
            new Dictionary<byte, double> { [1] = 300, [Player] = 0 },
            marks: [new Mark(30_000, 1, Flags2: RaceSample.OvertookFlag), new Mark(30_000, Player, Flags2: RaceSample.OvertakenFlag)]);

        var result = Build(samples);

        Assert.DoesNotContain(result.Race, c => c.Kind == nameof(HighlightKind.Overtake));
    }

    [Fact]
    public void Overtake_DuringSafetyCar_IsIgnored_ButTheSafetyCarIsAScene()
    {
        var samples = Race(
            new Dictionary<byte, double> { [1] = 30, [2] = 20 },
            marks: [new Mark(30_000, 2, Flags2: RaceSample.OvertookFlag), new Mark(30_000, 1, Flags2: RaceSample.OvertakenFlag)]);

        var result = Build(samples, [new RaceFlagPeriod(RaceFlagKind.SafetyCar, 25_000, 40_000)]);

        Assert.DoesNotContain(result.Race, c => c.Kind == nameof(HighlightKind.Overtake));
        Assert.Contains(result.Race, c => c.Kind == nameof(HighlightKind.SafetyCar) && c.EventMs == 25_000);
        Assert.Equal(nameof(RaceFlagKind.SafetyCar), Assert.Single(result.Flags).Kind);
    }

    [Fact]
    public void Overtake_RightBeforeOrAfterAPitStop_IsIgnored()
    {
        // 1번 차가 33~40초 피트 레인(새 에이전트 pitStatus) — 30초 추월(진입 직전)과 44초 추월(합류 직후) 모두 피트 때문이다.
        const byte pitting = 1 << 3;
        var samples = Race(
            new Dictionary<byte, double> { [1] = 30, [2] = 20 },
            statusAt: (car, t) => car == 1 && t is >= 33_000 and <= 40_000 ? pitting : (byte)0,
            marks:
            [
                new Mark(30_000, 2, Flags2: RaceSample.OvertookFlag), new Mark(30_000, 1, Flags2: RaceSample.OvertakenFlag),
                new Mark(44_000, 1, Flags2: RaceSample.OvertookFlag), new Mark(44_000, 2, Flags2: RaceSample.OvertakenFlag),
            ]);

        var result = Build(samples);

        Assert.DoesNotContain(result.Race, c => c.Kind == nameof(HighlightKind.Overtake));
    }

    [Fact]
    public void Collision_WithPlayer_IsInBothReels_FocusedOnPlayerInMine()
    {
        var samples = Race(
            new Dictionary<byte, double> { [1] = 30, [Player] = 25, [2] = 0 },
            marks: [new Mark(40_000, 1, Status: RaceSample.CollisionFlag), new Mark(40_000, Player, Status: RaceSample.CollisionFlag)]);

        var result = Build(samples);

        var race = Assert.Single(result.Race, c => c.Kind == nameof(HighlightKind.Collision));
        Assert.Equal([0, 1], new[] { race.FocusCar, race.OtherCar!.Value }.Order());
        var mine = Assert.Single(result.Mine, c => c.Kind == nameof(HighlightKind.Collision));
        Assert.Equal(Player, mine.FocusCar);
    }

    [Fact]
    public void WallHit_CountsOnlyWhenDamageRises()
    {
        var samples = Race(
            new Dictionary<byte, double> { [1] = 300, [2] = 0 },
            marks:
            [
                new Mark(30_000, 2, Status: RaceSample.ImpactFlag),
                new Mark(30_100, 2, Damage: 40),
                new Mark(45_000, 1, Status: RaceSample.ImpactFlag),
            ]);

        var result = Build(samples);

        var crash = Assert.Single(result.Race, c => c.Kind == nameof(HighlightKind.Crash));
        Assert.Equal(2, crash.FocusCar);
    }

    [Fact]
    public void Reels_StartWithTheStart_AndEndWithTheFinish()
    {
        var result = Build(Race(new Dictionary<byte, double> { [1] = 30, [Player] = 20, [2] = 10 }));

        Assert.Equal(nameof(HighlightKind.Start), result.Race[0].Kind);
        Assert.Equal(1, result.Race[0].FocusCar);         // 출발 직후 가장 앞선 차
        Assert.Equal(3, result.Race[0].Cars.Count);       // 출발 장면은 모든 차
        Assert.Equal(nameof(HighlightKind.Finish), result.Race[^1].Kind);
        Assert.Equal(1, result.Race[^1].FocusCar);        // 우승 차

        Assert.Equal(nameof(HighlightKind.Start), result.Mine[0].Kind);
        Assert.Equal(Player, result.Mine[0].FocusCar);
        Assert.Equal(nameof(HighlightKind.Finish), result.Mine[^1].Kind);
        Assert.Equal(Player, result.Mine[^1].FocusCar);
    }

    [Fact]
    public void ClipSamples_AreThinnedAndAligned()
    {
        var result = Build(Race(new Dictionary<byte, double> { [1] = 30, [Player] = 20 }));

        var track = result.Race[0].Cars[0];
        Assert.True(track.TimeMs.Zip(track.TimeMs.Skip(1)).All(p => p.Second - p.First >= 200));
        Assert.Equal(track.TimeMs.Count, track.X.Count);
        Assert.Equal(track.TimeMs.Count, track.Lap.Count);
    }

    [Fact]
    public void Timeline_FirstCrossFromTheGrid_IsNotALap()
    {
        // 출발선 뒤 50m(그리드)에서 출발: 랩 거리 550m → 0m를 처음 넘는 것은 랩 끝이 아니다.
        var timeline = RaceTimeline.Build([Race(new Dictionary<byte, double> { [1] = TrackLength - 50 })]);

        var crossings = timeline.CrossingsOf(1, TrackLength);

        Assert.Equal(13_000, crossings[0]);              // 50m + 한 바퀴 = 13초
    }

    [Fact]
    public void Grid_IsRebuilt_FromTheFirstSamplesAfterLightsOut()
    {
        // 소등 0초. 옛 에이전트처럼 출발선을 넘기 전 표본이 없다: 1번은 1초, 2번은 2초에 출발선(랩 거리 0)을 넘는다.
        var samples = Race(
            new Dictionary<byte, double> { [1] = -50, [2] = -100 },
            absent: (car, t) => (car == 1 && t < 1_000) || (car == 2 && t < 2_000));
        var timeline = RaceTimeline.Build([samples]);

        var filled = RaceGrid.Fill(timeline, lightsOutMs: 0, TrackLength);

        Assert.Equal(-RaceGrid.HoldMs, filled.StartMs);
        var first = filled.SampleAt(1, -1_000)!.Value;
        var second = filled.SampleAt(2, -1_000)!.Value;
        Assert.Equal(0, first.SpeedKph);                 // 소등 전에는 그리드에 서 있다
        Assert.Equal(0, second.SpeedKph);
        Assert.InRange(TrackLength - first.LapDistanceM, 20, 30);    // 50m/s × 1초 ÷ 2 = 25m 뒤
        Assert.InRange(TrackLength - second.LapDistanceM, 45, 55);   // 50m/s × 2초 ÷ 2 = 50m 뒤
        var gap = Math.Sqrt(Math.Pow(first.X - second.X, 2) + Math.Pow(first.Z - second.Z, 2));
        Assert.InRange(gap, 25, 27);                     // 앞뒤 25m + 좌우 엇갈림
        Assert.True(filled.SampleAt(1, 500)!.Value.SpeedKph > 0);    // 소등 뒤 출발
        Assert.Equal(1_000, filled.Cars[1].First(s => s.TimeMs >= 1_000).TimeMs);   // 실제 표본은 그대로 이어진다
    }

    [Fact]
    public void StartClip_BeginsOnTheGrid_WhenLightsOutIsKnown()
    {
        var result = HighlightsBuilder.Build(
            Guid.Empty, Guid.Empty, "F1_25", 5, RaceTimeline.Build([Race(new Dictionary<byte, double> { [1] = 30, [Player] = 20 }, fromMs: -5_000)]),
            TrackLength, Cars, [], [], lightsOutMs: 0);

        Assert.Equal(-RaceGrid.HoldMs, result.Race[0].StartMs);
        Assert.Equal(0, result.Race[0].EventMs);
    }

    [Fact]
    public void PitStop_MissingSamples_AreMarkedPitInBeforeAndPitOutAfter()
    {
        // 2번 차는 21~36초에 피트 레인(옛 에이전트: 표본 없음). 19초에 1번과 부딪힌다.
        var samples = Race(
            new Dictionary<byte, double> { [1] = 30, [2] = 25 },
            absent: (car, t) => car == 2 && t is > 21_000 and < 36_000,
            marks: [new Mark(19_000, 1, Status: RaceSample.CollisionFlag), new Mark(19_000, 2, Status: RaceSample.CollisionFlag)]);

        var clip = Assert.Single(Build(samples).Race, c => c.Kind == nameof(HighlightKind.Collision));
        var car2 = clip.Cars.Single(c => c.CarIndex == 2);

        Assert.Equal(0, car2.Pit[car2.TimeMs.ToList().IndexOf(15_000)]);
        Assert.Equal(1, car2.Pit[car2.TimeMs.ToList().IndexOf(17_000)]);    // 표본이 끊기기 5초 안 = 피트 인
        Assert.Equal(1, car2.Pit[car2.TimeMs.ToList().IndexOf(21_000)]);
    }

    [Fact]
    public void PitStop_WithPitStatus_IsPitInUntilTheCarStops_ThenPitOut()
    {
        // 새 에이전트: 피트 레인 표본에 pitStatus가 실린다. 3번 차는 40~50초 피트 레인, 그 안 45초 표본에서 선다(속도 0).
        const byte pitting = 1 << 3;
        var samples = Race(
            new Dictionary<byte, double> { [1] = 30, [3] = 25 },
            statusAt: (car, t) => car == 3 && t is >= 40_000 and <= 50_000 ? pitting : (byte)0,
            marks: [new Mark(47_000, 1, Status: RaceSample.CollisionFlag), new Mark(47_000, 3, Status: RaceSample.CollisionFlag | pitting)]);
        var stopped = samples with { SpeedKph = samples.SpeedKph!.Select((v, i) => samples.CarIndex[i] == 3 && samples.TimeMs[i] == 45_000 ? (ushort)0 : v).ToArray() };

        var clip = Assert.Single(Build(stopped).Race, c => c.Kind == nameof(HighlightKind.Collision));
        var car3 = clip.Cars.Single(c => c.CarIndex == 3);

        Assert.Equal(1, car3.Pit[car3.TimeMs.ToList().IndexOf(42_000)]);
        Assert.Equal(2, car3.Pit[car3.TimeMs.ToList().IndexOf(46_000)]);
        Assert.Equal(0, car3.Pit[car3.TimeMs.ToList().IndexOf(51_000)]);
    }

    [Fact]
    public void Standings_OrderByProgress_WithGapsToTheLeader_PitAndRetirement()
    {
        // 1번이 2번보다 50m(1초) 앞. 2번은 20~35초 피트 레인(표본 없음), 3번은 30초에 리타이어.
        var samples = Race(
            new Dictionary<byte, double> { [1] = 60, [2] = 10, [3] = 5 },
            absent: (car, t) => (car == 2 && t is > 21_000 and < 36_000) || (car == 3 && t > 30_000));
        var timeline = RaceTimeline.Build([samples]);
        var crossings = timeline.Cars.Keys.ToDictionary(c => c, c => timeline.CrossingsOf(c, TrackLength));
        var standings = new RaceStandings(timeline, TrackLength, 5, winner: 1, crossings, [new RaceRetirement(3, 30_000)], new Dictionary<int, int[]>());

        var early = standings.Frames(10_000, 10_000).Single();
        Assert.Equal([1, 2, 3], early.Cars);
        Assert.Equal(0, early.GapMs[0]);
        Assert.InRange(early.GapMs[1]!.Value, 950, 1_050);       // 50m ÷ 50m/s
        Assert.Equal(1, early.Lap);

        var pit = standings.Frames(28_000, 28_000).Single();
        Assert.Equal((int)StandingState.Pit, pit.State[pit.Cars.ToList().IndexOf(2)]);

        var late = standings.Frames(40_000, 40_000).Single();
        Assert.Equal(3, late.Cars[^1]);                           // 리타이어는 맨 아래
        Assert.Equal((int)StandingState.Out, late.State[^1]);
    }

    [Fact]
    public void Standings_CarsCrossingAfterTheWinnersLastLap_AreFinished()
    {
        // 5랩 레이스: 1번이 60초 안에 5번째로 결승선을 지나면 피니시, 뒤따르는 2번은 그 뒤 처음 지날 때 피니시.
        var samples = Race(new Dictionary<byte, double> { [1] = 60, [2] = 10 }, toMs: 62_000);
        var timeline = RaceTimeline.Build([samples]);
        var crossings = timeline.Cars.Keys.ToDictionary(c => c, c => timeline.CrossingsOf(c, TrackLength));
        var standings = new RaceStandings(timeline, TrackLength, 5, winner: 1, crossings, [], new Dictionary<int, int[]>());

        var end = standings.Frames(62_000, 62_000).Single();

        Assert.Equal([1, 2], end.Cars);
        Assert.All(end.State, s => Assert.Equal((int)StandingState.Finished, s));
        Assert.InRange(end.GapMs[1]!.Value, 950, 1_050);
    }

    [Fact]
    public void NoSamples_GivesEmptyReels()
    {
        var result = HighlightsBuilder.Build(Guid.Empty, Guid.Empty, "F1_25", 5, RaceTimeline.Build([]), TrackLength, Cars, [], []);

        Assert.Empty(result.Mine);
        Assert.Empty(result.Race);
    }
}
