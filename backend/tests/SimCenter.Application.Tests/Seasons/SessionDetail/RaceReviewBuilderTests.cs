using System.Text.Json;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;
using static SimCenter.Application.Tests.Seasons.SessionDetail.SessionDetailSamples;

namespace SimCenter.Application.Tests.Seasons.SessionDetail;

/// <summary>레이스 총평 재료: 깨끗한 랩 페이스·피트 스톱·스틴트 추세·배터리.</summary>
public class RaceReviewBuilderTests
{
    // 차 0(나, 2위): 3랩 세이프티카, 5랩 피트(Medium → Hard). 차 1(우승): 6랩 피트(Soft → Medium). 차 2(3위): 5랩 피트(Medium → Hard).
    private static readonly int[] MyLaps = [100_000, 90_000, 99_000, 90_200, 110_000, 112_000, 89_500, 89_600, 89_700, 89_800];
    private static readonly int[] WinnerLaps = [99_000, 89_000, 89_000, 89_000, 89_000, 109_000, 111_000, 89_000, 89_000, 89_000];
    private static readonly int[] ThirdLaps = [101_000, 91_000, 91_000, 91_000, 112_000, 113_000, 91_000, 91_000, 91_000, 91_000];

    private static readonly SessionResult Me =
        Result(0, position: 2, grid: 3, isPlayer: true, name: "Player", teamId: 221, (4, TyreCompound.Medium), (0, TyreCompound.Hard));
    private static readonly SessionResult Winner =
        Result(1, position: 1, grid: 1, false, "NORRIS", 228, (5, TyreCompound.Soft), (0, TyreCompound.Medium));
    private static readonly SessionResult Third =
        Result(2, position: 3, grid: 2, false, "LECLERC", 222, (4, TyreCompound.Medium), (0, TyreCompound.Hard));

    [Fact]
    public void Build_StintWear_UsesOneTyreSet_WhenTheInLapAlreadyShowsNewTyres()
    {
        // 피트 박스가 기록선 앞인 트랙: 5랩(인 랩) 안에서 타이어를 바꿔 5랩 끝 기록은 이미 새 Hard(마모 0)다.
        // 바퀴 마모 앞 w·뒤 w+2 → 남은 수명 = 99 − w.
        var rows = new[] { LapRow(2, 90_000, wear: 2), LapRow(3, 90_000, wear: 4), LapRow(4, 90_200, wear: 6), LapRow(5, 110_000, wear: 0) };

        var review = RaceReviewBuilder.Build(
            Session(SessionType.Race), [Winner, Me, Third], SessionHistory.Parse(History()), 0, rows.Select(MySessionLap.From).ToList())!;

        var medium = review.Stints[0];
        Assert.Equal(2.0, medium.WearPerLapPct);   // 수명 97 → 93%(2랩). 5랩의 새 타이어(99%)는 다음 세트라 뺀다.
        Assert.Equal(93.0, medium.EndLifePct);
        Assert.Equal([2.0, 2.0, 2.0, 2.0], medium.WheelWearPerLapPct);
    }

    [Fact]
    public void Build_RaceReview_PaceStrategyStintsBattery()
    {
        var rows = new[]
        {
            LapRow(7, 89_500, wear: 2) with { ErsStoreEndJ = 3_900_000, ErsDeployedJ = 1_000_000, ErsHarvestedJ = 800_000 },
            LapRow(10, 89_800, wear: 8) with { ErsStoreEndJ = 300_000, ErsDeployedJ = 1_200_000, ErsHarvestedJ = 600_000 },
        };

        var review = RaceReviewBuilder.Build(
            Session(SessionType.Race), [Winner, Me, Third], SessionHistory.Parse(History()), 0, rows.Select(MySessionLap.From).ToList());

        Assert.NotNull(review);

        // 세이프티카 랩(99.0초)·피트 인·아웃 랩·1랩을 뺀 중앙값.
        var pace = review.Pace!;
        Assert.Equal(
            new RacePaceReviewDto(89_750, 2, 3, 90_000, "NORRIS", 89_000, "NORRIS", 89_000, "LECLERC", 91_000),
            pace with { MySectorMs = null, FieldSectorMs = null, AheadSectorMs = null });
        // 섹터 1·2는 30초, 섹터 3 = 랩 − 60초: 나 29.75초, 다른 차들 중앙값(29.0·31.0초) 30.0초, 앞 차 NORRIS 29.0초.
        Assert.Equal([30_000, 30_000, 29_750], pace.MySectorMs);
        Assert.Equal([30_000, 30_000, 30_000], pace.FieldSectorMs);
        Assert.Equal([30_000, 30_000, 29_000], pace.AheadSectorMs);

        var strategy = review.Strategy;
        Assert.Equal((3, 2, 1), (strategy.GridPosition, strategy.FinishPosition, strategy.Stops));
        var stop = Assert.Single(strategy.PitStops);
        Assert.Equal(
            new RacePitStopReviewDto(5, 2, 3, 42_500, "Medium", "Hard"),
            stop with { InLapLossMs = null, OutLapLossMs = null, PeerLossMs = null, PeerCount = 0, PeerInLapLossMs = null, PeerOutLapLossMs = null });
        // 비슷한 때(5랩 ± 3랩) 같은 원스톱으로 들어간 차: 우승(6랩, 42.0초)·3위(5랩, 43.0초).
        Assert.Equal((42_500, 2), (stop.PeerLossMs, stop.PeerCount));
        Assert.Equal(stop.LossMs, stop.InLapLossMs + stop.OutLapLossMs);   // 인 랩 + 아웃 랩 = 스톱 손실
        Assert.NotNull(strategy.FieldInLapLossMs);
        Assert.NotNull(strategy.FieldOutLapLossMs);
        Assert.Equal((1, 3, 1), (strategy.CommonStops, strategy.CommonStopsCars, strategy.WinnerStops));
        Assert.Equal(new[] { "Soft", "Medium" }, strategy.WinnerCompounds);
        Assert.Equal(42_500, strategy.FieldPitLossMs);  // 42.0초·43.0초
        var group = Assert.Single(strategy.StopGroups!);
        Assert.Equal(1, group.Stops);
        Assert.Equal([1, 2, 3], group.Finishes);
        Assert.Empty(strategy.Rivals!);   // 모두 원스톱이라 전략이 다른 상대가 없다
        Assert.Equal(
            Enumerable.Range(1, 10).Select(lap => new RaceLapPositionDto(lap, lap is >= 5 and <= 7 ? 3 : 2)),
            strategy.LapPositions);

        Assert.Equal(2, review.Stints.Count);
        // 같은 Medium의 차 2는 1~5랩(피트 전 5랩)을 탔다.
        Assert.Equal(new RaceStintReviewDto("Medium", 1, 5, null, 90_000, null, null, null, null, FieldStintLaps: 5), review.Stints[0]);
        // Hard: 7~10랩 89.5→89.8초(+100ms/랩), 같은 Hard의 차 2는 91.0초 일정. 마모 97% → 91%(3랩).
        var hard = review.Stints[1];
        Assert.Equal(new RaceStintReviewDto("Hard", 6, 10, 89_650, 91_000, 100, 0, 2.0, 91.0), hard with { WheelWearPerLapPct = null, EndLapsSlowerMs = null });
        Assert.Equal([2.0, 2.0, 2.0, 2.0], hard.WheelWearPerLapPct);   // 네 바퀴 모두 2% → 8%(3랩)
        Assert.Equal(50, hard.EndLapsSlowerMs);                      // 마지막 3랩 중앙값 89.70초 − 스틴트 중앙값 89.65초

        var battery = review.Battery!;
        Assert.Equal(new RaceBatteryReviewDto(2, 1_100_000, 700_000, 3_900_000, 300_000, 300_000, 10, 1, 1, battery.PerLap), battery);
        Assert.Equal(
            [new RaceBatteryLapDto(7, 3_900_000, 1_000_000, 800_000), new RaceBatteryLapDto(10, 300_000, 1_200_000, 600_000)],
            battery.PerLap);
    }

    [Fact]
    public void Build_Strategy_StopGroupsRivalsAndPeers_ByStopCount()
    {
        // 3위 LECLERC는 피트 없이 끝까지(2위 출발 → 3위): 나(3위 출발 → 2위, 원스톱)와 출발·결과 순서가 뒤바뀐 다른 전략 상대다.
        var noStop = Result(2, position: 3, grid: 2, false, "LECLERC", 222, (0, TyreCompound.Hard));

        var strategy = RaceReviewBuilder.Build(
            Session(SessionType.Race), [Winner, Me, noStop], SessionHistory.Parse(History()), 0, [])!.Strategy;

        Assert.Equal(
            [(0, new[] { 3 }), (1, new[] { 1, 2 })],
            strategy.StopGroups!.Select(g => (g.Stops, g.Finishes.ToArray())));
        Assert.Equal([new RaceStrategyRivalDto("LECLERC", 0, 2, 3)], strategy.Rivals);
        // 비슷한 때 같은 원스톱으로 들어간 차는 우승 차(6랩)뿐 — 피트 없는 LECLERC는 견줄 스톱이 없다.
        var stop = Assert.Single(strategy.PitStops);
        Assert.Equal((42_000, 1), (stop.PeerLossMs, stop.PeerCount));
    }

    [Fact]
    public void Build_NotRaceOrUnknownCar_Null()
    {
        var history = SessionHistory.Parse(History());
        Assert.Null(RaceReviewBuilder.Build(Session(SessionType.Qualifying), [Me], history, 0, []));
        Assert.Null(RaceReviewBuilder.Build(Session(SessionType.Race), [Me], history, null, []));
        Assert.Null(RaceReviewBuilder.Build(Session(SessionType.Race), [Me], SessionHistory.Empty, 0, []));
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

        // positions[carIndex]: 4랩 끝 나 2위, 7랩 끝 나 3위.
        var positions = Enumerable.Range(1, 10).Select(lap => new
        {
            lapNumber = lap,
            positions = lap is >= 5 and <= 7 ? new[] { 3, 1, 2 } : new[] { 2, 1, 3 },
        });
        return JsonSerializer.Serialize(new
        {
            lapHistory = new[] { Car(0, MyLaps), Car(1, WinnerLaps), Car(2, ThirdLaps) },
            lapPositions = positions,
        });
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
        ClassifiedAt = At(9),
    };
}
