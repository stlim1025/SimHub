namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// 시즌 가져오기 요청 본문(docs/15 §12, D-55): 붙여넣은 마크다운 원문. 문서 여러 개(F1Laps 시즌 요약 · 인게임 순위표 · F1Laps 세션들)를
/// <c># 제목</c>으로 이어 붙여도 된다.
/// </summary>
public sealed record SeasonImportRequest(string? Markdown);

/// <summary>
/// 가져오기 미리보기 = 저장하지 않고 만든 결과. <see cref="Drivers"/>·<see cref="Constructors"/>는 가져온 뒤 시즌 화면에 나올 Standings와 같다.
/// <see cref="AlreadyImported"/>면 가져오기가 409다(같은 링크 또는 같은 게임·모드·이름의 가져온 시즌이 이미 있음).
/// </summary>
public sealed record SeasonImportPreviewDto(
    string Title,
    string GameCode,
    string GameMode,
    string? TeamName,
    string PlayerName,
    IReadOnlyList<SeasonImportDocumentDto> Documents,
    IReadOnlyList<SeasonImportRoundDto> Rounds,
    IReadOnlyList<SeasonImportDriverDto> Drivers,
    IReadOnlyList<SeasonImportConstructorDto> Constructors,
    SeasonLinkCandidateDto? LinkCandidate,
    bool AlreadyImported);

/// <summary>
/// 찾은 문서 하나. <see cref="Kind"/> = <c>F1LapsSeason</c>·<c>InGameStandings</c>·<c>F1LapsSession</c>.
/// 숫자는 그 문서에서 찾은 라운드·세션·드라이버 수.
/// </summary>
public sealed record SeasonImportDocumentDto(string Kind, string Title, int Rounds, int Sessions, int Drivers);

/// <summary>만들 라운드 한 줄(캘린더 순서). <see cref="Sessions"/>는 주말 안 순서이고 옮길 기록 세션도 포함한다.</summary>
public sealed record SeasonImportRoundDto(
    int Round,
    string TrackName,
    IReadOnlyList<SeasonImportSessionDto> Sessions,
    int? MyPoints);

/// <summary><see cref="Source"/> = <c>Imported</c>(가져온 세션) 또는 <c>Recorded</c>(옮길 기록 세션).</summary>
public sealed record SeasonImportSessionDto(
    string SessionType,
    string SessionKind,
    string Source,
    int? MyPosition,
    int CarCount,
    int LapCount);

public sealed record SeasonImportDriverDto(int Position, string Name, string TeamName, string TeamColor, int Points, bool IsPlayer);

public sealed record SeasonImportConstructorDto(int Position, string TeamName, string TeamColor, int Points);

/// <summary>연결할 게임 시즌(링크 ID)과 이 시즌으로 옮길 내 기록 세션들(D-55).</summary>
public sealed record SeasonLinkCandidateDto(long SeasonLinkId, IReadOnlyList<SeasonLinkCandidateSessionDto> Sessions);

/// <summary><see cref="Kind"/> = 세션 상세 종류 이름(<c>Qualifying1</c> 등).</summary>
public sealed record SeasonLinkCandidateSessionDto(Guid SessionId, string Kind, string TrackName, DateTime ClassifiedAt);

/// <summary>가져오기 결과: 만든 시즌, 만든 세션 수, 옮긴 기록 세션 수.</summary>
public sealed record SeasonImportResultDto(Guid SeasonId, int ImportedSessionCount, int AttachedSessionCount);
