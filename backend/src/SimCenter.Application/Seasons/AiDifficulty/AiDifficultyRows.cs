using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.AiDifficulty;

/// <summary>
/// AI 난이도 가이드가 읽는 시즌 세션 결과 한 줄(예선·레이스만, 가져온 세션 제외). 시간은 ms, 0 = 기록 없음.
/// <see cref="SessionKey"/>는 같은 세션의 내 랩(날씨 스냅샷)과 잇는 키다.
/// </summary>
public sealed record AiPaceRow(
    Guid WeekendId,
    Guid SessionId,
    string SessionKey,
    SessionType SessionType,
    SessionKind SessionKind,
    DateTime ClassifiedAt,
    int AiDifficulty,
    string DriverKey,
    string? DriverName,
    int CarIndex,
    int? TeamId,
    bool IsPlayer,
    bool IsAiControlled,
    int Position,
    int GridPosition,
    ResultStatus ResultStatus,
    int BestLapTimeMs,
    int TotalRaceTimeMs,
    int NumLaps);

/// <summary>세션(<see cref="SessionKey"/>)에서 내가 달린 랩 하나의 끝 날씨.</summary>
public sealed record SessionLapWeatherRow(string SessionKey, Weather Weather);

/// <summary>내 유효한 타임트라이얼 랩 하나(트랙, 시간, 랩 끝 날씨 — 모르면 null).</summary>
public sealed record TimeTrialLapRow(Guid TrackId, int LapTimeMs, Weather? Weather);
