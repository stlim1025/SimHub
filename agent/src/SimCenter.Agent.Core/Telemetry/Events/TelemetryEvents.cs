namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>Agent 도메인 이벤트 페이로드 베이스. <see cref="Type"/>로 envelope 타입을 확정한다.</summary>
public abstract record TelemetryEvent(string SessionRef)
{
    public abstract TelemetryEventType Type { get; }
}

/// <summary>세션 시작(트랙·세션타입 포함). shared/schema/session_started.json.</summary>
public sealed record SessionStarted(string SessionRef, int TrackId, SessionType SessionType)
    : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.SessionStarted;
}

/// <summary>랩 시작. shared/schema/lap_started.json.</summary>
public sealed record LapStarted(string SessionRef, int LapNumber)
    : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.LapStarted;
}

/// <summary>섹터 완료. shared/schema/sector_completed.json.</summary>
public sealed record SectorCompleted(string SessionRef, int LapNumber, int SectorNumber, int SectorTimeMs)
    : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.SectorCompleted;
}

/// <summary>단일 섹터 기록(가변 섹터, D-7).</summary>
public sealed record LapSectorDto(int SectorNumber, int SectorTimeMs);

/// <summary>
/// 랩 완주. shared/schema/lap_finished.json (+ sessionType — docs/06 예시·샘플과 일치, 스키마 보강 예정).
/// 무효/아웃/인랩도 전송하며 랭킹 적격 판정은 Backend가 수행(D-15).
/// 뒤쪽 4개(P7, 12 §4.6)는 선택 필드다 — 백엔드가 <c>Lap.SessionKey</c>를 계산해 P8에서 세션과 연결하는 데 쓴다.
/// </summary>
public sealed record LapFinished(
    string SessionRef,
    int LapNumber,
    int LapTimeMs,
    IReadOnlyList<LapSectorDto> Sectors,
    bool IsValid,
    bool IsOutOrInLap,
    int TrackId,
    SessionType SessionType,
    GameMode GameMode = GameMode.Other,
    uint SeasonLinkId = 0,
    uint WeekendLinkId = 0,
    uint SessionLinkId = 0) : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.LapFinished;
}

/// <summary>세션 종료. shared/schema/session_ended.json.</summary>
public sealed record SessionEnded(string SessionRef) : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.SessionEnded;
}

/// <summary>
/// 순위표의 차 1대(12 §5.5 <c>results[]</c>). 이름·드라이버·팀·번호는 참가자 정보를 받지 못한 차에서 null,
/// <paramref name="IsAiControlled"/>는 false다.
/// </summary>
public sealed record ClassifiedResult(
    int CarIndex,
    bool IsPlayer,
    int Position,
    int GridPosition,
    int NumLaps,
    int Points,
    int NumPitStops,
    int NumPenalties,
    ResultStatus ResultStatus,
    int BestLapTimeMs,
    int TotalRaceTimeMs,
    int PenaltiesTimeMs,
    string? DriverName,
    int? GameDriverId,
    int? TeamId,
    int? RaceNumber,
    bool IsAiControlled,
    IReadOnlyList<TyreStint> TyreStints);

/// <summary>
/// 세션 최종 순위표(D-28). 세션 맥락 + 참가자 정보 + 최종 순위를 한 이벤트에 담은 자기 완결 페이로드다.
/// shared/schema/session_classified.json.
/// </summary>
public sealed record SessionClassified(
    string SessionRef,
    int TrackId,
    SessionType SessionType,
    SessionKind SessionKind,
    GameMode GameMode,
    uint SeasonLinkId,
    uint WeekendLinkId,
    uint SessionLinkId,
    int TotalLaps,
    int AiDifficulty,
    bool IsNetworkGame,
    IReadOnlyList<ClassifiedResult> Results) : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.SessionClassified;
}
