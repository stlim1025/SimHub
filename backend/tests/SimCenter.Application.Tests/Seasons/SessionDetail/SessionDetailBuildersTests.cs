using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;
using static SimCenter.Application.Tests.Seasons.SessionDetail.SessionDetailSamples;

namespace SimCenter.Application.Tests.Seasons.SessionDetail;

/// <summary>세션 상세 카드 빌더(docs/15 §11.3·§11.4, D-53): Laps · Tyre Stints · Penalties · Final Classification 간격 · 조립.</summary>
public class SessionDetailBuildersTests
{
    private const string GameCode = "F1_25";

    private static readonly SessionResult Me =
        Result(0, position: 4, grid: 6, isPlayer: true, name: "Player", teamId: 221, (2, TyreCompound.Medium), (4, TyreCompound.Hard));

    // ---- Laps ----

    [Fact]
    public void Laps_FromHistory_PositionsCompoundsPitGapAndPurple()
    {
        var myLaps = new[] { Lap(2, 92_044), Lap(3, 91_500, isValid: false, details: SnapshotDetailsJson(pitStatus: 1)) };

        var laps = SessionLapsBuilder.Build(0, 6, SessionHistory.Parse(SessionDetailsJson), StintSpan.From(Me), myLaps);

        // 진행 중 랩(랩타임 0)은 뺀다.
        Assert.Equal(new[] { 1, 2, 3 }, laps.Select(l => l.LapNumber));
        Assert.Equal(new int?[] { 5, 3, 4 }, laps.Select(l => l.Position));
        Assert.Equal(new int?[] { 1, 2, -1 }, laps.Select(l => l.PositionChange));   // 1랩은 그리드 6 대비
        Assert.Equal(new[] { "Medium", "Medium", "Hard" }, laps.Select(l => l.VisualCompound));
        Assert.Equal(new[] { false, true, true }, laps.Select(l => l.InPit));         // 2랩 = 스틴트 끝, 3랩 = pitStatus 1
        Assert.Equal(new int?[] { 6_368, 0, -544 }, laps.Select(l => l.GapToBestMs)); // 최고 = 유효 랩 중 최소(92,044)
        Assert.Equal(new[] { false, true, false }, laps.Select(l => l.IsBestLap));
        Assert.Equal(new[] { true, true, false }, laps.Select(l => l.IsValid));
        Assert.Equal(new int?[] { 33_801, 34_190, 30_421 }, laps[0].Sectors);
        Assert.Equal(new[] { false, false, false }, laps[0].BestSectors);
        Assert.Equal(new[] { false, true, false }, laps[1].BestSectors);               // S2 = 유효 섹터 중 최소
        Assert.Equal(new[] { true, false, true }, laps[2].BestSectors);                // S2는 무효 섹터라 보라 아님
        Assert.Equal(new Guid?[] { null, Id(3002), Id(3003) }, laps.Select(l => l.LapId));
    }

    [Fact]
    public void Laps_NoHistory_FallsBackToStoredLaps()
    {
        var myLaps = new[] { Lap(2, 90_000), Lap(1, 95_000), Lap(3, 0) };

        var laps = SessionLapsBuilder.Build(0, 0, SessionHistory.Empty, [], myLaps);

        Assert.Equal(new[] { 1, 2 }, laps.Select(l => l.LapNumber));
        Assert.All(laps, l => Assert.Null(l.Position));
        Assert.All(laps, l => Assert.Null(l.PositionChange));                        // 그리드 0 = 모름
        Assert.All(laps, l => Assert.Null(l.VisualCompound));
        Assert.Equal(new int?[] { 30_000, 31_000, 29_000 }, laps[1].Sectors);
        Assert.True(laps[1].IsBestLap);
        Assert.Equal(Id(3001), laps[0].LapId);
    }

    [Fact]
    public void Laps_AllInvalid_BestIsFastestOverall()
    {
        var laps = SessionLapsBuilder.Build(null, null, SessionHistory.Empty, [], [Lap(1, 95_000, isValid: false), Lap(2, 93_000, isValid: false)]);

        Assert.Equal(new[] { false, true }, laps.Select(l => l.IsBestLap));
        Assert.Equal(new int?[] { 2_000, 0 }, laps.Select(l => l.GapToBestMs));
    }

    [Fact]
    public void Laps_NoData_Empty()
        => Assert.Empty(SessionLapsBuilder.Build(0, 1, SessionHistory.Empty, [], []));

    // ---- Tyre Stints ----

    [Fact]
    public void TyreStints_SplitByStint_WithLapTimesAndLife()
    {
        var myLaps = new[] { Lap(2, 92_044, wear: 10), Lap(3, 91_500, wear: 20) };
        var stints = StintSpan.From(Me);
        var laps = SessionLapsBuilder.Build(0, 6, SessionHistory.Parse(SessionDetailsJson), stints, myLaps);

        var series = TyreStintSeriesBuilder.Build(stints, laps, myLaps);

        Assert.Equal(2, series.Count);
        Assert.Equal(("Medium", 1, 2), (series[0].VisualCompound, series[0].StartLap, series[0].EndLap));
        Assert.Equal(
            new (int, int, int?, double?)[] { (1, 1, 98_412, null), (2, 2, 92_044, 89.0) },
            series[0].Laps.Select(p => (p.LapNumber, p.LapInStint, p.LapTimeMs, p.TyreLifeRemaining)));
        Assert.Equal(("Hard", 3, 3), (series[1].VisualCompound, series[1].StartLap, series[1].EndLap)); // 기록 끝(3랩)으로 자른다
        Assert.Equal((3, 1, 91_500, 79.0), (series[1].Laps[0].LapNumber, series[1].Laps[0].LapInStint, series[1].Laps[0].LapTimeMs, series[1].Laps[0].TyreLifeRemaining));
    }

    [Fact]
    public void TyreStints_NoLapsOrNoStints_Empty()
    {
        Assert.Empty(TyreStintSeriesBuilder.Build(StintSpan.From(Me), [], []));
        Assert.Empty(TyreStintSeriesBuilder.Build([], [], [Lap(1, 90_000, wear: 5)]));
    }

    [Fact]
    public void StintSpan_SkipsBrokenAndDeletedStints()
    {
        var result = Result(0, 1, 1, true, null, 1, (5, TyreCompound.Soft), (3, TyreCompound.Medium), (9, TyreCompound.Hard));
        result.TyreStints.Add(new SessionResultTyreStint { StintNumber = 4, EndLap = 12, VisualCompound = TyreCompound.Wet, IsDeleted = true });

        var spans = StintSpan.From(result);

        Assert.Equal(new[] { (1, 5, "Soft", false), (6, 9, "Hard", true) }, spans.Select(s => (s.StartLap, s.EndLap, s.VisualCompound, s.IsLast)));
        Assert.Equal("Hard", StintSpan.CompoundAt(spans, 15));
        Assert.True(StintSpan.IsPitLap(spans, 5));
        Assert.False(StintSpan.IsPitLap(spans, 9));
        Assert.Empty(StintSpan.From(null));
    }

    // ---- Penalties ----

    [Fact]
    public void Penalties_DedupesAndResolvesDrivers()
    {
        var results = new[] { Me, Result(1, 1, 1, name: "NORRIS", teamId: 228) };
        // 같은 이벤트가 두 랩 스냅샷에 실려 와도(재전송) 한 번만.
        var myLaps = new[] { Lap(3, 91_500, details: SnapshotDetailsJson()), Lap(2, 92_044, details: SnapshotDetailsJson()) };

        var penalties = SessionPenaltiesBuilder.Build(GameCode, 0, results, myLaps);

        Assert.Equal(2, penalties.Count);
        Assert.Equal(
            new SessionPenaltyDto(2, 0, "Player", true, "#E8002D", "Small Collision", "Warning", null, 4, 5),
            penalties[0]);
        Assert.Equal(
            new SessionPenaltyDto(2, 1, "NORRIS", false, "#FF8000", "Corner cutting gained time", "Time penalty", 5, 7, 4),
            penalties[1]);
    }

    [Fact]
    public void Penalties_UnknownCarAndMissingLap_UseFallbacks()
    {
        const string details = """
            {"events":[
              {"code":"PENA","details":{"penaltyType":40,"infringementType":99,"vehicleIndex":7,"timeS":0}},
              {"code":"PENA","details":{"penaltyType":5}}
            ]}
            """;

        var penalty = Assert.Single(SessionPenaltiesBuilder.Build(GameCode, 0, [Me], [Lap(6, 90_000, details: details)]));

        Assert.Equal((6, 7, "Car 8", false, "#9CA3AF"), (penalty.Lap, penalty.CarIndex, penalty.DriverName, penalty.IsPlayer, penalty.TeamColor));
        Assert.Equal(("Unknown (99)", "Unknown (40)", (int?)null), (penalty.Infringement, penalty.Penalty, penalty.TimeS));
    }

    // ---- Final Classification ----

    [Fact]
    public void Gaps_Race_IncludesPenaltiesAndGridChange()
    {
        var winner = Result(3, 1, 4);
        winner.TotalRaceTimeMs = 1_600_000;
        var second = Result(4, 2, 1);
        second.TotalRaceTimeMs = 1_598_000;
        second.PenaltiesTimeMs = 5_000;
        var noGrid = Result(5, 3, 0);

        var gaps = ClassificationGaps.For(SessionType.Race, [winner, second, noGrid]);

        Assert.Equal((int?)0, gaps.GapMs(winner));
        Assert.Equal((int?)3_000, gaps.GapMs(second));
        Assert.Null(gaps.GapMs(noGrid));
        Assert.Equal((int?)3, gaps.PositionChange(winner));
        Assert.Equal((int?)-1, gaps.PositionChange(second));
        Assert.Null(gaps.PositionChange(noGrid));
    }

    [Fact]
    public void Gaps_Qualifying_UsesBestLap_NoPositionChange()
    {
        var pole = Result(0, 1, 0);
        pole.BestLapTimeMs = 88_000;
        var other = Result(1, 2, 0);
        other.BestLapTimeMs = 88_456;
        var noTime = Result(2, 3, 0);

        var gaps = ClassificationGaps.For(SessionType.Qualifying, [pole, other, noTime]);

        Assert.Equal(new int?[] { 0, 456, null }, new[] { pole, other, noTime }.Select(gaps.GapMs));
        Assert.Null(gaps.PositionChange(other));
    }

    // ---- 조립 ----

    [Fact]
    public void Assembler_BuildsAllCards()
    {
        var session = Session(SessionType.Race);
        var rows = new[]
        {
            LapRow(2, 92_044, details: SnapshotDetailsJson(), wear: 10, weather: Weather.LightCloud, gearbox: 3, engine: 1),
            LapRow(3, 91_500, isValid: false, details: SnapshotDetailsJson(pitStatus: 1), wear: 20),
        };

        var extras = SessionDetailAssembler.Build(session, [Me, Result(1, 1, 1, name: "NORRIS", teamId: 228)], rows, []);

        Assert.Equal(3, extras.Laps.Count);
        Assert.Equal(new MyBestLapDto(Id(3002), 92_044), extras.MyBestLap);     // 무효 랩 3은 더 빨라도 제외
        Assert.Equal(new EngineWearDto(12, 10, 9, 8, 7, 6, null, null), extras.EngineWear); // 마지막 랩(3)의 값
        Assert.NotNull(extras.Setup);
        Assert.Equal(2, extras.TyreStints.Count);
        Assert.Equal(2, extras.Penalties.Count);
        Assert.Equal("LightCloud", extras.Weather);
        Assert.Empty(extras.QualifyingPositions);                               // 레이스는 예선 순위 없음
    }

    [Fact]
    public void Assembler_QualifyingWithoutWeekend_ListsThisSession()
    {
        var session = Session(SessionType.Qualifying);
        session.SessionKind = SessionKind.OneShotQualifying;

        var extras = SessionDetailAssembler.Build(session, [Me], [], Array.Empty<WeekendQualifyingRow>());

        var only = Assert.Single(extras.QualifyingPositions);
        Assert.Equal((session.Id, "OneShotQualifying", 4), (only.SessionId, only.SessionKind, only.Position));
        Assert.Null(extras.MyBestLap);
    }

    [Fact]
    public void Assembler_NoPlayerRow_UsesSnapshotCarIndex()
    {
        var session = Session(SessionType.Race);

        var extras = SessionDetailAssembler.Build(session, [], [LapRow(2, 92_044, details: SnapshotDetailsJson())], []);

        Assert.Equal(3, extras.Laps.Count);                    // lapData.carIndex 0 → lapHistory 차 0
        Assert.True(extras.Penalties[0].IsPlayer);
    }

    private static GameSession Session(SessionType type) => new()
    {
        Id = Id(1),
        UserId = Id(500),
        GameCode = GameCode,
        SessionKey = "link:1:2:3",
        SessionRef = "1",
        SessionType = type,
        SessionKind = type == SessionType.Race ? SessionKind.Race : SessionKind.Qualifying1,
        ClassifiedAt = At(9),
        Details = SessionDetailsJson,
    };
}
