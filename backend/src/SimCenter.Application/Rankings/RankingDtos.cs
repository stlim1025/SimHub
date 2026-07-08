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

/// <summary>랭킹 쿼리 원시 행(순위 미부여). 리포지토리 → 서비스 전달용.</summary>
public sealed record RankingLapRow(Guid UserId, string DisplayName, int LapTimeMs, DateTime SetAt);

/// <summary>트랙 마스터 항목(04 §3.8).</summary>
public sealed record TrackDto(Guid TrackId, string GameCode, string Name);

/// <summary>트랙 목록 응답.</summary>
public sealed record TrackListResponse(IReadOnlyList<TrackDto> Items);

/// <summary>내 랩 기록 응답(04 §3.9).</summary>
public sealed record MyLapsResponse(PersonalBestDto? PersonalBest, PagedResult<LapDto> Laps);

/// <summary>개인 최고 기록(랭킹 적격 기준).</summary>
public sealed record PersonalBestDto(Guid TrackId, int LapTimeMs, DateTime SetAt);

/// <summary>개별 랩(무효 랩 포함, D-15/D-16).</summary>
public sealed record LapDto(
    Guid LapId,
    string TrackName,
    string GameCode,
    string SessionType,
    int LapTimeMs,
    IReadOnlyList<LapSectorDto> Sectors,
    bool IsValid,
    bool IsRankingEligible,
    DateTime SetAt);

/// <summary>가변 섹터(D-7).</summary>
public sealed record LapSectorDto(int SectorNumber, int SectorTimeMs);

/// <summary>공통 페이징 래퍼(04 §5).</summary>
public sealed record PagedResult<T>(int Page, int PageSize, int Total, IReadOnlyList<T> Items);
