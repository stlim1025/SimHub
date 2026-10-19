namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 시즌 목록 한 줄(12 §7.2). 내 결과가 없으면 <c>My*</c>, Standings가 비면 <c>Leader*</c>는 null이다.
/// 점수는 <c>int</c> 상한으로 자른 값이다(순서는 실제 합계 기준). 열거형은 문자열로 직렬화한다.
/// <c>ImportedFrom</c> = 가져온 출처(docs/15 §12, D-55, 없으면 null). <c>MyTeam*</c> = Standings의 내 팀(내 결과가 없으면 null) — 헤더의 "모드 · 팀".
/// <c>SeasonNumber</c> = 같은 게임·모드 안 시즌 번호(D-54, 헤더 "Driver Career Season 1"), <c>MyDriverName</c> = Standings의 내 이름(없으면 null).
/// <c>Name</c> = 사용자가 붙인 이름(null = 기본 이름), <c>CompletedAt</c> = 완료로 표시한 시각(UTC, 진행 중이면 null).
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
    int? LeaderPoints,
    string? ImportedFrom = null,
    string? MyTeamName = null,
    string? MyTeamColor = null,
    int? SeasonNumber = null,
    string? MyDriverName = null,
    string? Name = null,
    DateTime? CompletedAt = null);

/// <summary>
/// 시즌 상세: 헤더 + 라운드 + Standings(결과표 칸 포함) + 캘린더(시즌 탭, docs/15 §12). 세 탭이 같은 스냅샷을 쓴다.
/// </summary>
public sealed record SeasonDetailDto(
    SeasonSummaryDto Season,
    IReadOnlyList<SeasonRoundDto> Rounds,
    SeasonStandingsDto Standings,
    IReadOnlyList<SeasonCalendarRoundDto> Calendar);

/// <summary>
/// 시즌 탭 한 줄(F1Laps 시즌 표, docs/15 §12): 게임 캘린더 트랙 전부 + 캘린더 밖 트랙에서 달린 주말(시간 순 자리에 끼움).
/// <see cref="Round"/> = 표 안 순번(1부터). 달리지 않은 라운드는 <c>WeekendId</c>·세션·결과가 null이고 팀은 시즌 팀이다.
/// <see cref="RaceSessionId"/> = 본 레이스(없으면 null), <see cref="FirstSessionId"/> = 그 주말 첫 세션.
/// <see cref="Points"/> = 레이스(스프린트 포함) 내 점수 합, <see cref="QualiPosition"/> = 마지막 예선(슛아웃 제외) 내 순위.
/// AI 난이도는 모르면(0) null. 순위는 모르면(0) null.
/// <see cref="IsSprintWeekend"/> = 그 주말에 Race2가 있다(그 주말의 Race = 스프린트, Race2 = 본 레이스).
/// <see cref="SprintPosition"/> = 스프린트 내 순위. <see cref="Sessions"/> = 그 주말 계산 대상 세션 전부(표시 순서,
/// <see cref="SessionPositions.WeekendOrder"/> → 시각).
/// </summary>
public sealed record SeasonCalendarRoundDto(
    int Round,
    Guid TrackId,
    string TrackName,
    string? CountryCode,
    Guid? WeekendId,
    Guid? RaceSessionId,
    Guid? FirstSessionId,
    string? MyTeamName,
    string? MyTeamColor,
    int? RacePosition,
    int? Points,
    int? QualiPosition,
    int? RaceAiDifficulty,
    int? QualiAiDifficulty,
    int? SprintPosition,
    bool IsSprintWeekend,
    IReadOnlyList<SeasonCalendarSessionDto> Sessions);

/// <summary>시즌 탭 그랑프리 메뉴의 세션 1개. 내 결과가 없거나 순위를 모르면 <see cref="MyPosition"/>은 null.</summary>
public sealed record SeasonCalendarSessionDto(Guid SessionId, string SessionKind, int? MyPosition);

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
