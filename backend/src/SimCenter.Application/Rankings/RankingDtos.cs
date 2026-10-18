namespace SimCenter.Application.Rankings;

/// <summary>트랙·기간별 TOP N 스냅샷(04 §3.7). SignalR RankingUpdated 브로드캐스트에도 재사용한다(05 §3.4).</summary>
public sealed record RankingSnapshotDto(
    Guid TrackId,
    string TrackName,
    string GameCode,
    string Period,
    string PeriodKey,
    IReadOnlyList<RankingEntryDto> Entries);

/// <summary>랭킹 한 줄(유저별 최고 랩).</summary>
public sealed record RankingEntryDto(int Rank, string DisplayName, int BestLapTimeMs, DateTime SetAt);

/// <summary>
/// 랭킹 쿼리 원시 행(순위 미부여). 리포지토리 → 서비스 전달용.
/// <paramref name="ShowOnLeaderboard"/>가 false면 서비스가 표시 이름을 익명으로 바꾼다(<see cref="RankingPrivacy"/>).
/// 기본값을 두지 않는다 — 만드는 쪽이 공개 여부를 반드시 정하게 해서, 빠뜨려 비공개 사용자의 이름이 새는 일을 막는다.
/// </summary>
public sealed record RankingLapRow(
    Guid UserId,
    string DisplayName,
    int LapTimeMs,
    DateTime SetAt,
    bool ShowOnLeaderboard);

/// <summary>트랙 마스터 항목(04 §3.8). 국가(ISO 3166-1 alpha-2, 모르면 null)·표시 순서(D-43)를 함께 내린다.</summary>
public sealed record TrackDto(Guid TrackId, string GameCode, string Name, string? CountryCode, int DisplayOrder);

/// <summary>트랙 목록 응답.</summary>
public sealed record TrackListResponse(IReadOnlyList<TrackDto> Items);

/// <summary>내 랩 기록 응답(04 §3.9).</summary>
public sealed record MyLapsResponse(PersonalBestDto? PersonalBest, PagedResult<LapDto> Laps);

/// <summary>
/// 내 트랙별 요약 한 줄(11 §8). 최고 기록은 유효 랩 기준이며 유효 랩이 없으면 null.
/// 국가·표시 순서(D-43)는 트랙 메뉴용이며, 목록 순서는 그대로 마지막 주행 순이다.
/// </summary>
public sealed record MyTrackDto(
    Guid TrackId,
    string TrackName,
    string GameCode,
    int LapCount,
    int? BestValidLapTimeMs,
    DateTime LastSetAt,
    string? CountryCode,
    int DisplayOrder);

/// <summary>내 트랙 요약 응답(마지막으로 랩을 세운 트랙 우선).</summary>
public sealed record MyTracksResponse(IReadOnlyList<MyTrackDto> Items);

/// <summary>개인 최고 기록(랭킹 적격 기준).</summary>
public sealed record PersonalBestDto(Guid TrackId, int LapTimeMs, DateTime SetAt);

/// <summary>
/// 개별 랩(무효 랩 포함, D-15/D-16). 15 §4.2 추가 필드: 랩 번호, 게임 모드(옛 랩 null), 팀(스냅샷의 팀 ID → <c>TeamCatalog</c>, 없으면 null),
/// 날씨(<c>Weather</c> 이름, 모르면 null), 트레이스 유무.
/// 봉인하지 않는다 — 실시간 <c>LapRecorded</c>가 같은 필드에 trackId만 더해 평평하게 보낸다(docs/15 §9, D-50).
/// </summary>
public record LapDto(
    Guid LapId,
    string TrackName,
    string GameCode,
    string SessionType,
    int LapTimeMs,
    IReadOnlyList<LapSectorDto> Sectors,
    bool IsValid,
    bool IsRankingEligible,
    DateTime SetAt,
    int LapNumber,
    string? GameMode,
    TeamRefDto? Team,
    string? Weather,
    bool HasTrace);

/// <summary>팀 표시 이름과 색(<c>#RRGGBB</c>, D-33).</summary>
public sealed record TeamRefDto(string Name, string Color);

/// <summary>가변 섹터(D-7).</summary>
public sealed record LapSectorDto(int SectorNumber, int SectorTimeMs);

/// <summary>공통 페이징 래퍼(04 §5).</summary>
public sealed record PagedResult<T>(int Page, int PageSize, int Total, IReadOnlyList<T> Items);
