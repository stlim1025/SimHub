using System.Text.Json;
using SimCenter.Application.Seasons.Queries.Detail;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 세션 목록 한 줄(12 §7.2 + docs/15 §11.4 D-53). 내 차 결과가 없으면 <c>My*</c> 전부 null, 시즌이 없으면 <see cref="SeasonId"/>·<see cref="SeasonNumber"/>가 null.
/// <see cref="MyBestLapTimeMs"/>는 0(기록 없음)이면 null이다. 열거형은 문자열로 직렬화한다.
/// <see cref="SeasonNumber"/> = 같은 게임·모드의 내 시즌 순번(1부터, <see cref="SeasonNumbering"/>).
/// <c>My*</c> 순위는 모르면(0) null. <see cref="IsSprintWeekend"/> = 같은 주말에 Race2가 있다 — 그러면 Race = 스프린트(<see cref="SessionPositions"/>).
/// </summary>
public sealed record SessionSummaryDto(
    Guid SessionId,
    DateTime ClassifiedAt,
    string TrackName,
    string SessionType,
    string SessionKind,
    string GameMode,
    Guid? SeasonId,
    int CarCount,
    int? MyPosition,
    int? MyGridPosition,
    string? MyResultStatus,
    int? MyBestLapTimeMs,
    int? MyPoints,
    string? CountryCode,
    MyTeamDto? MyTeam,
    int? SeasonNumber,
    bool IsSprintWeekend);

/// <summary>
/// 세션 상세: 헤더 + 결과(<c>Position</c> 오름차순, 같으면 <c>CarIndex</c>) + F1Laps 카드 재료(docs/15 §11.4 D-53).
/// 데이터가 없는 카드 재료는 null·빈 목록이다.
/// </summary>
public sealed record SessionDetailDto(
    SessionDetailHeaderDto Session,
    IReadOnlyList<SessionResultDto> Results,
    IReadOnlyList<QualifyingPositionDto> QualifyingPositions,
    MyBestLapDto? MyBestLap,
    JsonElement? Setup,
    IReadOnlyList<SessionLapDto> Laps,
    EngineWearDto? EngineWear,
    IReadOnlyList<TyreStintSeriesDto> TyreStints,
    IReadOnlyList<SessionPenaltyDto> Penalties);

/// <summary>
/// 세션 상세 헤더 = <see cref="SessionSummaryDto"/>의 모든 필드 + 세션 설정. 시즌에 속하면 <see cref="Round"/>는
/// 시즌 상세의 라운드 번호와 같은 계산(<see cref="RoundNumbering"/>)이고, 아니면 null.
/// <see cref="Weather"/>는 세션 마지막 내 랩 스냅샷의 날씨 이름(없으면 null, docs/15 §11.3 Conditions).
/// </summary>
public sealed record SessionDetailHeaderDto(
    Guid SessionId,
    DateTime ClassifiedAt,
    string TrackName,
    string SessionType,
    string SessionKind,
    string GameMode,
    Guid? SeasonId,
    int CarCount,
    int? MyPosition,
    int? MyGridPosition,
    string? MyResultStatus,
    int? MyBestLapTimeMs,
    int? MyPoints,
    int TotalLaps,
    int AiDifficulty,
    bool IsNetworkGame,
    int? Round,
    string? CountryCode,
    MyTeamDto? MyTeam,
    int? SeasonNumber,
    string? Weather,
    bool IsSprintWeekend,
    bool HasFieldSamples = false);

/// <summary>
/// 세션 결과 한 줄(차 1대). <see cref="BestLapTimeMs"/>·<see cref="TotalRaceTimeMs"/>는 0이면 null,
/// <see cref="IsFastestLap"/>은 기록이 있는 행 중 최소값(같으면 모두 true). 팀 정보가 없으면 <see cref="TeamId"/>는 null이고 팀 이름은 <c>Unknown Team</c>.
/// <see cref="GapMs"/>·<see cref="PositionChange"/>는 <see cref="ClassificationGaps"/> 규칙(docs/15 §11.4).
/// </summary>
public sealed record SessionResultDto(
    int Position,
    int CarIndex,
    string Name,
    int? TeamId,
    string TeamName,
    string TeamColor,
    int? RaceNumber,
    bool IsAiControlled,
    bool IsPlayer,
    int GridPosition,
    int NumLaps,
    int? BestLapTimeMs,
    bool IsFastestLap,
    int? TotalRaceTimeMs,
    int PenaltiesTimeMs,
    int NumPenalties,
    int NumPitStops,
    int Points,
    string ResultStatus,
    IReadOnlyList<TyreStintViewDto> TyreStints,
    int? GapMs,
    int? PositionChange);

/// <summary>타이어 스틴트(스틴트 번호 순서대로 담긴다).</summary>
public sealed record TyreStintViewDto(int EndLap, string VisualCompound, string? ActualCompound);
