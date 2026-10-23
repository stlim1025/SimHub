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
/// 링크 4개(P7, 12 §4.6)는 선택 필드다 — 백엔드가 <c>Lap.SessionKey</c>를 계산해 P8에서 세션과 연결하는 데 쓴다.
/// 마지막 3개(docs/15 §4.3)도 선택이다 — 차량 스냅샷·주행 조건(D-44)과 1랩 트레이스(D-45). 받은 값이 없으면 null(옛 계약과 같다).
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
    uint SessionLinkId = 0,
    LapCarSnapshot? Car = null,
    LapConditions? Conditions = null,
    LapTrace? Trace = null) : TelemetryEvent(SessionRef)
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
/// <paramref name="IsAiControlled"/>는 false다. <paramref name="LapHistory"/>(D-49, docs/15 §8)는 그 차의 Session History 랩 기록 — 받지 못했으면 null.
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
    IReadOnlyList<TyreStint> TyreStints,
    IReadOnlyList<LapHistoryEntry>? LapHistory = null);

/// <summary>
/// 세션 최종 순위표(D-28). 세션 맥락 + 참가자 정보 + 최종 순위를 한 이벤트에 담은 자기 완결 페이로드다.
/// <paramref name="LapPositions"/>(D-49, docs/15 §8)는 랩별 순위(Lap Positions) — 받지 못했으면 null. 둘 다 P8 세션 상세의 재료다.
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
    IReadOnlyList<ClassifiedResult> Results,
    IReadOnlyList<LapPositionsEntry>? LapPositions = null) : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.SessionClassified;
}

/// <summary>
/// 트랙 형상 표본 조각(헌장 Agent Rules 예외). 오프라인 세션의 모든 차 위치·랩 거리·노면만 추린 표본을 <see cref="Format"/> 배치로 gzip해
/// base64로 싣는다(<see cref="Data"/>). 세션 하나가 여러 조각이 되며 마지막 조각은 <see cref="IsLast"/>다. shared/schema/track_samples_chunk.json.
/// </summary>
public sealed record TrackSamplesChunk(
    string SessionRef,
    int TrackId,
    SessionType SessionType,
    int? TrackLengthM,
    int Format,
    int SampleRateHz,
    int ChunkIndex,
    bool IsLast,
    int FrameCount,
    int SampleCount,
    string Data) : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.TrackSamplesChunk;
}
