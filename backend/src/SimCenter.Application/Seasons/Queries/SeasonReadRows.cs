using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 시즌 조회용 읽기 행(12 §7.3) — 결과 1건(드라이버 1명 × 세션 1건)의 프로젝션. 저장소 → 순수 계산기 전달용이다.
/// 활성(삭제되지 않은) 행만 담는다. <c>IsImported</c> = 가져온 세션의 행(D-55 — 점수는 가져온 스탠딩 기준선에 이미 들어 있다).
/// </summary>
public sealed record SeasonResultRow(
    Guid SeasonId,
    Guid WeekendId,
    Guid SessionId,
    SessionType SessionType,
    SessionKind SessionKind,
    DateTime ClassifiedAt,
    string DriverKey,
    string? DriverName,
    int CarIndex,
    int? TeamId,
    bool IsPlayer,
    bool IsAiControlled,
    int Position,
    ResultStatus ResultStatus,
    int Points,
    bool IsImported = false);

/// <summary>그랑프리 주말 행(라운드 번호 계산·트랙 이름 표시용).</summary>
/// <remarks>
/// <see cref="DisplayOrder"/>는 트랙의 캘린더 순서(D-43), <see cref="CalendarRounds"/>는 그 시즌이 가져온 시즌이라 라운드 번호를
/// 캘린더 순서로 매기는지(docs/15 §12, D-55).
/// </remarks>
public sealed record WeekendRow(
    Guid WeekendId, Guid SeasonId, string TrackName, DateTime FirstSessionAt, int DisplayOrder = 0, bool CalendarRounds = false);

/// <summary>
/// 세션 목록 한 줄(12 §7.2). <c>My*</c>는 내 차 결과(<c>IsPlayer</c> 행)에서 읽고, 없으면 null이다.
/// <see cref="MyBestLapTimeMs"/>는 저장 값 그대로(0 = 기록 없음)이며, null 변환은 서비스가 한다.
/// <see cref="CountryCode"/>는 트랙의 국가 코드, <see cref="MyTeamId"/>는 내 결과의 팀(docs/15 §11.2, 이름·색은 서비스가 푼다).
/// </summary>
public sealed record SessionSummaryRow(
    Guid SessionId,
    DateTime ClassifiedAt,
    string TrackName,
    SessionType SessionType,
    SessionKind SessionKind,
    GameMode GameMode,
    Guid? SeasonId,
    int CarCount,
    int? MyPosition,
    int? MyGridPosition,
    ResultStatus? MyResultStatus,
    int? MyBestLapTimeMs,
    int? MyPoints,
    string GameCode,
    string? CountryCode,
    int? MyTeamId);
