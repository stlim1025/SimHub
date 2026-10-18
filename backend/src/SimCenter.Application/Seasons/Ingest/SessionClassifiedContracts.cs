using System.Text.Json;

namespace SimCenter.Application.Seasons.Ingest;

/// <summary>
/// <c>SessionClassified</c> payload(shared/schema/session_classified.json, 12 §5.5). camelCase 계약.
/// enum 필드(<c>SessionType</c>·<c>SessionKind</c>·<c>GameMode</c>·<c>ResultStatus</c>·<c>VisualCompound</c>)는
/// 문자열로 받아 <see cref="Common.LenientEnum"/>으로 해석한다 — 모르는 값을 거부하지 않기 위해서다(12 §6.2-1).
/// <see cref="LapHistory"/>·<see cref="LapPositions"/>(D-49)는 선택 필드라 raw JSON으로 받는다 — 안이 어떻든 파싱이 실패하지 않는다.
/// </summary>
public sealed record SessionClassifiedPayloadDto(
    string SessionRef,
    int TrackId,
    string? SessionType,
    string? SessionKind,
    string? GameMode,
    long SeasonLinkId,
    long WeekendLinkId,
    long SessionLinkId,
    int TotalLaps,
    int AiDifficulty,
    bool IsNetworkGame,
    IReadOnlyList<ClassifiedResultDto>? Results,
    JsonElement? LapHistory = null,
    JsonElement? LapPositions = null);

/// <summary>순위표의 차 1대(12 §5.5 <c>results[]</c>).</summary>
public sealed record ClassifiedResultDto(
    int CarIndex,
    bool IsPlayer,
    int Position,
    int GridPosition,
    int NumLaps,
    int Points,
    int NumPitStops,
    int NumPenalties,
    string? ResultStatus,
    int BestLapTimeMs,
    int TotalRaceTimeMs,
    int PenaltiesTimeMs,
    string? DriverName,
    int? GameDriverId,
    int? TeamId,
    int? RaceNumber,
    bool IsAiControlled,
    IReadOnlyList<TyreStintDto>? TyreStints,
    JsonElement? LapHistory = null);

/// <summary>타이어 스틴트(12 §5.5 <c>tyreStints[]</c>).</summary>
public sealed record TyreStintDto(int EndLap, string? VisualCompound, string? ActualCompound);
