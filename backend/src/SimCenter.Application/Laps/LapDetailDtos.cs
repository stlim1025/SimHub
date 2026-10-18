using System.Text.Json;
using SimCenter.Application.Rankings;

namespace SimCenter.Application.Laps;

/// <summary>
/// 랩 상세(<c>GET /me/laps/{lapId}</c>, 15 §4.2). <see cref="SessionId"/> = 같은 세션 키의 내 세션(없으면 null),
/// <see cref="Car"/>·<see cref="Conditions"/> = 스냅샷(없으면 null, 안의 값도 각각 null 가능),
/// <see cref="Comparison"/> = 같은 트랙·게임의 내 최고 유효 랩(이 랩일 수도 있음, 없으면 null).
/// </summary>
public sealed record LapDetailResponse(
    LapDto Lap,
    Guid TrackId,
    string? CountryCode,
    Guid? SessionId,
    LapCarSnapshotDto? Car,
    LapConditionsDto? Conditions,
    LapComparisonDto? Comparison);

/// <summary>
/// 랩 끝의 차량 스냅샷(D-44). 바퀴 묶음은 4개 값이 모두 있을 때만 보인다. 퍼센트 0~100, 연료 kg, ERS J.
/// <see cref="TeamId"/> = 게임 팀 ID(이름·색은 <c>lap.team</c>). <see cref="Details"/> = 그 밖의 값 묶음(D-49, 받은 JSON 객체 그대로, 없으면 null).
/// </summary>
public sealed record LapCarSnapshotDto(
    int? TeamId,
    int? VisualTyreCompound,
    int? ActualTyreCompound,
    int? TyreAgeLaps,
    WheelValuesDto? TyreWearStart,
    WheelValuesDto? TyreWearEnd,
    WheelValuesDto? TyreDamage,
    WheelValuesDto? BrakeDamage,
    int? FrontLeftWingDamage,
    int? FrontRightWingDamage,
    int? RearWingDamage,
    int? FloorDamage,
    int? DiffuserDamage,
    int? SidepodDamage,
    int? GearboxDamage,
    int? EngineDamage,
    double? FuelStartKg,
    double? FuelEndKg,
    double? FuelRemainingLaps,
    double? ErsStoreStartJ,
    double? ErsStoreEndJ,
    double? ErsDeployedJ,
    double? ErsHarvestedJ,
    JsonElement? Details);

/// <summary>바퀴 4개 값.</summary>
public sealed record WheelValuesDto(double FrontLeft, double FrontRight, double RearLeft, double RearRight);

/// <summary>랩 끝의 날씨(D-44). <see cref="Weather"/> = <c>Clear·LightCloud·Overcast·LightRain·HeavyRain·Storm</c>, 모르면 null.</summary>
public sealed record LapConditionsDto(string? Weather, int? AirTempC, int? TrackTempC, int? RainForecastPercent);

/// <summary>비교 대상 랩(D-46): 내 최고 유효 랩.</summary>
public sealed record LapComparisonDto(
    Guid LapId,
    int LapTimeMs,
    IReadOnlyList<LapSectorDto> Sectors,
    DateTime SetAt,
    bool HasTrace);

/// <summary>
/// 랩 트레이스(<c>GET /me/laps/{lapId}/trace</c>, 15 §4.2): 거리 <see cref="ResolutionM"/>m 간격 표본 7채널, 모두 <see cref="SampleCount"/> 길이.
/// <see cref="Extra"/> = 추가 채널 맵(D-49, 이름 → 같은 길이의 실수 배열). 없으면 빈 맵(null이 아니다).
/// </summary>
public sealed record LapTraceResponse(
    Guid LapId,
    int ResolutionM,
    int SampleCount,
    IReadOnlyList<int> TimeMs,
    IReadOnlyList<int> SpeedKph,
    IReadOnlyList<int> Throttle,
    IReadOnlyList<int> Brake,
    IReadOnlyList<int> Steer,
    IReadOnlyList<int> Gear,
    IReadOnlyList<int> Rpm,
    IReadOnlyDictionary<string, double[]> Extra);
