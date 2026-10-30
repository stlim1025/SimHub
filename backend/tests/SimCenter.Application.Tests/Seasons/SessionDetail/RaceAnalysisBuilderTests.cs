using System.Text.Json;
using SimCenter.Application.Laps;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Application.TrackSamples;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;
using static SimCenter.Application.Tests.Seasons.SessionDetail.SessionDetailSamples;

namespace SimCenter.Application.Tests.Seasons.SessionDetail;

/// <summary>
/// 레이스 심층 분석: 1km 트랙(10m 간격 101표본) — 직선 0~290m · 코너 A 300~500m(브레이크·락업·휠스핀·연석) · 직선 510~790m(Overtake로 배터리 씀)
/// · 코너 B 800~900m(배터리 채움) · 직선 910m~결승선. 10랩 레이스, 나(차 0)와 AI 두 대 모두 Medium 1~4랩 → Hard 5~10랩.
/// </summary>
public class RaceAnalysisBuilderTests
{
    private const int ResolutionM = 10;
    private const int SampleCount = 101;
    private const int TotalLaps = 10;

    private static readonly SessionResult Me = Result(0, position: 2, grid: 2, isPlayer: true, name: "Player", teamId: 221, (3, TyreCompound.Medium), (0, TyreCompound.Hard));
    private static readonly SessionResult Ai1 = Result(1, position: 1, grid: 1, false, "NORRIS", 228, (3, TyreCompound.Medium), (0, TyreCompound.Hard));
    private static readonly SessionResult Ai2 = Result(2, position: 3, grid: 3, false, "LECLERC", 222, (3, TyreCompound.Medium), (0, TyreCompound.Hard));

    private static readonly int[] MyLapTimes = [100_000, 90_000, 90_000, 110_000, 112_000, 90_000, 90_000, 90_000, 90_000, 90_000];
    private static readonly int[] AiLapTimes = [101_000, 91_000, 91_000, 111_000, 113_000, 91_000, 91_000, 91_000, 91_000, 91_000];

    [Fact]
    public void Build_RaceAnalysis_SegmentsDrivingBatteryStrategyPace()
    {
        var analysis = RaceAnalysisBuilder.Build(
            Session(SessionType.Race), [Ai1, Me, Ai2], SessionHistory.Parse(History()), 0, MyLaps(),
            Enumerable.Range(1, TotalLaps).Select(n => Trace(n)).ToList(), [AiSamples()], 1000)!;

        Assert.Equal(2, analysis.ReferenceLap);   // 깨끗한 랩이 모두 90.0초 → 가장 앞 랩
        Assert.Equal(
            [
                new RaceSegmentDto(0, "Straight", 910, 290, 910, 300),
                new RaceSegmentDto(1, "Corner", 300, 500, 400, 100),
                new RaceSegmentDto(2, "Straight", 510, 790, 510, 300),
                new RaceSegmentDto(3, "Corner", 800, 900, 800, 200),
            ],
            analysis.Segments);

        // Medium: 깨끗한 랩 2·3. 앞왼만 코너 A에서 횡력 1000N·슬립각 45° → 21표본 × 1000 × 10m = 210kJ.
        var medium = analysis.Stints[0];
        Assert.Equal(("Medium", 1, 4), (medium.Compound, medium.StartLap, medium.EndLap));
        Assert.Equal([2, 3], medium.Laps);
        Assert.Equal([210.0, 0, 0, 0], medium.WheelWorkKj);
        Assert.Equal([2.0, 2.0, 2.0, 2.0], medium.WheelWearPerLapPct);
        var cornerA = medium.Segments[1];
        Assert.Equal(2100, cornerA.TimeMs);
        Assert.Equal((60.0, 60.0, 60.0, 60.0, 30.0), (cornerA.LockupM!.Value, cornerA.WheelspinM!.Value, cornerA.TrailBrakeM, cornerA.ThrottleSteerM, cornerA.KerbM!.Value));
        Assert.Equal(60, cornerA.BrakeM);
        Assert.Equal(22.5, cornerA.UndersteerDeg);   // 코너링 중 앞 슬립각 (45 + 0)/2 − 뒤 0
        Assert.Equal([120.0, 90, 90, 90], cornerA.PeakSurfaceTempC);
        Assert.Equal((100, 120), (cornerA.MinSpeedKph, cornerA.EndSpeedKph));
        var straight = medium.Segments[2];
        Assert.Equal((0.0, 290.0, 290.0, 1710.0), (straight.HarvestKj!.Value, straight.DeployKj!.Value, straight.OvertakeM!.Value, straight.StoreEndKj!.Value));
        Assert.Equal((55.0, 1765.0), (medium.Segments[3].HarvestKj!.Value, medium.Segments[3].StoreEndKj!.Value));
        Assert.Equal(0, straight.EmptyLaps);   // 잔량이 200kJ 아래로 내려간 랩 없음

        // Hard: 깨끗한 랩 6~10, 코너 A가 랩마다 210ms씩 느려진다.
        var hard = analysis.Stints[1];
        Assert.Equal([6, 7, 8, 9, 10], hard.Laps);
        Assert.Equal((2520, 210), (hard.Segments[1].TimeMs, hard.Segments[1].TimeTrendMsPerLap!.Value));
        Assert.Null(medium.Segments[1].TimeTrendMsPerLap);   // 2랩은 기울기를 내지 않는다

        // 랩당 마모 8%p ÷ 마찰 일 0.21MJ.
        Assert.Equal(38.1, analysis.WearPctPerMj);

        var aiErs = analysis.FieldErs;
        Assert.Equal(new FieldSegmentErsDto(2, 0, 290, 1), aiErs[2]);
        Assert.Equal(new FieldSegmentErsDto(3, 55, 0, 1), aiErs[3]);

        var strategy = analysis.Strategy!;
        Assert.Equal((10, 4, 6, 42_000), (strategy.TotalLaps, strategy.IdealLap!.Value, strategy.LatestLap!.Value, strategy.PitLossMs!.Value));
        Assert.Equal(new RaceStopContextDto(4, 4, 6, 40, 11, "Medium", "Hard", 100), Assert.Single(strategy.Stops));
        Assert.Equal(
            [
                new RaceCompoundModelDto("Soft", -400, null, 12, 1),
                new RaceCompoundModelDto("Medium", 0, 200, 15, 1),
                new RaceCompoundModelDto("Hard", 500, 100, 20, 1),
            ],
            strategy.Compounds);
        // 실제 M4·H6 = 1.2 + 4.5초 + 스톱 42초. 1스톱 M5·H5 = 2.0 + 3.5초가 0.2초 빠르다(Soft는 탄 적이 없어 빠지고, 세트가 하나씩이라 2스톱은 없다).
        Assert.Equal(2, strategy.Options.Count);
        Assert.True(strategy.Options[0].IsActual);
        Assert.Equal([new RaceStrategyStintDto("Medium", 5), new RaceStrategyStintDto("Hard", 5)], strategy.Options[1].Stints);
        Assert.Equal(-200, strategy.Options[1].DeltaMs);

        Assert.Equal(new RaceLapPaceDto(2, 90_000, 91_000, 91_000, "Medium", 1, true), analysis.LapPace[1]);
        Assert.Equal(new RaceLapPaceDto(7, 90_000, 91_000, 91_000, "Hard", 2, true), analysis.LapPace[6]);
        Assert.False(analysis.LapPace[3].IsClean);   // 인 랩
    }

    [Fact]
    public void Build_ShortGapBetweenCorners_JoinsTheCornerBeforeIt()
    {
        var analysis = RaceAnalysisBuilder.Build(
            Session(SessionType.Race), [Ai1, Me, Ai2], SessionHistory.Parse(History()), 0, MyLaps(),
            Enumerable.Range(1, TotalLaps).Select(n => Trace(n, cornerB: (60, 70))).ToList(), [], 1000)!;

        // 코너 A(300~500m)와 코너 B(600~700m) 사이 90m는 직선이 되기에 짧아 코너 A의 탈출로 붙는다 — 구간이 랩을 빈틈없이 덮는다.
        Assert.Equal(
            [("Straight", 710, 290), ("Corner", 300, 590), ("Corner", 600, 700)],
            analysis.Segments.Select(s => (s.Kind, s.StartM, s.EndM)));
    }

    [Fact]
    public void Build_WithoutTraces_KeepsStrategyAndPace()
    {
        var analysis = RaceAnalysisBuilder.Build(
            Session(SessionType.Race), [Ai1, Me, Ai2], SessionHistory.Parse(History()), 0, MyLaps(), [], [], null)!;

        Assert.Null(analysis.ReferenceLap);
        Assert.Empty(analysis.Segments);
        Assert.Empty(analysis.Stints);
        Assert.Empty(analysis.FieldErs);
        Assert.NotNull(analysis.Strategy);
        Assert.Equal(TotalLaps, analysis.LapPace.Count);
    }

    [Fact]
    public void Build_NotRaceOrUnknownCar_Null()
    {
        var history = SessionHistory.Parse(History());
        Assert.Null(RaceAnalysisBuilder.Build(Session(SessionType.Qualifying), [Me], history, 0, [], [], [], null));
        Assert.Null(RaceAnalysisBuilder.Build(Session(SessionType.Race), [Me], history, null, [], [], [], null));
    }

    /// <summary>내 랩 트레이스. 코너 A의 표본 사이 시간이 Hard 6랩부터 랩마다 10ms씩 늘어난다. [cornerB] = 코너 B 표본 범위(기본 80~90).</summary>
    private static RaceTraceLap Trace(int lap, (int Start, int End)? cornerB = null)
    {
        var (bStart, bEnd) = cornerB ?? (80, 90);
        var extraMs = lap >= 6 ? 10 * (lap - 6) : 0;
        var time = new int[SampleCount];
        var speed = new int[SampleCount];
        var throttle = new int[SampleCount];
        var brake = new int[SampleCount];
        var steer = new int[SampleCount];
        var lateral = new double[SampleCount];
        var store = new double[SampleCount];
        var mode = new double[SampleCount];
        var latForceFl = new double[SampleCount];
        var slipAngleFl = new double[SampleCount];
        var slipRatioFl = new double[SampleCount];
        var slipRatioRl = new double[SampleCount];
        var surfaceFl = new double[SampleCount];
        var surfaceTempFl = new double[SampleCount];
        for (var i = 0; i < SampleCount; i++)
        {
            var inA = i is >= 30 and <= 50;
            var inB = i >= bStart && i <= bEnd;
            time[i] = i == 0 ? 0 : time[i - 1] + 100 + (inA ? extraMs : 0);
            speed[i] = i == 40 ? 100 : inA ? 120 : inB ? 200 : 300;
            throttle[i] = inA && i < 45 ? 0 : 100;
            brake[i] = i is >= 30 and <= 35 ? 100 : 0;
            steer[i] = inA ? 20 : inB ? 10 : 0;
            lateral[i] = inA ? 3 : inB ? 2 : 0;
            latForceFl[i] = inA ? 1000 : 0;
            slipAngleFl[i] = inA ? 45 : 0;
            slipRatioFl[i] = i is >= 30 and <= 35 ? -20 : 0;
            slipRatioRl[i] = i is >= 45 and <= 50 ? 10 : 0;
            surfaceFl[i] = i is >= 40 and <= 42 ? 1 : 0;
            surfaceTempFl[i] = inA ? 120 : 90;
            store[i] = i <= 50 ? 2_000_000 : i <= 79 ? 2_000_000 - 10_000 * (i - 50) : i <= 90 ? 1_710_000 + 5_000 * (i - 79) : 1_765_000;
            mode[i] = i is >= 51 and <= 79 ? 3 : 1;
        }

        var zeros = new double[SampleCount];
        var flat90 = Enumerable.Repeat(90.0, SampleCount).ToArray();
        var extra = new Dictionary<string, double[]>
        {
            ["gForceLateral"] = lateral,
            ["ersStoreEnergy"] = store,
            ["ersDeployMode"] = mode,
        };
        AddWheels(extra, "wheelLatForce", latForceFl, zeros);
        AddWheels(extra, "wheelLongForce", zeros, zeros);
        AddWheels(extra, "wheelSlipAngleDeg", slipAngleFl, zeros);
        AddWheels(extra, "wheelSlipRatioPct", slipRatioFl, zeros, rearLeft: slipRatioRl);
        AddWheels(extra, "surfaceType", surfaceFl, zeros);
        AddWheels(extra, "tyreSurfaceTemp", surfaceTempFl, flat90);
        AddWheels(extra, "tyreInnerTemp", flat90, flat90);
        var gear = Enumerable.Repeat(7, SampleCount).ToArray();
        var rpm = Enumerable.Repeat(11_000, SampleCount).ToArray();
        return new RaceTraceLap(lap, ResolutionM, new LapTraceChannels(time, speed, throttle, brake, steer, gear, rpm, extra));
    }

    private static void AddWheels(Dictionary<string, double[]> extra, string prefix, double[] frontLeft, double[] others, double[]? rearLeft = null)
    {
        extra[prefix + "FL"] = frontLeft;
        extra[prefix + "FR"] = others;
        extra[prefix + "RL"] = rearLeft ?? others;
        extra[prefix + "RR"] = others;
    }

    /// <summary>AI 차 1의 한 랩 표본(5, 15, … 995m, 다음 랩 5m): 직선 510~790m에서 표본마다 10kJ 쓰고 코너 B에서 5kJ씩 채운다.</summary>
    private static DecodedTrackSamples AiSamples()
    {
        const int count = 101;
        var distance = Enumerable.Range(0, count).Select(k => k < 100 ? 5f + 10 * k : 5f).ToArray();
        var ers = Enumerable.Range(0, count)
            .Select(k => (ushort)(k <= 50 ? 2000 : k <= 79 ? 2000 - 10 * (k - 50) : k <= 90 ? 1710 + 5 * (k - 79) : 1765))
            .ToArray();
        return new DecodedTrackSamples(
            5,
            Enumerable.Range(0, count).Select(k => k * 100).ToArray(),
            Enumerable.Repeat((byte)1, count).ToArray(),
            distance,
            new float[count],
            new float[count],
            new ushort[count],
            new byte[count],
            null, null, null, null, null, null, null, null,
            ers);
    }

    /// <summary>내 랩 1~10: 마모(앞 w·뒤 w+2)는 랩마다 2%p씩, 5랩에 새 타이어. 스냅샷 details = 피트 창 + 타이어 세트.</summary>
    private static List<MySessionLap> MyLaps()
        => Enumerable.Range(1, TotalLaps)
            .Select(n => MySessionLap.From(LapRow(n, MyLapTimes[n - 1], details: TyreDetails(n), wear: n <= 4 ? 2 * n : 1 + 2 * (n - 5))))
            .ToList();

    /// <summary>
    /// 1~4랩: Medium(0번) 끼움, 안 쓴 Soft(1번, 5%)·Hard(2번) 델타가 랩마다 200ms씩 줄어든다(Medium이 랩당 200ms 느려짐). 피트 창 4~6랩.
    /// 5~10랩: Hard(2번) 끼움, Medium·Soft 델타가 랩마다 100ms씩 줄어든다. 피트 창 없음.
    /// </summary>
    private static string TyreDetails(int lap)
    {
        object Set(int compound, int wear, int life, int usable, int delta)
            => new { visualCompound = compound, wearPercent = wear, available = true, lifeSpanLaps = life, usableLifeLaps = usable, lapDeltaTimeMs = delta };

        var onMedium = lap <= 4;
        return JsonSerializer.Serialize(new
        {
            session = new { pitStopWindowIdealLap = onMedium ? 4 : 0, pitStopWindowLatestLap = onMedium ? 6 : 0 },
            tyreSets = new
            {
                fittedIndex = onMedium ? 0 : 2,
                sets = onMedium
                    ? new[] { Set(17, 10 * lap, 15 - lap, 15, 0), Set(16, 5, 12, 12, -400 - 200 * (lap - 1)), Set(18, 0, 20, 20, 500 - 200 * (lap - 1)) }
                    : new[] { Set(17, 40, 11, 15, 1500 - 100 * (lap - 5)), Set(16, 5, 12, 12, -900 - 100 * (lap - 5)), Set(18, 2 * (lap - 4), 20 - lap, 20, 0) },
            },
        });
    }

    private static string History()
    {
        static object Car(int carIndex, int[] laps) => new
        {
            carIndex,
            laps = laps.Select((ms, i) => new
            {
                lapNumber = i + 1,
                lapTimeMs = ms,
                sector1TimeMs = 30_000,
                sector2TimeMs = 30_000,
                sector3TimeMs = ms - 60_000,
                lapValid = true,
                sector1Valid = true,
                sector2Valid = true,
                sector3Valid = true,
            }),
        };

        return JsonSerializer.Serialize(new { lapHistory = new[] { Car(0, MyLapTimes), Car(1, AiLapTimes), Car(2, AiLapTimes) } });
    }

    private static GameSession Session(SessionType type) => new()
    {
        Id = Id(1),
        UserId = Id(500),
        GameCode = "F1_25",
        SessionKey = "link:1:2:3",
        SessionRef = "1",
        SessionType = type,
        SessionKind = type == SessionType.Race ? SessionKind.Race : SessionKind.Qualifying1,
        TotalLaps = TotalLaps,
        ClassifiedAt = At(9),
    };
}
