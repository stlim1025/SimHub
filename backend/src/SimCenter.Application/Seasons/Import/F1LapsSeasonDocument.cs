using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// F1Laps 시즌 마크다운을 해석한 결과(docs/15 §12, D-55). 값 그대로이며 트랙·팀 매핑은 하지 않는다.
/// </summary>
/// <param name="Title">"# Season: …"의 시즌 이름(예: "Driver Career").</param>
/// <param name="GameCode">헤더 <c>Game</c>을 게임 코드로 바꾼 값(예: "F1 2025" → <c>F1_25</c>).</param>
/// <param name="GameMode">헤더 <c>Mode</c>.</param>
/// <param name="TeamName">헤더 <c>Team</c>(없으면 null).</param>
/// <param name="PlayerName">헤더 <c>Name</c>.</param>
/// <param name="Rounds">Grand Prix Results의 모든 행(값이 없는 라운드 포함, <c>#</c> 순서).</param>
/// <param name="Drivers">Driver Standings의 모든 행.</param>
public sealed record F1LapsSeasonDocument(
    string Title,
    string GameCode,
    GameMode GameMode,
    string? TeamName,
    string PlayerName,
    IReadOnlyList<F1LapsRound> Rounds,
    IReadOnlyList<F1LapsDriverPoints> Drivers);

/// <summary>
/// Grand Prix Results 한 행. <c>-</c>는 null. <see cref="Number"/> = 라운드 = F1 25 캘린더 순서(<c>Track.DisplayOrder</c>).
/// </summary>
public sealed record F1LapsRound(
    int LineNumber,
    int Number,
    string TrackName,
    int? QualifyingPosition,
    int? RacePosition,
    int? Points,
    int? BestLapTimeMs,
    string? Conditions,
    int? RaceAiDifficulty,
    int? QualifyingAiDifficulty)
{
    /// <summary>값이 하나라도 있는 라운드만 가져온다(D-55).</summary>
    public bool HasAnyValue =>
        QualifyingPosition is not null || RacePosition is not null || Points is not null || BestLapTimeMs is not null
        || Conditions is not null || RaceAiDifficulty is not null || QualifyingAiDifficulty is not null;

    /// <summary>레이스 세션을 만들 결과가 있는가(레이스 순위·포인트·베스트 랩 중 하나 — 난이도·날씨만으로는 만들지 않는다).</summary>
    public bool HasRace => RacePosition is not null || Points is not null || BestLapTimeMs is not null;

    /// <summary>예선 세션을 만들 결과가 있는가(예선 순위 — 난이도만으로는 만들지 않는다).</summary>
    public bool HasQualifying => QualifyingPosition is not null;
}

/// <summary>Driver Standings 한 행. <see cref="IsPlayer"/> = "You *" 행.</summary>
public sealed record F1LapsDriverPoints(int Position, string Name, int Points, bool IsPlayer);
