using SimCenter.Application.Seasons.AiDifficulty;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Trends;

/// <summary>
/// 추세가 읽는 내 세션의 결과 한 줄(예선·레이스). <see cref="Result"/>의 주말 Id는 주말이 없으면 <see cref="Guid.Empty"/>다
/// (<see cref="HasWeekend"/> = false).
/// </summary>
public sealed record TrendResultRow(
    AiPaceRow Result,
    string GameCode,
    GameMode GameMode,
    Guid TrackId,
    bool IsImported,
    bool HasWeekend);

/// <summary>내 랩 한 줄(모든 세션 종류). <see cref="IsValid"/> = 게임 유효이고 수동 무효가 아님.</summary>
public sealed record TrendLapRow(
    Guid TrackId,
    string? SessionKey,
    SessionType SessionType,
    int LapNumber,
    int LapTimeMs,
    bool IsValid,
    DateTime SetAt);

/// <summary>트랙 표시 이름과 국가 코드.</summary>
public sealed record TrendTrackLabel(string Name, string? CountryCode);
