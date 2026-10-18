namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 플레이어 차의 상태(F1 Car Status 패킷의 플레이어 칸, docs/15 §3.1). 랩 스냅샷(D-44)의 연료·ERS·타이어 원천이다.
/// ERS 값은 줄(J), "이 랩" 값은 게임이 랩마다 0으로 되돌린다. 컴파운드는 게임 원시 값(F1: 실제 16=C5 … 18=C3, 표시 16=Soft·17=Medium·18=Hard).
/// </summary>
public sealed record CarStatusFrame(
    string SessionRef,
    float FuelInTankKg,
    float FuelRemainingLaps,
    float ErsStoreEnergyJ,
    float ErsDeployedThisLapJ,
    float ErsHarvestedThisLapMgukJ,
    float ErsHarvestedThisLapMguhJ,
    int ActualTyreCompound,
    int VisualTyreCompound,
    int TyreAgeLaps) : ITelemetryFrame;
