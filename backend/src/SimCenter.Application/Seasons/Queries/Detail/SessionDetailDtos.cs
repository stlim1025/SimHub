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

/// <summary>레이스 총평 재료(<see cref="RaceReviewBuilder"/>). 모르는 부분은 null·빈 목록.</summary>
public sealed record RaceReviewDto(
    RacePaceReviewDto? Pace,
    RaceStrategyReviewDto Strategy,
    IReadOnlyList<RaceStintReviewDto> Stints,
    RaceBatteryReviewDto? Battery);

/// <summary>
/// 페이스: 깨끗한 랩 중앙값(ms) — 내 값, 내 순위(1 = 가장 빠름)/순위를 낸 차 수, 다른 차들 중앙값의 중앙값,
/// 나를 뺀 가장 빠른 차, 결과 바로 앞·뒤 차(없으면 null), 섹터 1·2·3 중앙값(ms) — 내 값·다른 차들 값의 중앙값·결과 바로 앞 차 값(모르면 null).
/// </summary>
public sealed record RacePaceReviewDto(
    int MyMedianMs,
    int Rank,
    int RankedCars,
    int FieldMedianMs,
    string FastestName,
    int FastestMedianMs,
    string? AheadName,
    int? AheadMedianMs,
    string? BehindName,
    int? BehindMedianMs,
    IReadOnlyList<int>? MySectorMs = null,
    IReadOnlyList<int>? FieldSectorMs = null,
    IReadOnlyList<int>? AheadSectorMs = null);

/// <summary>
/// 전략: 그리드·결과 순위, 내 스톱 수와 스톱마다의 결과, 완주 차들이 가장 많이 한 스톱 수와 그 차 수,
/// 우승 차 스톱 수·컴파운드 순서, 다른 차들 스톱 손실 중앙값(ms), 내 랩 끝 순위(랩별, 기록된 랩만),
/// 다른 차들 인 랩·아웃 랩 손실 중앙값(ms), 스톱 수별 완주 순위, 나와 스톱 수가 다르면서 출발·결과 순서가 뒤바뀐 차들.
/// </summary>
public sealed record RaceStrategyReviewDto(
    int? GridPosition,
    int? FinishPosition,
    int Stops,
    IReadOnlyList<RacePitStopReviewDto> PitStops,
    int? CommonStops,
    int CommonStopsCars,
    int? WinnerStops,
    IReadOnlyList<string> WinnerCompounds,
    int? FieldPitLossMs,
    IReadOnlyList<RaceLapPositionDto> LapPositions,
    int? FieldInLapLossMs = null,
    int? FieldOutLapLossMs = null,
    IReadOnlyList<RaceStopGroupDto>? StopGroups = null,
    IReadOnlyList<RaceStrategyRivalDto>? Rivals = null);

/// <summary>스톱 수 하나로 완주한 차들의 결과 순위(오름차순, 나 포함).</summary>
public sealed record RaceStopGroupDto(int Stops, IReadOnlyList<int> Finishes);

/// <summary>나와 스톱 수가 다른 차 중 출발·결과 순서가 나와 뒤바뀐 차: 이름, 스톱 수, 출발·결과 순위.</summary>
public sealed record RaceStrategyRivalDto(string Name, int Stops, int GridPosition, int FinishPosition);

/// <summary>내 랩 끝 순위 하나.</summary>
public sealed record RaceLapPositionDto(int Lap, int Position);

/// <summary>
/// 피트 스톱 하나: 인 랩, 앞 랩 순위 → 아웃 랩 다음 랩 순위, 손실(ms), 바꾸기 전·후 컴파운드, 인 랩·아웃 랩 손실(각 랩 − 깨끗한 랩 중앙값, ms),
/// 비슷한 때(인 랩 앞뒤 몇 랩) 같은 스톱 수로 들어간 다른 차들(없으면 스톱 수와 상관없이 비슷한 때 들어간 차들)의 손실·인 랩·아웃 랩 손실 중앙값과 그 스톱 수.
/// </summary>
public sealed record RacePitStopReviewDto(
    int Lap,
    int? PositionBefore,
    int? PositionAfter,
    int? LossMs,
    string FromCompound,
    string ToCompound,
    int? InLapLossMs = null,
    int? OutLapLossMs = null,
    int? PeerLossMs = null,
    int PeerCount = 0,
    int? PeerInLapLossMs = null,
    int? PeerOutLapLossMs = null);

/// <summary>
/// 내 스틴트 하나: 컴파운드·랩 범위, 깨끗한 랩 중앙값(ms)과 같은 컴파운드 다른 차들 값, 랩타임 추세(ms/랩, +면 느려짐)와 다른 차들 값,
/// 랩당 타이어 마모(%p)·끝 잔여 수명(%), 바퀴별 랩당 마모(%p, 앞왼·앞오·뒤왼·뒤오), 마지막 깨끗한 랩들이 스틴트 중앙값보다 느린 정도(ms),
/// 같은 컴파운드로 다른 차들이 피트에 들어가기 전까지 탄 랩 수의 중앙값(마지막 스틴트 제외, 마모가 빠른지 견주는 기준).
/// </summary>
public sealed record RaceStintReviewDto(
    string Compound,
    int StartLap,
    int EndLap,
    int? MedianMs,
    int? FieldMedianMs,
    int? TrendMsPerLap,
    int? FieldTrendMsPerLap,
    double? WearPerLapPct,
    double? EndLifePct,
    IReadOnlyList<double>? WheelWearPerLapPct = null,
    int? EndLapsSlowerMs = null,
    int? FieldStintLaps = null);

/// <summary>배터리: 기록된 랩 수, 랩당 평균 배포·회수(J), 랩 끝 잔량 처음·끝·최저(J)와 그 랩, 거의 바닥·가득 찬 랩 수, 랩별 잔량·배포·회수.</summary>
public sealed record RaceBatteryReviewDto(
    int Laps,
    double? AverageDeployJ,
    double? AverageHarvestJ,
    double FirstStoreJ,
    double LastStoreJ,
    double MinStoreJ,
    int MinStoreLap,
    int LowLaps,
    int FullLaps,
    IReadOnlyList<RaceBatteryLapDto> PerLap);

/// <summary>배터리 한 랩: 랩 번호, 랩 끝 잔량(J), 그 랩의 배포·회수(J, 모르면 null).</summary>
public sealed record RaceBatteryLapDto(int Lap, double StoreJ, double? DeployedJ, double? HarvestedJ);

/// <summary>세션 상세의 F1Laps 카드 재료 묶음(D-53). 데이터가 없으면 null·빈 목록 — 오류로 만들지 않는다.</summary>
public sealed record SessionDetailExtras(
    IReadOnlyList<QualifyingPositionDto> QualifyingPositions,
    MyBestLapDto? MyBestLap,
    JsonElement? Setup,
    IReadOnlyList<SessionLapDto> Laps,
    EngineWearDto? EngineWear,
    IReadOnlyList<TyreStintSeriesDto> TyreStints,
    IReadOnlyList<SessionPenaltyDto> Penalties,
    string? Weather,
    RaceReviewDto? RaceReview = null);
