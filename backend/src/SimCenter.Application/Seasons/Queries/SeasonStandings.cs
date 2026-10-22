using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 결과표(드라이버 × 라운드) 한 칸. <see cref="Position"/>·<see cref="ResultStatus"/>는 그 주말 본 레이스의 결과이고
/// (그 드라이버의 본 레이스 기록이 없으면 null), <see cref="Points"/>는 그 주말 계산 대상 세션의 점수 합(스프린트 포함)이다.
/// </summary>
public sealed record StandingCell(Guid WeekendId, int? Position, ResultStatus? ResultStatus, int Points);

/// <summary>
/// 드라이버 순위 한 줄. 이름·팀·AI 여부는 그 드라이버의 가장 최근 세션 값이고, 점수는 <c>int</c> 상한으로 자른 값이다(순서는 실제 합계 기준).
/// <see cref="Cells"/>는 그 드라이버가 결과를 가진 주말만 담는다. <see cref="TeamName"/> = 저장된 사용자 팀 이름(가져온 My Team).
/// </summary>
public sealed record DriverStanding(
    int Position,
    string DriverKey,
    string Name,
    int? TeamId,
    bool IsPlayer,
    bool IsAiControlled,
    int Points,
    int Wins,
    int Podiums,
    IReadOnlyList<StandingCell> Cells,
    string? TeamName = null);

/// <summary>팀(컨스트럭터) 순위 한 줄. 팀 ID가 다르면 이름이 같아도 다른 팀이다. <see cref="TeamName"/> = 사용자 팀 이름(My Team, 없으면 null).</summary>
public sealed record ConstructorStanding(int Position, int TeamId, int Points, int Wins, string? TeamName = null);

/// <summary>시즌의 드라이버·컨스트럭터 순위.</summary>
public sealed record SeasonStandings(
    IReadOnlyList<DriverStanding> Drivers,
    IReadOnlyList<ConstructorStanding> Constructors);
