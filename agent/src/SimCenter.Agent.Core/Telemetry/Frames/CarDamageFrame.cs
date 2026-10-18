namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 플레이어 차의 마모·손상(F1 Car Damage 패킷의 플레이어 칸, docs/15 §3.1). 모든 값은 퍼센트(0~100).
/// 바퀴 값은 이름으로 담는다(<see cref="WheelSet{T}"/>).
/// </summary>
public sealed record CarDamageFrame(
    string SessionRef,
    WheelSet<float> TyreWearPercent,
    WheelSet<int> TyreDamagePercent,
    WheelSet<int> BrakeDamagePercent,
    int FrontLeftWingDamage,
    int FrontRightWingDamage,
    int RearWingDamage,
    int FloorDamage,
    int DiffuserDamage,
    int SidepodDamage,
    int GearboxDamage,
    int EngineDamage) : ITelemetryFrame;
