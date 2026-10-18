using SimCenter.Application.Rankings;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Laps;

/// <summary>
/// 내 랩 목록·상세·비교가 함께 쓰는 읽기 행(15 §4.2). 리포지토리가 한 쿼리 프로젝션으로 만든다 —
/// 트랙 이름·국가, 스냅샷의 팀·날씨, 트레이스 유무, 섹터를 랩마다 따로 읽지 않는다(N+1 없음).
/// </summary>
public sealed record LapRow(
    Guid LapId,
    Guid TrackId,
    string TrackName,
    string? CountryCode,
    string GameCode,
    SessionType SessionType,
    int LapNumber,
    int LapTimeMs,
    bool IsValid,
    bool IsRankingEligible,
    DateTime SetAt,
    string? GameMode,
    string? SessionKey,
    int? TeamId,
    Weather? Weather,
    bool HasTrace,
    IReadOnlyList<LapSectorDto> Sectors);

/// <summary>
/// 내 랩 목록 필터(04 §3.11, 15 §4.2). <see cref="ValidOnly"/> = 게임 판정 유효(<c>IsValid</c>) 랩만 — <c>bestValidLapTimeMs</c>와 같은 기준.
/// </summary>
public sealed record MyLapsFilter(Guid? TrackId, SessionType? SessionType, bool ValidOnly);
