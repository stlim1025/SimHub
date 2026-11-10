using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons;

public class TeammateHeadToHeadTests
{
    private const string GameCode = "F1_26";

    private static TeammateHeadToHeadDto? Build(params SeasonResultRow[] rows)
    {
        var selection = SeasonSessionSelector.Select(rows);
        return TeammateHeadToHead.Build(selection, StandingsCalculator.Calculate(selection, GameCode), GameCode);
    }

    private static SeasonResultRow Me(int session, int weekend, int position, int points, SessionKind kind, double hours,
        int grid = 0, ResultStatus status = ResultStatus.Finished, SessionType type = SessionType.Race)
        => Row(session, weekend, "me", position, points, type, kind, hours, teamId: 222, isPlayer: true, isAi: false, status: status)
            with { GridPosition = grid };

    /// <summary>팀메이트: 주말 2부터 게임이 팀 ID를 478(같은 Red Bull)로 바꿔 보낸다.</summary>
    private static SeasonResultRow Mate(int session, int weekend, int position, int points, SessionKind kind, double hours,
        int grid = 0, SessionType type = SessionType.Race)
        => Row(session, weekend, "mate", position, points, type, kind, hours, carIndex: 1, teamId: weekend == 1 ? 222 : 478)
            with { GridPosition = grid };

    private static SeasonResultRow Other(int session, int weekend, int position, SessionKind kind, double hours, SessionType type = SessionType.Race)
        => Row(session, weekend, "other", position, 0, type, kind, hours, carIndex: 2, teamId: 221);

    [Fact]
    public void Build_ComparesMeWithTheAiTeammateAcrossRacesQualifyingAndResults()
    {
        var h2h = Build(
            // 주말 1: Q1 · Q2 둘 다, Q3는 나만(팀메이트 Q2 탈락). 본 레이스 나 P1(그리드 2), 팀메이트 P6(그리드 8).
            Me(1, 1, 5, 0, SessionKind.Qualifying1, 1, type: SessionType.Qualifying),
            Mate(1, 1, 8, 0, SessionKind.Qualifying1, 1, type: SessionType.Qualifying),
            Me(2, 1, 4, 0, SessionKind.Qualifying2, 2, type: SessionType.Qualifying),
            Mate(2, 1, 12, 0, SessionKind.Qualifying2, 2, type: SessionType.Qualifying),
            Me(3, 1, 2, 0, SessionKind.Qualifying3, 3, type: SessionType.Qualifying),
            Me(4, 1, 1, 25, SessionKind.Race, 5, grid: 2),
            Mate(4, 1, 6, 8, SessionKind.Race, 5, grid: 8),
            Other(4, 1, 2, SessionKind.Race, 5),
            // 주말 2(스프린트): 슛아웃만 — 팀메이트가 앞섬. 스프린트는 레이스 맞대결에 안 센다. 본 레이스 나 DNF, 팀메이트 P3(그리드 1).
            Me(5, 2, 3, 0, SessionKind.SprintShootout1, 20, type: SessionType.Qualifying),
            Mate(5, 2, 1, 0, SessionKind.SprintShootout1, 20, type: SessionType.Qualifying),
            Me(6, 2, 2, 7, SessionKind.Race, 22, grid: 3),
            Mate(6, 2, 1, 8, SessionKind.Race, 22, grid: 1),
            Me(7, 2, 20, 0, SessionKind.Race2, 26, grid: 4, status: ResultStatus.DidNotFinish),
            Mate(7, 2, 3, 15, SessionKind.Race2, 26, grid: 1));

        Assert.NotNull(h2h);
        Assert.Equal(("ME", "MATE", "Red Bull Racing"), (h2h.MyName, h2h.TeammateName, h2h.TeamName));
        Assert.Equal(new HeadToHeadCountDto(1, 1), h2h.Races);
        Assert.Equal(new HeadToHeadCountDto(1, 1), h2h.Qualifying);
        Assert.Equal(new HeadToHeadCountDto(32, 31), h2h.Points);
        Assert.Equal(new HeadToHeadCountDto(1, 1), h2h.Podiums);
        Assert.Equal(new HeadToHeadPositionDto(1, 3), h2h.BestRaceFinish);
        Assert.Equal(new HeadToHeadPositionDto(2, 1), h2h.HighestGrid);
        Assert.Equal(new HeadToHeadCountDto(1, 0), h2h.Dnfs);
    }

    [Fact]
    public void Build_WithoutATeammate_IsNull()
    {
        var h2h = Build(
            Me(1, 1, 1, 25, SessionKind.Race, 1),
            Other(1, 1, 2, SessionKind.Race, 1));

        Assert.Null(h2h);
    }
}
