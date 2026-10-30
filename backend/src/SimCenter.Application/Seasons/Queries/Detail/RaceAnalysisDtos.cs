namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 레이스 심층 분석(<see cref="RaceAnalysisBuilder"/>): 내 랩 트레이스로 나눈 랩 구간, 스틴트마다 구간별 타이어 부담·입력·배터리,
/// 마찰 일 대비 실제 마모, 다른 차들의 구간별 배터리, 타이어로 본 전략, 랩마다 페이스 기준들. 모르는 부분은 null·빈 목록.
/// 구간을 나눈 기준 랩 = 트레이스가 있는 깨끗한 랩 중 가장 빠른 랩(없으면 null — 구간·스틴트 주행 분석이 빈다).
/// </summary>
public sealed record RaceAnalysisDto(
    int TrackLengthM,
    int? ReferenceLap,
    IReadOnlyList<RaceSegmentDto> Segments,
    IReadOnlyList<RaceStintDrivingDto> Stints,
    double? WearPctPerMj,
    IReadOnlyList<FieldSegmentErsDto> FieldErs,
    RaceStrategyAnalysisDto? Strategy,
    IReadOnlyList<RaceLapPaceDto> LapPace);

/// <summary>
/// 랩 구간 하나: 번호(랩 안 순서), 종류(<c>Corner</c>·<c>Straight</c>), 랩 거리 시작·끝(m — 결승선을 넘는 직선은 시작 &gt; 끝),
/// 기준 랩의 최저 속도 지점(m)과 그 속도(km/h).
/// </summary>
public sealed record RaceSegmentDto(int Index, string Kind, int StartM, int EndM, int ApexM, int MinSpeedKph);

/// <summary>
/// 내 스틴트 하나의 주행 분석: 컴파운드·랩 범위, 분석한 깨끗한 랩, 바퀴별(앞왼·앞오·뒤왼·뒤오) 랩당 마찰 일(kJ)·랩 최고 표면 온도 평균·
/// 속 온도 평균(°C)·랩당 마모(%p), 구간별 랩 평균.
/// </summary>
public sealed record RaceStintDrivingDto(
    string Compound,
    int StartLap,
    int EndLap,
    IReadOnlyList<int> Laps,
    IReadOnlyList<double>? WheelWorkKj,
    IReadOnlyList<double>? PeakSurfaceTempC,
    IReadOnlyList<double>? InnerTempC,
    IReadOnlyList<double>? WheelWearPerLapPct,
    IReadOnlyList<RaceSegmentDrivingDto> Segments);

/// <summary>
/// 스틴트 안 한 구간의 랩 평균: 구간 시간(ms)과 랩마다 늘어난 정도(ms/랩, 최소제곱), 바퀴별 마찰 일(kJ), 평균 조향(%, 0~100),
/// 언더스티어(앞 − 뒤 평균 슬립각, °, +면 앞이 더 미끄러진다 — 코너링 중 표본만), 앞 바퀴 락업·뒤 휠스핀·브레이크 밟은 채 조향·
/// 풀 스로틀로 조향·브레이크(10% 이상) 밟은·연석 거리(m), 바퀴별 최고 표면 온도(°C), 최저·끝 속도(km/h),
/// 배터리 채움·씀(kJ)·Overtake 모드 거리·배포 없음 모드 거리(m)·구간 끝 잔량(kJ)·거의 바닥이던 거리(m)와 그런 랩 수,
/// 스로틀을 완전히 뗀(5% 미만) 거리(m)·Overtake로 280km/h 이상 달린 거리(m). 채널이 없으면 null.
/// </summary>
public sealed record RaceSegmentDrivingDto(
    int Index,
    int TimeMs,
    int? TimeTrendMsPerLap,
    IReadOnlyList<double>? WheelWorkKj,
    double SteerPct,
    double? UndersteerDeg,
    double? LockupM,
    double? WheelspinM,
    double TrailBrakeM,
    double ThrottleSteerM,
    double BrakeM,
    double? KerbM,
    IReadOnlyList<double>? PeakSurfaceTempC,
    int MinSpeedKph,
    int EndSpeedKph,
    double? HarvestKj,
    double? DeployKj,
    double? OvertakeM,
    double? NoDeployM,
    double? StoreEndKj,
    double? EmptyM,
    int? EmptyLaps = null,
    double LiftM = 0,
    double? FastOvertakeM = null);

/// <summary>
/// 다른 차들(모든 차 표본)이 그 구간에서 랩마다 배터리를 채운·쓴 양의 중앙값(kJ)과 본 차 수,
/// 스로틀을 완전히 뗀(5% 미만) 거리(m)·구간 통과 시간(ms)의 중앙값(표본에 스로틀이 없으면 거리는 null).
/// </summary>
public sealed record FieldSegmentErsDto(int Index, double HarvestKj, double DeployKj, int Cars, double? LiftM = null, int? TimeMs = null);

/// <summary>
/// 타이어로 본 전략: 레이스 랩 수, 출발 때 게임 피트 창(이상·최대 랩), 내 스톱 손실 중앙값(ms), 스톱마다 타이어 사정,
/// 컴파운드 모델(게임 타이어 델타·내 마모), 실제 전략과 스톱 수마다 가장 빠른 대안(추정).
/// </summary>
public sealed record RaceStrategyAnalysisDto(
    int TotalLaps,
    int? IdealLap,
    int? LatestLap,
    int? PitLossMs,
    IReadOnlyList<RaceStopContextDto> Stops,
    IReadOnlyList<RaceCompoundModelDto> Compounds,
    IReadOnlyList<RaceStrategyOptionDto> Options);

/// <summary>
/// 스톱 하나의 타이어 사정: 인 랩, 그 랩의 게임 피트 창(이상·최대 랩), 끼운 세트 마모(%)·게임이 본 남은 수명(랩),
/// 바꾸기 전·후 컴파운드, 다음 세트로 바꾸면 랩당 빨라지는 정도(ms, +면 빨라진다 — 게임 타이어 델타).
/// </summary>
public sealed record RaceStopContextDto(
    int Lap,
    int? IdealLap,
    int? LatestLap,
    double? WearPct,
    int? LifeLapsLeft,
    string FromCompound,
    string ToCompound,
    int? NewSetGainMs);

/// <summary>
/// 컴파운드 모델: 출발 때 끼운 세트 대비 새 세트 랩타임 차(ms, −면 빠르다 — 게임 타이어 델타), 랩당 느려지는 정도(ms/랩 — 그 컴파운드로 달린
/// 스틴트의 게임 타이어 델타 변화, 안 탔으면 null), 게임이 본 쓸 수 있는 랩 수, 출발 때 쓸 수 있던 세트 수.
/// </summary>
public sealed record RaceCompoundModelDto(string Compound, int? OffsetMs, int? DegMsPerLap, int? UsableLaps, int Sets);

/// <summary>전략 하나: 스틴트(컴파운드·랩 수), 실제 전략 대비 추정 시간(ms, −면 빠르다), 실제 전략인지.</summary>
public sealed record RaceStrategyOptionDto(IReadOnlyList<RaceStrategyStintDto> Stints, int DeltaMs, bool IsActual);

/// <summary>전략 안의 스틴트 하나.</summary>
public sealed record RaceStrategyStintDto(string Compound, int Laps);

/// <summary>
/// 내 랩 하나의 페이스 기준들: 랩타임, 같은 랩 다른 차들 깨끗한 랩 중앙값, 같은 컴파운드·타이어 나이(±1랩) 다른 차들 깨끗한 랩 중앙값,
/// 내 컴파운드·타이어 나이(스틴트 첫 랩 = 0), 깨끗한 랩인지(1랩·피트 인아웃·세이프티카 랩 제외).
/// </summary>
public sealed record RaceLapPaceDto(
    int Lap,
    int LapTimeMs,
    int? FieldSameLapMs,
    int? FieldSameTyreMs,
    string? Compound,
    int? TyreAge,
    bool IsClean);
