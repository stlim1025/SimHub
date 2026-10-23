using System.Text.Json;
using SimCenter.Application.Rankings;

namespace SimCenter.Application.Laps;

/// <summary>
/// 랩 상세(<c>GET /me/laps/{lapId}</c>, 15 §4.2). <see cref="SessionId"/> = 같은 세션 키의 내 세션(없으면 null),
/// <see cref="Car"/>·<see cref="Conditions"/> = 스냅샷(없으면 null, 안의 값도 각각 null 가능),
/// <see cref="Assists"/> = 드라이버 어시스트(D-51, 하나도 모르면 null),
/// <see cref="Comparison"/> = 고른 비교 대상(docs/15 §10, D-51 — 기본 = 같은 트랙·게임의 내 최고 유효 랩, 이 랩일 수도 있음).
/// 비교 대상이 null이면 <see cref="ComparisonUnavailable"/>가 까닭이다(<see cref="LapComparisonUnavailable"/>, <c>compare=none</c>이면 둘 다 null).
/// </summary>
public sealed record LapDetailResponse(
    LapDto Lap,
    Guid TrackId,
    string? CountryCode,
    Guid? SessionId,
    LapCarSnapshotDto? Car,
    LapConditionsDto? Conditions,
    LapAssistsDto? Assists,
    LapComparisonDto? Comparison,
    string? ComparisonUnavailable);

/// <summary>
/// 공유 링크로 보는 랩 상세(<c>GET /public/laps/{lapId}</c>, 로그인 없음). <see cref="LapDetailResponse"/>와 같은 이름의 필드를 쓰는 읽기 전용 부분집합이다
/// — 세션 연결은 로그인한 주인의 것이라 뺀다. <see cref="DisplayName"/> = 랩 주인 이름, 랭킹과 같은 규칙(이름 비공개·지운 사용자 = 익명 드라이버, D-39).
/// <see cref="Comparison"/> = 공유 링크의 <c>compareLapId</c>로 고른 비교 랩(종류 <c>lap</c>). 같은 트랙·게임의 지우지 않은 다른 랩일 때만 있고, 아니면 null.
/// 비교 랩 주인이 이 랩 주인과 같으면 <c>isMine</c> = true(이름 없음), 다르면 같은 이름 규칙의 이름을 싣는다.
/// 이메일·사용자 ID·장치 정보는 담지 않는다.
/// </summary>
public sealed record PublicLapDetailResponse(
    LapDto Lap,
    Guid TrackId,
    string? CountryCode,
    string DisplayName,
    LapCarSnapshotDto? Car,
    LapConditionsDto? Conditions,
    LapAssistsDto? Assists,
    LapComparisonDto? Comparison = null);

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

/// <summary>
/// 드라이버 어시스트(docs/15 §10, D-51). 값 = 이름 문자열, 모르면 null.
/// TC <c>Off·Medium·Full</c> · ABS/조향 <c>Off·On</c> · 제동 <c>Off·Low·Medium·High</c> · 기어 <c>Manual·ManualSuggested·Automatic</c> · 라인 <c>Off·CornersOnly·Full</c>.
/// </summary>
public sealed record LapAssistsDto(
    string? TractionControl,
    string? AntiLockBrakes,
    string? SteeringAssist,
    string? BrakingAssist,
    string? Gearbox,
    string? RacingLine);

/// <summary>
/// 비교 대상 랩(docs/15 §10, D-51). <see cref="Kind"/> = <c>best·leaderboard·lap</c>(<see cref="LapComparisonKinds"/>).
/// <see cref="IsMine"/>면 <see cref="DisplayName"/>은 null, 남의 랩이면 랭킹과 같은 이름 규칙(이름 비공개 = 익명 드라이버, D-39).
/// <see cref="AppliedFilters"/> = 실제로 적용한 필터(<see cref="LapComparisonFilters"/>) — 이 랩의 값을 모르면 그 필터는 빠진다.
/// </summary>
public sealed record LapComparisonDto(
    string Kind,
    Guid LapId,
    int LapTimeMs,
    IReadOnlyList<LapSectorDto> Sectors,
    DateTime SetAt,
    bool HasTrace,
    bool IsMine,
    string? DisplayName,
    TeamRefDto? Team,
    string SessionType,
    IReadOnlyList<string> AppliedFilters);

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
