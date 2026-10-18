using System.Text.Json;

namespace SimCenter.Application.Laps.Ingest;

/// <summary>
/// LapFinished <c>car</c>(15 §4.3, D-44): 랩 끝의 차량 스냅샷 + 게임 팀 ID. 모든 필드는 선택(null = Agent가 받지 못함).
/// 정수 필드(컴파운드·나이·손상%·팀)는 정수, 마모·바퀴 손상·연료·ERS는 실수다. ERS는 J, 배터리 최대 4MJ.
/// <see cref="Details"/>(D-49)는 그 밖의 값 묶음(임의 JSON 객체)이라 raw로 받는다 — 안이 어떻든 car 해석이 실패하지 않는다.
/// </summary>
public sealed record LapCarPayload(
    int? TeamId = null,
    int? VisualTyreCompound = null,
    int? ActualTyreCompound = null,
    int? TyreAgeLaps = null,
    WheelValuesPayload? TyreWearStart = null,
    WheelValuesPayload? TyreWearEnd = null,
    WheelValuesPayload? TyreDamage = null,
    WheelValuesPayload? BrakeDamage = null,
    int? FrontLeftWingDamage = null,
    int? FrontRightWingDamage = null,
    int? RearWingDamage = null,
    int? FloorDamage = null,
    int? DiffuserDamage = null,
    int? SidepodDamage = null,
    int? GearboxDamage = null,
    int? EngineDamage = null,
    double? FuelStartKg = null,
    double? FuelEndKg = null,
    double? FuelRemainingLaps = null,
    double? ErsStoreStartJ = null,
    double? ErsStoreEndJ = null,
    double? ErsDeployedJ = null,
    double? ErsHarvestedJ = null,
    JsonElement? Details = null);

/// <summary>바퀴 4개 값(이름 기준 — UDP 배열 순서 RL·RR·FL·FR은 Agent가 이름으로 옮긴다). 묶음이 오면 4개가 모두 있어야 한다.</summary>
public sealed record WheelValuesPayload(
    double? FrontLeft = null,
    double? FrontRight = null,
    double? RearLeft = null,
    double? RearRight = null);

/// <summary>LapFinished <c>conditions</c>(15 §4.2): 날씨 이름(<c>Weather</c> enum 이름), 기온·노면 온도(°C), 비 예보(%).</summary>
public sealed record LapConditionsPayload(
    string? Weather = null,
    int? AirTempC = null,
    int? TrackTempC = null,
    int? RainForecastPercent = null);

/// <summary>
/// LapFinished <c>trace</c>(15 §3.3, D-45): 거리 <see cref="ResolutionM"/>m 간격 표본 7채널, 모두 같은 길이의 정수 배열.
/// throttle·brake 0~100, steer −100~100, gear −1~8(0=N, −1=R).
/// <see cref="Extra"/>(D-49)는 <c>{채널이름: number[]}</c> 선택 맵이라 raw로 받는다 — 틀려도 7채널은 그대로 저장한다.
/// </summary>
public sealed record LapTracePayload(
    int? ResolutionM = null,
    int[]? TimeMs = null,
    int[]? SpeedKph = null,
    int[]? Throttle = null,
    int[]? Brake = null,
    int[]? Steer = null,
    int[]? Gear = null,
    int[]? Rpm = null,
    JsonElement? Extra = null);
