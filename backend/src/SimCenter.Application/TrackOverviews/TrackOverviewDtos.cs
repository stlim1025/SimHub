namespace SimCenter.Application.TrackOverviews;

/// <summary>트랙 개요의 트랙 정보(정적 카탈로그 포함, 모르는 칸은 null).</summary>
public sealed record TrackOverviewTrackDto(
    Guid TrackId,
    string Name,
    string? CountryCode,
    string GameCode,
    string? CircuitName,
    string? GrandPrixName,
    double? LengthKm,
    string? F1LapRecord);

/// <summary>이 트랙의 내 통계. 랩이 없으면 개수 0, 나머지 null.</summary>
public sealed record TrackMyStatsDto(
    int LapCount,
    int SessionCount,
    int? BestLapMs,
    int? BestTimeTrialLapMs,
    int? AverageLapMs,
    double? AverageAiDifficulty);

/// <summary>전체 기간 Time Trial 상위 한 줄. 이름은 랭킹 공개 설정(D-39)을 따른다.</summary>
public sealed record TrackTopLapDto(int Rank, string DisplayName, string? TeamName, int LapTimeMs, Guid LapId);

/// <summary>내 최고 랩 한 줄.</summary>
public sealed record TrackMyLapDto(Guid LapId, int LapTimeMs, string SessionType, string? TeamName, bool IsValid, DateTime SetAt);

/// <summary>
/// 트랙 개요 응답. <see cref="MapLapId"/> = 트랙 지도를 그릴 수 있는(월드 위치 채널이 있는 트레이스) 내 가장 빠른 랩, 없으면 null.
/// </summary>
public sealed record TrackOverviewResponse(
    TrackOverviewTrackDto Track,
    TrackMyStatsDto MyStats,
    IReadOnlyList<TrackTopLapDto> TopTimeTrial,
    IReadOnlyList<TrackMyLapDto> MyBestLaps,
    Guid? MapLapId);
