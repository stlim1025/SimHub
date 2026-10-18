namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>
/// 랩 끝 차량 스냅샷 — LapFinished <c>car</c>(D-44, docs/15 §4.2·§4.3). 필드마다 null 가능: 받지 못한 값, 또는 랩 중간에 Agent가 시작해
/// 시작 값이 없는 경우다. "끝" 값은 랩이 바뀌기 직전 마지막 값, "시작" 값은 새 랩이 시작된 뒤 처음 받은 값이다(§3.2).
/// 이 랩 사용량(연료·ERS·마모 증가)은 앱이 시작 − 끝으로 계산한다. 팀·컴파운드는 게임 원시 ID, ERS는 정수 줄(J).
/// </summary>
public sealed record LapCarSnapshot(
    int? TeamId,
    int? VisualTyreCompound,
    int? ActualTyreCompound,
    int? TyreAgeLaps,
    WheelSet<float>? TyreWearStart,
    WheelSet<float>? TyreWearEnd,
    WheelSet<int>? TyreDamage,
    WheelSet<int>? BrakeDamage,
    int? FrontLeftWingDamage,
    int? FrontRightWingDamage,
    int? RearWingDamage,
    int? FloorDamage,
    int? DiffuserDamage,
    int? SidepodDamage,
    int? GearboxDamage,
    int? EngineDamage,
    float? FuelStartKg,
    float? FuelEndKg,
    float? FuelRemainingLaps,
    int? ErsStoreStartJ,
    int? ErsStoreEndJ,
    int? ErsDeployedJ,
    int? ErsHarvestedJ);

/// <summary>랩 끝의 주행 조건 — LapFinished <c>conditions</c>(D-44, docs/15 §4.2). 기온은 섭씨, 비 예보는 퍼센트. 필드마다 null 가능.</summary>
public sealed record LapConditions(
    Weather? Weather,
    int? AirTempC,
    int? TrackTempC,
    int? RainForecastPercent);
