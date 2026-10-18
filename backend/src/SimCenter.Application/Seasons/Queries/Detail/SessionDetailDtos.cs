using System.Text.Json;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>내 팀(결과의 플레이어 행 팀, <c>TeamCatalog</c>로 푼 이름·색 — docs/15 §11.4 D-53).</summary>
public sealed record MyTeamDto(string Name, string Color);

/// <summary>같은 주말 예선 세션의 내 순위(Details 카드의 Q1·Q2·Q3, docs/15 §11.3). <c>SessionKind</c> 순서.</summary>
public sealed record QualifyingPositionDto(Guid SessionId, string SessionKind, int Position);

/// <summary>이 세션에 연결된 내 최고 랩(유효 랩 우선, 없으면 가장 빠른 랩).</summary>
public sealed record MyBestLapDto(Guid LapId, int LapTimeMs);

/// <summary>
/// Laps 카드 한 줄(docs/15 §11.3·§11.4). <see cref="Sectors"/>·<see cref="BestSectors"/>는 항상 3칸이고 모르는 섹터는 null·false.
/// <see cref="PositionChange"/> = 이전 랩 순위 − 이 랩 순위(1랩은 그리드 대비, 모르면 null). <see cref="LapId"/>는 같은 랩 번호의 저장된 내 랩.
/// </summary>
public sealed record SessionLapDto(
    int LapNumber,
    int? Position,
    int? PositionChange,
    string? VisualCompound,
    bool InPit,
    int LapTimeMs,
    int? GapToBestMs,
    IReadOnlyList<int?> Sectors,
    bool IsValid,
    bool IsBestLap,
    IReadOnlyList<bool> BestSectors,
    Guid? LapId);

/// <summary>Engine Wear 카드(%) — 세션 마지막 내 랩의 <c>details.damage</c> + 스냅샷 기어박스·엔진 손상. 모르는 부품은 null.</summary>
public sealed record EngineWearDto(
    int? Ice,
    int? TurboCharger,
    int? MguH,
    int? MguK,
    int? EnergyStore,
    int? ControlElectronics,
    int? Gearbox,
    int? EngineDamage);

/// <summary>Tyre Stints 카드의 스틴트 한 개. <see cref="EndLap"/>은 기록이 있는 마지막 랩으로 자른 값이다.</summary>
public sealed record TyreStintSeriesDto(string VisualCompound, int StartLap, int EndLap, IReadOnlyList<TyreStintLapDto> Laps);

/// <summary>스틴트 안 랩 한 개. <see cref="TyreLifeRemaining"/> = 100 − 네 바퀴 평균 마모(%), 모르면 null.</summary>
public sealed record TyreStintLapDto(int LapNumber, int LapInStint, int? LapTimeMs, double? TyreLifeRemaining);

/// <summary>
/// Penalties 카드 한 줄(PENA 이벤트). 이름은 <c>PenaltyCatalog</c>, 드라이버는 순위표의 같은 carIndex 행에서 푼다.
/// <see cref="TimeS"/>는 0·255(해당 없음)면 null. 원시 번호(<see cref="PenaltyType"/>·<see cref="InfringementType"/>)도 함께 준다(추가 필드).
/// </summary>
public sealed record SessionPenaltyDto(
    int Lap,
    int CarIndex,
    string DriverName,
    bool IsPlayer,
    string TeamColor,
    string Infringement,
    string Penalty,
    int? TimeS,
    int? InfringementType,
    int? PenaltyType);

/// <summary>세션 상세의 F1Laps 카드 재료 묶음(D-53). 데이터가 없으면 null·빈 목록 — 오류로 만들지 않는다.</summary>
public sealed record SessionDetailExtras(
    IReadOnlyList<QualifyingPositionDto> QualifyingPositions,
    MyBestLapDto? MyBestLap,
    JsonElement? Setup,
    IReadOnlyList<SessionLapDto> Laps,
    EngineWearDto? EngineWear,
    IReadOnlyList<TyreStintSeriesDto> TyreStints,
    IReadOnlyList<SessionPenaltyDto> Penalties,
    string? Weather);
