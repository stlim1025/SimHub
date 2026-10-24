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

    /// <summary>[offsets]의 차들이 같은 속도로 [fromMs]~[toMs] 달린다. 차마다 출발 위치만 다르다(m, 출발선 앞).</summary>
    private static DecodedTrackSamples Race(IReadOnlyDictionary<byte, double> offsets, int fromMs = 0, int toMs = RaceMs, params Mark[] marks)
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
                var lapDistance = (offset + SpeedMps * t / 1000.0) % TrackLength;
                var angle = lapDistance / Radius;
                var mark = marks.FirstOrDefault(m => m.Car == index && m.TimeMs == t);
                time.Add(t);
                car.Add(index);
                distance.Add((float)lapDistance);
                x.Add((float)(Radius * Math.Cos(angle)));
                z.Add((float)(Radius * Math.Sin(angle)));
                status.Add(mark?.Status ?? 0);
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
        => HighlightsBuilder.Build(Guid.Empty, 5, RaceTimeline.Build([samples]), TrackLength, Cars, flags ?? [], []);

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
    public void NoSamples_GivesEmptyReels()
    {
        var result = HighlightsBuilder.Build(Guid.Empty, 5, RaceTimeline.Build([]), TrackLength, Cars, [], []);

        Assert.Empty(result.Mine);
        Assert.Empty(result.Race);
    }
}
