namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 플레이어 차량의 랩 상태 프레임(F1 Lap Data 패킷의 플레이어 인덱스 매핑).
/// 섹터 시간은 분+밀리초를 합산한 총 밀리초로 전달한다(Infrastructure에서 합산).
/// </summary>
public sealed record LapFrame(
    string SessionRef,
    int CurrentLapNumber,
    int CurrentSector,          // 0=S1, 1=S2, 2=S3 (진행 중 섹터)
    int Sector1TimeMs,          // 확정 시 유효(진행 전 0)
    int Sector2TimeMs,
    int LastLapTimeMs,          // 직전 완료 랩 총시간
    bool IsCurrentLapInvalid,
    bool IsOutOrInLap) : ITelemetryFrame;
