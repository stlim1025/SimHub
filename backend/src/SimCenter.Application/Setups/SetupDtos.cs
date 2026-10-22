namespace SimCenter.Application.Setups;

/// <summary>셋업 트랙 메뉴 한 줄: 게임의 트랙(캘린더 순, 리버스 포함)과 조건별 셋업 수(0 가능).</summary>
public sealed record SetupTrackDto(
    Guid TrackId,
    string Name,
    string? CountryCode,
    int DisplayOrder,
    string? CircuitName,
    int DryCount,
    int WetCount);

/// <summary>셋업 화면의 트랙 머리.</summary>
public sealed record SetupTrackRefDto(Guid TrackId, string Name, string? CountryCode, string? CircuitName);

/// <summary>셋업 목록 한 줄.</summary>
public sealed record SetupListItemDto(
    Guid Id,
    int Rank,
    string? TeamName,
    string? SessionType,
    int LapTimeMs,
    string SourceUrl);

/// <summary>트랙·조건의 셋업 목록. <see cref="FetchedAt"/> = 마지막으로 출처를 읽은 시각(셋업이 없으면 null).</summary>
public sealed record SetupListResponse(
    SetupTrackRefDto Track,
    string Condition,
    DateTime? FetchedAt,
    IReadOnlyList<SetupListItemDto> Items);

/// <summary>셋업 상세. <see cref="SetOn"/> = <c>yyyy-MM-dd</c> 또는 null.</summary>
public sealed record SetupDetailDto(
    Guid Id,
    int Rank,
    string GameCode,
    SetupTrackRefDto Track,
    string Condition,
    string? TeamName,
    string? SessionType,
    int LapTimeMs,
    string? Steering,
    string? SetOn,
    string SourceUrl,
    DateTime FetchedAt,
    IReadOnlyList<SetupSectionDto> Sections);
