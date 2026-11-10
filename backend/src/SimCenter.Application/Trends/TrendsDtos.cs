namespace SimCenter.Application.Trends;

/// <summary>
/// 내 성과 추세(Trends 화면). 모두 시간 순(오래된 것부터)이다.
/// <see cref="Races"/> = 레이스마다 순위·AI 난이도·팀메이트 대비 페이스·필드 대비 페이스·꾸준함,
/// <see cref="Qualifying"/> = 주말마다 예선 순위·팀메이트 대비 차이, <see cref="WeeklyLaps"/> = 주(월요일 시작, UTC)마다 달린 랩 수,
/// <see cref="Tracks"/> = 트랙마다 세션 최고 랩과 그때까지의 최고 랩(랩이 많은 트랙부터).
/// </summary>
public sealed record TrendsDto(
    IReadOnlyList<RaceTrendDto> Races,
    IReadOnlyList<QualifyingTrendDto> Qualifying,
    IReadOnlyList<WeeklyLapsDto> WeeklyLaps,
    IReadOnlyList<TrackProgressionDto> Tracks);

/// <summary>
/// 레이스 한 판. <see cref="TeammatePaceGapPerLapMs"/> = 팀메이트 대비 랩당 평균 차이(둘 다 완주·같은 랩일 때, 음수 = 내가 빠름),
/// <see cref="FieldPaceGapPercent"/> = 내 최고 랩 대 AI 최고 랩 중앙값(%, 음수 = 내가 빠름),
/// <see cref="ConsistencyMs"/> = 깨끗한 랩(첫 랩 제외, 중앙값의 107% 이내)의 표준편차 — 작을수록 꾸준하다.
/// </summary>
public sealed record RaceTrendDto(
    Guid SessionId,
    DateTime ClassifiedAt,
    string TrackName,
    string? CountryCode,
    string SessionKind,
    bool IsSprint,
    string GameMode,
    int? AiDifficulty,
    int? Grid,
    int? Position,
    string? ResultStatus,
    int? TeammatePaceGapPerLapMs,
    double? FieldPaceGapPercent,
    int? ConsistencyMs,
    int? CleanLaps);

/// <summary>주말 예선 하나: 마지막으로 달린 단계의 순위와 팀메이트 대비 최고 랩 차이(음수 = 내가 빠름).</summary>
public sealed record QualifyingTrendDto(
    Guid WeekendId,
    DateTime At,
    string TrackName,
    string? CountryCode,
    int? AiDifficulty,
    int? Position,
    int? TeammateGapMs,
    double? TeammateGapPercent);

/// <summary>한 주(월요일 시작, UTC 날짜)에 달린 랩 수. 랩이 없던 주도 0으로 넣는다.</summary>
public sealed record WeeklyLapsDto(DateOnly WeekStart, int Laps);

/// <summary>트랙 하나의 최고 랩 변화. <see cref="LapCount"/> = 그 트랙의 내 랩 수(무효 포함).</summary>
public sealed record TrackProgressionDto(
    Guid TrackId,
    string TrackName,
    string? CountryCode,
    int LapCount,
    IReadOnlyList<TrackProgressionPointDto> Points);

/// <summary>세션 하나(세션을 모르면 하루): 그 세션의 유효 최고 랩과 그때까지의 최고 랩, 그 최고 랩의 세션 종류.</summary>
public sealed record TrackProgressionPointDto(DateTime At, string SessionType, int SessionBestMs, int BestSoFarMs);
