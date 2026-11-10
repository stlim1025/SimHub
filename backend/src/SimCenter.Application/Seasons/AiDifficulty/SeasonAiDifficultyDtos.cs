namespace SimCenter.Application.Seasons.AiDifficulty;

/// <summary>
/// 시즌 AI 난이도 가이드(시즌 상세 AI 탭). 같은 차를 탄 AI 팀메이트와의 차이로 지금 난이도가 맞는지 본다 — 차 성능 차이가 빠진다.
/// <see cref="CurrentAiDifficulty"/> = 가장 최근 레이스(없으면 예선)의 AI 난이도. 판정(<see cref="Qualifying"/>·<see cref="Race"/>)은
/// 그 난이도로 달린 세션만 쓴다. <see cref="TimeTrial"/> = 내 타임트라이얼 최고 랩과 같은 트랙 마른 노면 예선의 가장 빠른 AI 랩 비교.
/// </summary>
public sealed record SeasonAiDifficultyDto(
    int? CurrentAiDifficulty,
    AiVerdictDto Qualifying,
    AiVerdictDto Race,
    AiCarLevelDto Car,
    IReadOnlyList<AiWeekendDto> Weekends,
    IReadOnlyList<AiTimeTrialDto> TimeTrial);

/// <summary>
/// 판정 하나. <see cref="Verdict"/> = <c>Raise</c>(올려도 됨) · <c>Keep</c>(적정) · <c>Lower</c>(낮추기) · <c>NotEnoughData</c>.
/// <see cref="Steps"/> = 바꿀 폭 추정(<c>1-2</c> · <c>3+</c>, 적정·데이터 부족이면 null).
/// <see cref="MedianGapPercent"/>·<see cref="MedianGapMs"/> = 팀메이트 대비 중앙값(음수 = 내가 빠름). 레이스는 랩당 평균 차이.
/// <see cref="Samples"/> = 판정에 쓴 세션 수, <see cref="AheadOfTeammate"/> = 그중 팀메이트를 앞선 수.
/// </summary>
public sealed record AiVerdictDto(
    string Verdict,
    string? Steps,
    double? MedianGapPercent,
    int? MedianGapMs,
    int Samples,
    int AheadOfTeammate);

/// <summary>차 성능 위치(시즌 전체 평균 순위). 팀메이트 값이 이 차의 수준이다. 모르면 null.</summary>
public sealed record AiCarLevelDto(
    double? TeammateQualiPosition,
    double? TeammateRacePosition,
    double? MyQualiPosition,
    double? MyRacePosition);

/// <summary>
/// 주말 한 줄. 예선 = 본 예선(없으면 스프린트 슛아웃)의 마지막 단계 순위, 차이 = 둘 다 기록한 마지막 단계의 최고 랩 차이(음수 = 내가 빠름).
/// <see cref="Weather"/> = 그 예선에서 내 랩들의 가장 나쁜 날씨(모르면 null).
/// </summary>
public sealed record AiWeekendDto(
    Guid WeekendId,
    int Round,
    string TrackName,
    string? CountryCode,
    int? AiDifficulty,
    string? Weather,
    string? TeammateName,
    int? MyQualiPosition,
    int? TeammateQualiPosition,
    int? QualiGapMs,
    double? QualiGapPercent,
    IReadOnlyList<AiRaceDto> Races);

/// <summary>
/// 레이스 한 판. 페이스 차이 = (내 총 레이스 시간 − 팀메이트 총 레이스 시간) ÷ 랩 수 — 둘 다 완주하고 랩 수가 같을 때만(음수 = 내가 빠름).
/// <see cref="IsSprint"/> = 스프린트 주말의 첫 레이스.
/// </summary>
public sealed record AiRaceDto(
    Guid SessionId,
    string SessionKind,
    bool IsSprint,
    int? MyGrid,
    int? MyPosition,
    int? TeammatePosition,
    int? PaceGapPerLapMs,
    double? PaceGapPercent,
    string? MyResultStatus);

/// <summary>타임트라이얼 비교 한 줄: 내 TT 최고 랩 vs 그 주말 마른 노면 예선의 가장 빠른 AI 랩(그 주말 AI 난이도). 차이 % 음수 = TT가 빠름.</summary>
public sealed record AiTimeTrialDto(
    Guid WeekendId,
    string TrackName,
    string? CountryCode,
    int TimeTrialBestMs,
    int AiFastestQualiMs,
    int AiDifficulty,
    double GapPercent);
