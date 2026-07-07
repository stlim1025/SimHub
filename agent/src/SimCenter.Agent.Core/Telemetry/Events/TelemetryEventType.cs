namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>Agent가 생성하는 도메인 이벤트 유형(shared/schema telemetry_envelope enum과 일치).</summary>
public enum TelemetryEventType
{
    SessionStarted,
    LapStarted,
    SectorCompleted,
    LapFinished,
    SessionEnded,
}
