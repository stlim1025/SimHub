namespace SimCenter.Application.Rankings;

/// <summary>
/// 내 트랙별 요약 쿼리 원시 행. 리포지토리 → 서비스 전달용.
/// 최고 기록은 유효(<c>IsValid</c>) 랩 기준이며 유효 랩이 없으면 null이다. 국가·표시 순서는 트랙 마스터 값(D-43).
/// </summary>
public sealed record MyTrackSummaryRow(
    Guid TrackId,
    string TrackName,
    string GameCode,
    int LapCount,
    int? BestValidLapTimeMs,
    DateTime LastSetAt,
    string? CountryCode,
    int DisplayOrder);
