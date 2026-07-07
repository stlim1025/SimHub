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
/// </summary>
public sealed record LapFinished(
    string SessionRef,
    int LapNumber,
    int LapTimeMs,
    IReadOnlyList<LapSectorDto> Sectors,
    bool IsValid,
    bool IsOutOrInLap,
    int TrackId,
    SessionType SessionType) : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.LapFinished;
}

/// <summary>세션 종료. shared/schema/session_ended.json.</summary>
public sealed record SessionEnded(string SessionRef) : TelemetryEvent(SessionRef)
{
    public override TelemetryEventType Type => TelemetryEventType.SessionEnded;
}
