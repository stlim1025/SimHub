namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 시즌 목록 한 줄(12 §7.2). 내 결과가 없으면 <c>My*</c>, Standings가 비면 <c>Leader*</c>는 null이다.
/// 점수는 <c>int</c> 상한으로 자른 값이다(순서는 실제 합계 기준). 열거형은 문자열로 직렬화한다.
/// </summary>
public sealed record SeasonSummaryDto(
    Guid SeasonId,
    string GameCode,
    string GameMode,
    DateTime FirstSessionAt,
    DateTime LastSessionAt,
    int RoundCount,
    int? MyPosition,
    int? MyPoints,
    string? LeaderName,
    int? LeaderPoints);

/// <summary>시즌 상세: 헤더 + 라운드 + Standings(결과표 칸 포함). 세 탭이 같은 스냅샷을 쓴다.</summary>
public sealed record SeasonDetailDto(
    SeasonSummaryDto Season,
    IReadOnlyList<SeasonRoundDto> Rounds,
    SeasonStandingsDto Standings);

/// <summary>
/// 라운드(그랑프리 주말) 한 줄. <see cref="WinnerName"/>은 본 레이스 1위(없으면 null),
/// <see cref="MyPoints"/>는 그 주말 내 점수 합(계산 대상 세션만, 내 결과가 없으면 null).
/// <see cref="Sessions"/>는 저장된 모든 세션을 <c>ClassifiedAt</c> 오름차순으로 담는다.
/// </summary>
public sealed record SeasonRoundDto(
    int Round,
    Guid WeekendId,
    string TrackName,
    DateTime FirstSessionAt,
    string? WinnerName,
    int? MyPoints,
    IReadOnlyList<SeasonRoundSessionDto> Sessions);

/// <summary>라운드 안의 세션 칩. 내 결과가 없으면 <c>My*</c>는 null.</summary>
public sealed record SeasonRoundSessionDto(
    Guid SessionId,
    string SessionType,
    string SessionKind,
    int? MyPosition,
    string? MyResultStatus);

public sealed record SeasonStandingsDto(
    IReadOnlyList<DriverStandingDto> Drivers,
    IReadOnlyList<ConstructorStandingDto> Constructors);

/// <summary><see cref="Cells"/>는 그 드라이버가 결과를 가진 라운드만 담는다(라운드 번호 오름차순).</summary>
public sealed record DriverStandingDto(
    int Position,
    string DriverKey,
    string Name,
    string TeamName,
    string TeamColor,
    bool IsPlayer,
    bool IsAiControlled,
    int Points,
    int Wins,
    int Podiums,
    IReadOnlyList<StandingCellDto> Cells);

/// <summary><see cref="Position"/>·<see cref="ResultStatus"/>는 그 라운드에 본 레이스 기록이 없으면 null.</summary>
public sealed record StandingCellDto(int Round, int? Position, string? ResultStatus, int Points);

public sealed record ConstructorStandingDto(
    int Position,
    int TeamId,
    string TeamName,
    string TeamColor,
    int Points,
    int Wins);
