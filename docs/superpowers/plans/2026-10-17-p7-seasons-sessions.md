# P7 시즌·세션 결과 수집 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agent가 세션 끝의 최종 순위표를 참가자 정보와 합쳐 `SessionClassified` 1건으로 보내고, 백엔드가 게임 링크 식별자로 시즌 → 그랑프리 주말 → 세션을 묶어 저장하며, 웹이 Seasons(Season · Results · Standings)와 Sessions·세션 결과 화면을 보여 준다.

**Architecture:** Agent.Core에 게임 중립 프레임 2종(`ParticipantsFrame`·`ClassificationFrame`)과 상태 저장 분석기 `SessionResultTracker`를 추가하고, 파이프라인은 `ITelemetryAnalyzer` 목록을 분석기별 예외 격리로 돌린다. 백엔드는 `TelemetryIngestService`의 공통 단계(멱등·장치·LastSeen) 뒤에 유형별 분기를 두고, `SessionClassificationIngestor`가 변경만 추적해 커밋은 한 번이다. 조회는 시즌의 결과 행을 한 번 읽어 순수 계산기(세션 선별·Standings·라운드)로 만든다. Flutter는 `features/sessions`·`features/seasons`를 기존 Laps 구조대로 추가하고 페이지 바를 공용화한다.

**Tech Stack:** .NET 10 · ASP.NET Core 10 · EF Core 10 + Npgsql · SignalR · xUnit / .NET 10 Agent · F1Game.UDP 26.0.0 / Flutter 3.41 · Riverpod 2 · GoRouter 14 · Dio · Material3

**Spec:** [docs/12-seasons-sessions.md](../../12-seasons-sessions.md)

## Global Constraints

- 헌장: raw 패킷 전송 금지 — 서버로는 도메인 이벤트만. 시간은 `IClock`, Id는 `IIdGenerator`. Magic Number 금지(아래 값은 이름 붙은 상수).
- **실패 원칙(스펙 §0):** 같은 입력에 항상 실패하는 허브 예외를 만들지 않는다. 영구 무효는 Reject, 모르는 enum 문자열은 0번 대체값, 컬렉션 `Remove`·`Clear` 금지(지우기는 `IsDeleted`), 모든 unique index에 `.HasFilter("is_deleted = false")`.
- 이벤트 유형 문자열 `"SessionClassified"`. 페이로드 필드는 스펙 §5.5 그대로(camelCase, enum은 문자열). `LapFinished`에 선택 필드 `gameMode`·`seasonLinkId`·`weekendLinkId`·`sessionLinkId` 추가(스펙 §4.6).
- enum(백엔드 Domain과 Agent.Core가 **같은 이름·순서**): `GameMode { Other, DriverCareer, MyTeamCareer, OnlineCareer, ChallengeCareer, GrandPrix, TimeTrial, Online, Story }`, `SessionKind { Unknown, Practice1, Practice2, Practice3, ShortPractice, Qualifying1, Qualifying2, Qualifying3, ShortQualifying, OneShotQualifying, SprintShootout1, SprintShootout2, SprintShootout3, ShortSprintShootout, OneShotSprintShootout, Race, Race2, Race3, TimeTrial }`, `ResultStatus { Unknown, Active, Finished, DidNotFinish, Disqualified, NotClassified, Retired }`, `TyreCompound { Unknown, Soft, Medium, Hard, Intermediate, Wet }`.
- 시즌 대상: `GameMode ∈ {DriverCareer, MyTeamCareer, OnlineCareer, ChallengeCareer, GrandPrix}` **그리고** `seasonLinkId != 0` **그리고** `weekendLinkId != 0`.
- 세션 키: 시즌 대상이고 `sessionLinkId != 0`이면 `$"link:{seasonLinkId}:{weekendLinkId}:{sessionLinkId}"`, 그 밖에는 `$"uid:{sessionRef}"`.
- 드라이버 키: `isPlayer` → `"player"`; `gameDriverId` 있음 → `$"driver:{id}"`; 이름 있음 → `$"name:{NAME}#{raceNumber}"`(NAME = Trim + ToUpperInvariant, raceNumber null이면 빈 문자열); 그 외 `$"car:{sessionRef}:{carIndex}"`. 표시 대체 이름 `$"Car {carIndex + 1}"`.
- 검증 상수: `MaxClassificationEntries = 32`, `MaxTyreStints = 8`, `MaxDriverNameLength = 64`, `MaxSessionRefLength = 32`, `MaxActualCompoundLength = 10`. `MaxClockSkew = 5분`. 필드별 규칙은 스펙 §6.2-2 전부(DB 열 제약에 걸릴 값은 모두 검증에서 거른다).
- **EF 키:** 새 엔티티 5종은 `builder.Property(x => x.Id).ValueGeneratedNever()` — 추적 중인 세션에 Id를 채운 새 결과·스틴트를 붙일 때 INSERT가 되도록(스펙 §4.5).
- Reject 문구: `"SessionClassified payload 파싱 실패"`, `"SessionClassified payload가 비어 있습니다."`, `"SessionClassified 검증 실패: {상세}"`, 트랙 없음은 랩과 같은 `$"트랙 매핑 없음(gameCode={gameCode}, trackId={trackId})"`.
- 크기: 백엔드 `TelemetryHub.MaxMessageBytes = 64 * 1024`(`AddHubOptions<TelemetryHub>`로 명시), Agent `OutboxTelemetrySink.MaxEnvelopeBytes = 48 * 1024`.
- API: `GET /api/v1/me/seasons`(page 1, pageSize 기본 20·최대 20), `GET /api/v1/me/seasons/{seasonId:guid}`, `GET /api/v1/me/sessions`(sessionType 문자열 `Practice|Qualifying|Race` 대소문자 무시, page 1, pageSize 기본 20·최대 100), `GET /api/v1/me/sessions/{sessionId:guid}`. 남의 것·없는 것 = 404(`NotFoundException`). 잘못된 `sessionType` = `ValidationException("sessionType", "sessionType는 Practice/Qualifying/Race 중 하나여야 합니다.")`. 페이지 보정은 `RankingService.GetMyLapsAsync`와 같은 규칙.
- 정렬: 시즌 목록 `LastSessionAt` DESC → Id DESC; 세션 목록 `ClassifiedAt` DESC → Id DESC; 세션 결과 `Position` ASC → `CarIndex` ASC; 라운드 `FirstSessionAt` ASC → Id ASC; 라운드 안 세션 `ClassifiedAt` ASC.
- Standings(스펙 D-31): 같은 `(WeekendId, SessionKind≠Unknown)`은 최신 `ClassifiedAt` 1건만. 본 레이스 = 주말의 `SessionType.Race` 중 최신. 점수 = 계산 대상 세션 전부의 합. 우승·포디움·카운트백 = 본 레이스만. 드라이버 동점: 점수 DESC → 본 레이스 1위 수, 2위 수 … DESC → 이름 Ordinal ASC. Constructors: 점수 DESC → 우승 DESC → 팀 이름 Ordinal ASC.
- DTO null 규칙: 0인 `bestLapTimeMs`·`totalRaceTimeMs`·`myBestLapTimeMs`는 null. 내 결과 없음 → `my*` null.
- Flutter: 색은 `AppColors` 토큰만(팀 색은 API hex를 `parseHexColor`로). `kSessionTableCompactWidth = 600`(콘텐츠 폭), Sessions 페이지 크기 15, Seasons 20. 탭·필터 변경은 `Router.neglect(context, () => context.go(...))`. 페이지 번호는 화면 상태.
- 테스트 관례: xUnit + `Assert`, 테스트 파일마다 private nested Fake. Flutter는 `flutter_test`. TDD(실패 확인 → 구현 → 통과).
- 커밋: 한국어 conventional commit + 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **EF 모델 규칙(P6 교훈):** EF Core 9+는 모델과 마이그레이션이 어긋나면 `MigrateAsync`에서 예외를 던진다. 매핑된 엔티티(`Lap` 포함)를 바꾸거나 DbSet을 추가하는 일은 **마이그레이션과 같은 태스크(Task 3)** 에서만 한다. Task 1·2는 EF 모델을 건드리지 않는다.
- **실행 환경(이 PC):** 모든 `dotnet`·`flutter` 명령 앞에 `$env:DOTNET_ROOT='C:\Program Files\dotnet'; $env:TEMP='C:\Temp'; $env:TMP='C:\Temp';`. 빌드 전에 실행 중인 backend·agent·app 터미널 탭을 멈춘다. 통합 테스트는 로컬 PostgreSQL과 user-secrets(설정 완료)를 쓴다.

## Review Focus

1. **처음 쓰는 사용자(시즌·세션 0개)** — 두 목록 API가 빈 페이지를 돌려주고, 두 화면이 각자의 빈 상태 안내를 보여야 한다. → Task 5 `GetSeasons_NoData_ReturnsEmptyPage`, Task 8 `SessionsPage_Empty_ShowsGuide`, Task 9 `SeasonsPage_Empty_ShowsGuide`.
2. **스프린트 주말(레이스 세션 2개)** — 결과표 칸 순위는 마지막 레이스, 점수는 두 레이스 합, 스프린트 우승은 wins에 들어가지 않아야 한다. → Task 4 `Cells_SprintWeekend_UseMainRacePosition_AndSumWeekendPoints`, `Calculate_SprintWin_IsNotAWin`.
3. **같은 세션이 링크 ID만 바뀐 채 두 번 저장됨** — Standings 점수가 두 배가 되면 안 된다. → Task 4 `Select_DuplicateKindInWeekend_KeepsLatest`, `Calculate_DuplicateSession_NotDoubleCounted`.
4. **같은 세션이 차 수가 줄어 다시 분류됨** — 빠진 차의 옛 행이 결과·Standings에 남으면 안 되고, 허브가 예외 없이 Ack해야 한다. → Task 1 `ReplaceResults_MergesByCarIndex`, Task 3 `Reclassified_SameKey_FewerCars_MergesWithoutError`.
5. **Agent 시계가 크게 앞섬** — 이후 같은 세션의 재분류가 막히면 안 된다. → Task 2 `Apply_FutureOccurredAt_IsClampedToServerSkew`.

---

## File Structure

```
backend/src/SimCenter.Domain/
  Enums/                    GameMode, SessionKind, ResultStatus, TyreCompound (신규)
  Entities/                 Season, RaceWeekend, GameSession, SessionResult, SessionResultTyreStint (신규) · Lap (+SessionKey, Task 3)
  Seasons/                  SeasonPolicy, SessionKeys, DriverKeys (신규, 순수)
backend/src/SimCenter.Application/
  Common/Interfaces/        ISeasonRepository, IGameSessionRepository (신규)
  Common/                   LenientEnum (신규: 모르는 문자열 → 0번 값)
  Seasons/Ingest/           SessionClassifiedContracts, SessionClassificationValidator, ClassificationOutcome,
                            ISessionClassificationIngestor, SessionClassificationIngestor (신규)
  Seasons/Queries/          SeasonReadRows, SeasonSessionSelector, RoundNumbering, StandingsCalculator, TeamCatalog,
                            SeasonDtos, SessionDtos, ISeasonQueryService, SeasonQueryService, ISessionQueryService, SessionQueryService (신규)
  Telemetry/                TelemetryIngestService (유형 분기·SessionKey, Task 3), TelemetryContracts (LapFinished 선택 필드, Task 3)
backend/src/SimCenter.Infrastructure/Persistence/
  Configurations/           Season·RaceWeekend·GameSession·SessionResult·SessionResultTyreStintConfiguration (신규) · LapConfiguration (수정)
  Repositories/             SeasonRepository, GameSessionRepository (신규)
  Migrations/               AddSeasonsAndSessions (신규)
backend/src/SimCenter.Api/  Controllers/MySeasonsController, MySessionsController (신규) · Hubs/TelemetryHub (MaxMessageBytes) · Program.cs (AddHubOptions)
agent/src/SimCenter.Agent.Core/
  Telemetry/                GameMode, SessionKind, ResultStatus, TyreCompound, TyreStint (신규)
  Telemetry/Frames/         SessionFrame (필드 추가) · ParticipantsFrame, ClassificationFrame (신규)
  Telemetry/Events/         TelemetryEvents (+SessionClassified, ClassifiedResult, LapFinished 필드), TelemetryEventType (+SessionClassified)
  Analysis/                 ITelemetryAnalyzer, SessionResultTracker (신규) · LapAnalyzer (인터페이스 + 맥락 전달)
agent/src/SimCenter.Agent.Infrastructure/
  Mapping/                  F1PacketMapper (수정) · F1EnumMaps (신규)
  Pipeline/TelemetryPipeline · Sinks/OutboxTelemetrySink (크기 검사) · DependencyInjection
app/lib/core/               theme/app_colors.dart · router/app_router.dart · shell/nav_items.dart · widgets/pagination_bar.dart (신규, Laps에서 추출) · widgets/not_found_state.dart (신규) · util/hex_color.dart (신규)
app/lib/features/laps/presentation/track_laps_page.dart   (공용 PaginationBar 사용)
app/lib/features/sessions/  domain/session_models.dart, session_display.dart · data/sessions_repository.dart · application/sessions_providers.dart ·
                            presentation/sessions_page.dart, session_detail_page.dart, session_results_table.dart, tyre_stints_view.dart
app/lib/features/seasons/   domain/season_models.dart · data/seasons_repository.dart · application/seasons_providers.dart ·
                            presentation/seasons_page.dart, season_detail_page.dart, season_rounds_tab.dart, season_results_tab.dart, season_standings_tab.dart
shared/                     schema/session_classified.json (신규) · schema/telemetry_envelope.json · schema/lap_finished.json · samples/telemetry_session_classified_envelope.json (신규) · openapi/openapi.yaml
docs/                       CLAUDE.md · 02 · 03 · 04 · 05 · 06 · 08 · 11 · 12 · PROGRESS.md · TESTING-local-e2e.md
```

**태스크 순서와 병렬성:** 백엔드 1 → 2 → 3 → 4 → 5, Agent 6 → 7, 앱 8 → 9, 마지막 10. Agent(6·7)는 Task 2의 계약(스키마)만 필요하고, 앱(8·9)은 스펙 §7.2의 DTO 모양만 필요하다(테스트는 Fake). 세 줄기는 서로 다른 파일만 만지므로 병렬로 진행할 수 있다.

---

### Task 1: 시즌·세션 도메인 (enum · 엔티티 · 순수 규칙)

**Files:**
- Create: `backend/src/SimCenter.Domain/Enums/GameMode.cs`, `SessionKind.cs`, `ResultStatus.cs`, `TyreCompound.cs`
- Create: `backend/src/SimCenter.Domain/Entities/Season.cs`, `RaceWeekend.cs`, `GameSession.cs`, `SessionResult.cs`, `SessionResultTyreStint.cs`
- Create: `backend/src/SimCenter.Domain/Seasons/SeasonPolicy.cs`, `SessionKeys.cs`, `DriverKeys.cs`
- Test: `backend/tests/SimCenter.Domain.Tests/Seasons/SeasonPolicyTests.cs`, `SessionKeysTests.cs`, `DriverKeysTests.cs`, `GameSessionReplaceResultsTests.cs`, `SeasonTouchTests.cs`; Modify: `backend/tests/SimCenter.Domain.Tests/EntityDefaultsTests.cs`

**Interfaces:**
- Consumes: `BaseEntity`, `SessionType`, `Track`.
- Produces:
  - enum 4종(Global Constraints의 이름·순서, 0번이 대체값).
  - `Season : BaseEntity { Guid UserId; string GameCode; long SeasonLinkId; GameMode GameMode; DateTime FirstSessionAt; DateTime LastSessionAt; ICollection<RaceWeekend> Weekends; void Touch(DateTime classifiedAt, DateTime now); }` — 범위를 넓힐 때만 `UpdatedAt = now`.
  - `RaceWeekend : BaseEntity { Guid SeasonId; Season? Season; long WeekendLinkId; Guid TrackId; Track? Track; DateTime FirstSessionAt; void Touch(DateTime classifiedAt, DateTime now); }`
  - `GameSession : BaseEntity { Guid UserId; Guid AgentDeviceId; Guid? SeasonId; Guid? RaceWeekendId; string GameCode; string SessionKey; long SeasonLinkId; long WeekendLinkId; long SessionLinkId; string SessionRef; Guid TrackId; Track? Track; SessionType SessionType; SessionKind SessionKind; GameMode GameMode; int TotalLaps; int AiDifficulty; bool IsNetworkGame; DateTime ClassifiedAt; ICollection<SessionResult> Results; void ReplaceResults(IReadOnlyList<SessionResult> incoming, DateTime now); }`
  - `SessionResult : BaseEntity { Guid GameSessionId; int CarIndex; int Position; int GridPosition; int NumLaps; int Points; int NumPitStops; int NumPenalties; ResultStatus ResultStatus; int BestLapTimeMs; int TotalRaceTimeMs; int PenaltiesTimeMs; string DriverKey; string? DriverName; int? GameDriverId; int? TeamId; int? RaceNumber; bool IsAiControlled; bool IsPlayer; ICollection<SessionResultTyreStint> TyreStints; void CopyValuesFrom(SessionResult source, DateTime now); void ReplaceTyreStints(IEnumerable<SessionResultTyreStint> stints, DateTime now); void SoftDelete(DateTime now); }`
  - `SessionResultTyreStint : BaseEntity { Guid SessionResultId; int StintNumber; int EndLap; TyreCompound VisualCompound; string? ActualCompound; }`
  - `static class SeasonPolicy { bool BelongsToSeason(GameMode mode, long seasonLinkId, long weekendLinkId); }`
  - `static class SessionKeys { string For(GameMode mode, long seasonLinkId, long weekendLinkId, long sessionLinkId, string sessionRef); string Uid(string sessionRef); }`
  - `static class DriverKeys { const string Player = "player"; string Build(bool isPlayer, int? gameDriverId, string? name, int? raceNumber, string sessionRef, int carIndex); }`

- [ ] **Step 1: 순수 규칙 테스트 작성**

```csharp
// SeasonPolicyTests
[Theory]
[InlineData(GameMode.DriverCareer, true)] [InlineData(GameMode.MyTeamCareer, true)] [InlineData(GameMode.OnlineCareer, true)]
[InlineData(GameMode.ChallengeCareer, true)] [InlineData(GameMode.GrandPrix, true)]
[InlineData(GameMode.TimeTrial, false)] [InlineData(GameMode.Online, false)] [InlineData(GameMode.Story, false)] [InlineData(GameMode.Other, false)]
public void BelongsToSeason_ByMode(GameMode mode, bool expected) => Assert.Equal(expected, SeasonPolicy.BelongsToSeason(mode, 11, 22));
[Theory] [InlineData(0, 22)] [InlineData(11, 0)]
public void BelongsToSeason_ZeroLink_IsFalse(long season, long weekend) => Assert.False(SeasonPolicy.BelongsToSeason(GameMode.DriverCareer, season, weekend));
// SessionKeysTests
[Fact] For_SeasonModeWithSessionLink_UsesLinkTriple   // For(DriverCareer, 11, 22, 33, "999") == "link:11:22:33"
[Fact] For_SeasonModeWithoutSessionLink_UsesUid       // For(DriverCareer, 11, 22, 0, "999") == "uid:999"
[Fact] For_NonSeasonMode_AlwaysUsesUid                // For(Online, 11, 22, 33, "999") == "uid:999"
[Fact] Uid_PrefixesSessionRef                         // Uid("999") == "uid:999"
// DriverKeysTests
[Fact] Build_Player_IgnoresOtherFields                // Build(true, 9, "X", 1, "S", 0) == "player"
[Fact] Build_GameDriverId_UsesDriverId                // Build(false, 9, "VERSTAPPEN", 1, "S", 4) == "driver:9"
[Fact] Build_NoDriverId_UsesNormalizedNameAndNumber   // Build(false, null, "  lim ", 26, "S", 4) == "name:LIM#26"; raceNumber null → "name:LIM#"
[Theory] [InlineData(null)] [InlineData("  ")]
Build_NoIdentity_UsesSessionScopedCarKey(string? name) // Build(false, null, name, 26, "S1", 4) == "car:S1:4"
```

- [ ] **Step 2: 엔티티 동작 테스트 작성** (`Now = 2026-10-17T12:00:00Z`)

```csharp
// GameSessionReplaceResultsTests
[Fact] ReplaceResults_MergesByCarIndex
    // 기존 활성: car 0(P1, 스틴트 2개), car 1(P2), car 2(P3) / 새로: car 0(P2, 스틴트 1개), car 1(P1), car 5(P3)
    // → car 0·1 행은 같은 Id로 값만 바뀜(UpdatedAt == Now), car 0의 옛 스틴트 2개 IsDeleted == true + 새 스틴트 1개 붙음,
    //   car 2 행과 그 스틴트 IsDeleted == true(UpdatedAt == Now), car 5는 새 행, Results 개수는 줄지 않음(Remove 없음),
    //   Results.Where(r => !r.IsDeleted).Select(r => r.CarIndex) == {0, 1, 5}
[Fact] ReplaceResults_IgnoresAlreadyDeletedRows      // soft-deleted car 3 행은 그대로(값·UpdatedAt 불변), 새 car 3은 새 행
// SeasonTouchTests
[Fact] Season_Touch_WidensRangeOnly                  // First 10:00·Last 11:00 → Touch(09:00) First 09:00, Touch(12:00) Last 12:00, Touch(10:30) UpdatedAt 불변
[Fact] Weekend_Touch_KeepsEarliest
```

- [ ] **Step 3: 실패 확인** — `dotnet test backend/tests/SimCenter.Domain.Tests --nologo` → 컴파일 실패(타입 없음).
- [ ] **Step 4: enum·엔티티·규칙 구현** — `CopyValuesFrom`은 Id·GameSessionId·CreatedAt·IsDeleted·TyreStints를 뺀 모든 값 필드를 복사하고 `UpdatedAt = now`. 문자열 필드는 기존 엔티티처럼 `required` 또는 `string.Empty`.
- [ ] **Step 5: 기본값 테스트 추가** — `EntityDefaultsTests`에 새 엔티티 5종: `IsDeleted == false`, `UpdatedAt == null`, 컬렉션이 빈 목록(null 아님).
- [ ] **Step 6: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → 전체 PASS(EF 모델 불변 — DbSet·Lap 변경 없음).
- [ ] **Step 7: 커밋** — `feat(domain): 시즌·주말·세션 결과 엔티티와 묶음 규칙 추가(P7)`

---

### Task 2: 계약 + `SessionClassified` 인입 유스케이스 (Application, Fake 저장소 — 아직 배선하지 않음)

> **배선은 Task 3:** ingestor를 DI·`TelemetryIngestService`에 연결하면 저장소 구현(Task 3)이 없어 Development 환경의 DI 검증이 실패하고 통합 테스트가 모두 깨진다.
> 이 태스크는 유스케이스 클래스와 단위 테스트까지만 만든다.

**Files:**
- Create: `shared/schema/session_classified.json`, `shared/samples/telemetry_session_classified_envelope.json`(22대, 2스틴트); Modify: `shared/schema/telemetry_envelope.json`(`type` enum), `shared/schema/lap_finished.json`(선택 필드 4개 — `required`에는 넣지 않는다)
- Create: `backend/src/SimCenter.Application/Common/Interfaces/ISeasonRepository.cs`, `IGameSessionRepository.cs`, `backend/src/SimCenter.Application/Common/LenientEnum.cs`
- Create: `backend/src/SimCenter.Application/Seasons/Ingest/SessionClassifiedContracts.cs`, `SessionClassificationValidator.cs`, `ClassificationOutcome.cs`, `ISessionClassificationIngestor.cs`, `SessionClassificationIngestor.cs`
- Test: `backend/tests/SimCenter.Application.Tests/Common/LenientEnumTests.cs`, `Seasons/SessionClassificationValidatorTests.cs`, `Seasons/SessionClassificationIngestorTests.cs`

**Interfaces:**
- Consumes: Task 1 전부, 기존 `TelemetryEnvelopeDto`, `IngestResult`, `ITrackRepository.GetByGameTrackIdAsync`, `IIdGenerator`, `IClock`, `AgentDevice`, `ProcessedEvent`.
- Produces:
  - `static class LenientEnum { TEnum Parse<TEnum>(string? value) where TEnum : struct, Enum; }` — 대소문자 무시 이름 일치(숫자 문자열은 거부)면 그 값, 아니면 `default(TEnum)`.
  - DTO(`SimCenter.Application.Seasons.Ingest`, enum 필드는 문자열):
    `SessionClassifiedPayloadDto(string SessionRef, int TrackId, string? SessionType, string? SessionKind, string? GameMode, long SeasonLinkId, long WeekendLinkId, long SessionLinkId, int TotalLaps, int AiDifficulty, bool IsNetworkGame, IReadOnlyList<ClassifiedResultDto>? Results)`,
    `ClassifiedResultDto(int CarIndex, bool IsPlayer, int Position, int GridPosition, int NumLaps, int Points, int NumPitStops, int NumPenalties, string? ResultStatus, int BestLapTimeMs, int TotalRaceTimeMs, int PenaltiesTimeMs, string? DriverName, int? GameDriverId, int? TeamId, int? RaceNumber, bool IsAiControlled, IReadOnlyList<TyreStintDto>? TyreStints)`,
    `TyreStintDto(int EndLap, string? VisualCompound, string? ActualCompound)`
  - `static class SessionClassificationValidator { const int MaxClassificationEntries = 32; const int MaxTyreStints = 8; const int MaxDriverNameLength = 64; const int MaxSessionRefLength = 32; const int MaxActualCompoundLength = 10; string? Validate(SessionClassifiedPayloadDto payload); }` — null = 통과, 아니면 상세 문구.
  - `abstract record ClassificationOutcome { sealed record Stored(string SessionKey, bool IsNew); sealed record Ignored(string Reason); sealed record Rejected(string Reason); }`
  - `ISeasonRepository { Task<Season?> GetByLinkAsync(Guid userId, string gameCode, long seasonLinkId, ct) /* tracked */; Task<RaceWeekend?> GetWeekendAsync(Guid seasonId, long weekendLinkId, ct) /* tracked */; Task AddAsync(Season season, ct); Task AddWeekendAsync(RaceWeekend weekend, ct); }`
  - `IGameSessionRepository { Task<GameSession?> GetByKeyWithResultsAsync(Guid userId, string gameCode, string sessionKey, ct) /* tracked, 활성 Results + 활성 TyreStints */; Task AddAsync(GameSession session, ct); }`
  - `ISessionClassificationIngestor { Task<ClassificationOutcome> ApplyAsync(TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, CancellationToken ct); }` — Stored면 변경을 **추적만**(저장 안 함). Ignored·Rejected면 아무것도 추적하지 않는다.
  - `SessionClassificationIngestor.MaxClockSkew = TimeSpan.FromMinutes(5)`.

- [ ] **Step 1: `LenientEnum`·검증기 테스트 작성** (`ValidPayload()` 헬퍼: 2대, car 0 플레이어)

```csharp
// LenientEnumTests
[Theory] [InlineData("Race", SessionKind.Race)] [InlineData("race", SessionKind.Race)] [InlineData("Sprint", SessionKind.Unknown)]
[InlineData(null, SessionKind.Unknown)] [InlineData("15", SessionKind.Unknown)]
Parse_MatchesNameIgnoringCase_ElseDefault(string? input, SessionKind expected)
// SessionClassificationValidatorTests
[Fact] Validate_ValidPayload_ReturnsNull
[Theory] [InlineData(0)] [InlineData(33)] Validate_ResultCountOutOfRange_Fails(int count)   // 상세에 "results" 포함
[Fact] Validate_NullResults_Fails
[Fact] Validate_DuplicateCarIndex_Fails                  // 상세 == "carIndex 중복(1)"
[Theory] [InlineData(-1)] [InlineData(32)] Validate_CarIndexOutOfRange_Fails(int carIndex)
[Theory] [InlineData(0)] [InlineData(33)] Validate_PositionOutOfRange_Fails(int position)
[Theory] [InlineData("bestLapTimeMs")] [InlineData("numLaps")] [InlineData("penaltiesTimeMs")] Validate_NegativeValue_Fails(string field)
[Theory] [InlineData("gridPosition")] [InlineData("points")] [InlineData("numPitStops")] [InlineData("numPenalties")] [InlineData("totalRaceTimeMs")]
Validate_OtherNegativeValues_Fail(string field)
[Fact] Validate_DriverNameOver64_Fails                   // new string('A', 65)
[Fact] Validate_TooManyStints_Fails                      // 9개
[Fact] Validate_NullStints_AreTreatedAsEmpty             // tyreStints null → 통과
[Fact] Validate_NullElements_Fail                        // results에 null, tyreStints에 null 각각
[Fact] Validate_StintNegativeEndLap_Fails
[Fact] Validate_ActualCompoundOver10_Fails
[Theory] [InlineData(null)] [InlineData("")] [InlineData("123456789012345678901234567890123")] // 33자
Validate_BadSessionRef_Fails(string? sessionRef)
[Fact] Validate_TwoPlayers_Fails
```

- [ ] **Step 2: 인입 테스트 작성** (Fake: `FakeSeasons`, `FakeSessions`, `FakeTracks`, `SequentialIdGenerator`. `Now = 2026-10-17T12:00:00Z`, envelope `occurredAt = Now.AddSeconds(-5)`, 기본 페이로드: DriverCareer, Race/Race, 링크 11·22·33, 트랙 10)

```csharp
[Fact] Apply_CareerRace_CreatesSeasonWeekendSessionResultsAndStints
    // Stored(IsNew: true, "link:11:22:33"). Season(UserId = 장치 주인, SeasonLinkId 11, GameMode DriverCareer, First=Last=occurredAt),
    // RaceWeekend(SeasonId, WeekendLinkId 22, TrackId 매핑, First=occurredAt), GameSession(SeasonId·RaceWeekendId 연결, AgentDeviceId, ClassifiedAt = occurredAt),
    // 결과 2행(DriverKey "player"·"driver:9"), 스틴트 번호 1·2, 컴파운드 Medium·Hard
[Fact] Apply_NonSeasonMode_CreatesSessionOnly            // GameMode "Online" → SessionKey "uid:{ref}", SeasonId == null, 시즌 Add 0회
[Fact] Apply_ExistingSeasonAndWeekend_Reuses_AndTouches  // 같은 시즌 두 번째 주말 → 시즌 Add 0회, LastSessionAt 확장, 주말 Add 1회
[Fact] Apply_SameKeyNewer_MergesResults                  // 기존 세션 ClassifiedAt < occurredAt → Stored(IsNew: false), SessionRef·AgentDeviceId·ClassifiedAt·UpdatedAt 갱신, 결과는 Task 1 병합 규칙
[Fact] Apply_SameKeyOlder_IsIgnored_AndTouchesNothing    // 기존 ClassifiedAt > occurredAt → Ignored, 시즌 First/Last 불변, Add 0회
[Theory] [InlineData("track")] [InlineData("kind")]
Apply_SameKeyDifferentTrackOrKind_StoresUnderUidKey_WithoutSeason(string mismatch)
    // 기존 세션과 TrackId 또는 SessionKind가 다름 → 새 세션 SessionKey "uid:{ref}", SeasonId·RaceWeekendId null, 시즌·주말 Touch 없음, 기존 세션 불변
[Fact] Apply_BlankDriverName_IsStoredAsNull              // "   " → DriverName null, DriverKey는 이름 없는 규칙
[Fact] Apply_TimeTrial_IsIgnored                         // sessionType "TimeTrial" 또는 gameMode "TimeTrial" → Ignored, 트랙 조회 0회
[Fact] Apply_FutureOccurredAt_IsClampedToServerSkew      // occurredAt = Now + 3시간 → ClassifiedAt == Now + 5분
[Fact] Apply_UnknownEnumStrings_FallBackToDefaults       // sessionKind "Sprint", resultStatus "Overtime", visualCompound "Hyper" → Unknown, gameMode "NewMode" → Other(시즌 없음)
[Fact] Apply_MissingParticipant_UsesSessionScopedCarKey  // DriverName null, carIndex 5 → DriverKey "car:{ref}:5", DriverName null
[Fact] Apply_MalformedPayload_Rejects                    // payload = JSON 배열 → Rejected("SessionClassified payload 파싱 실패"), 어떤 Add도 없음
[Fact] Apply_InvalidPayload_RejectsWithDetail            // reason.StartsWith("SessionClassified 검증 실패: ")
[Fact] Apply_UnknownTrack_Rejects                        // Rejected("트랙 매핑 없음(gameCode=F1_25, trackId=99)")
```

- [ ] **Step 3: 실패 확인** — `dotnet test backend/tests/SimCenter.Application.Tests --filter "FullyQualifiedName~Seasons|FullyQualifiedName~LenientEnum" --nologo` → 컴파일 실패.
- [ ] **Step 4: 구현** — 파싱은 Web 기본 `JsonSerializerOptions`(enum이 문자열 필드라 변환기 불필요), `JsonException`과 루트가 객체가 아닌 경우를 파싱 실패로. `ApplyAsync`는 스펙 §6.2 순서 그대로 — **1~7단계에서는 Add·수정 금지**(불변식). 결과 행 생성 시 `DriverKeys.Build`, 스틴트 번호는 1부터. 결과별 로그는 스펙 §6.4. DI 등록·`TelemetryIngestService` 연결은 하지 않는다(Task 3).
- [ ] **Step 5: 계약 파일 작성** — 기존 스키마와 같은 draft-07 형식. `session_classified.json`은 스펙 §5.5 필드 전부 required(nullable 필드는 `"type": ["string","null"]`/`["integer","null"]`), enum 값 나열, `sessionRef` `minLength 1`·`maxLength 32`, `results` `maxItems: 32`, `tyreStints` `maxItems: 8`. 샘플 envelope(`type: "SessionClassified"`, `gameCode: "F1_25"`). `lap_finished.json`의 새 필드에는 "없으면 uid 키" 설명.
- [ ] **Step 6: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → 전체 PASS(EF 모델·DI 불변).
- [ ] **Step 7: 커밋** — `feat(app): SessionClassified 계약과 시즌·세션 인입 유스케이스 추가(P7)`

---

### Task 3: 영속성 + 마이그레이션 + 인입 배선 + 허브 한도 + `Lap.SessionKey` + 인입 E2E

**Files:**
- Create: `backend/src/SimCenter.Infrastructure/Persistence/Configurations/SeasonConfiguration.cs`, `RaceWeekendConfiguration.cs`, `GameSessionConfiguration.cs`, `SessionResultConfiguration.cs`, `SessionResultTyreStintConfiguration.cs`
- Create: `backend/src/SimCenter.Infrastructure/Persistence/Repositories/SeasonRepository.cs`, `GameSessionRepository.cs`
- Modify: `AppDbContext.cs`(DbSet 5개), `LapConfiguration.cs`(`SessionKey` max 80), `backend/src/SimCenter.Domain/Entities/Lap.cs`(`string? SessionKey`), `backend/src/SimCenter.Application/Telemetry/TelemetryContracts.cs`(`LapFinishedPayloadDto`에 `string? GameMode = null, long SeasonLinkId = 0, long WeekendLinkId = 0, long SessionLinkId = 0`), `backend/src/SimCenter.Infrastructure/DependencyInjection.cs`(저장소 2개 Scoped)
- Modify(배선, Task 2에서 옮김): `backend/src/SimCenter.Application/Telemetry/TelemetryIngestService.cs`(유형 분기 + `CreateLap`의 `SessionKey`), `backend/src/SimCenter.Application/DependencyInjection.cs`(`ISessionClassificationIngestor` Scoped)
- Modify: `backend/src/SimCenter.Api/Hubs/TelemetryHub.cs`(`public const long MaxMessageBytes = 64 * 1024;`), `backend/src/SimCenter.Api/Program.cs`(`.AddHubOptions<TelemetryHub>(o => o.MaximumReceiveMessageSize = TelemetryHub.MaxMessageBytes)`)
- Create: `backend/src/SimCenter.Infrastructure/Persistence/Migrations/*_AddSeasonsAndSessions.cs`
- Test: `backend/tests/SimCenter.Api.IntegrationTests/SessionClassifiedIngestE2ETests.cs`, `backend/tests/SimCenter.Api.IntegrationTests/SessionClassifiedPayloads.cs`; Modify: `TelemetryIngestServiceTests`

**Interfaces:**
- Consumes: Task 1 엔티티·`SessionKeys`, Task 2 저장소 인터페이스·`ISessionClassificationIngestor`·`ClassificationOutcome`·`LenientEnum`.
- Produces: 테이블 `seasons`, `race_weekends`, `game_sessions`, `session_results`, `session_result_tyre_stints`, 컬럼 `laps.session_key`. 저장소 구현(Task 2 시그니처).
  `TelemetryIngestService.SessionClassifiedType = "SessionClassified"`. `CreateLap`의 `SessionKey`: `sessionRef`가 1~32자면 `SessionKeys.For(LenientEnum.Parse<GameMode>(payload.GameMode), payload.SeasonLinkId, payload.WeekendLinkId, payload.SessionLinkId, payload.SessionRef)`, 아니면 null. 테스트 헬퍼 `SessionClassifiedPayloads.Build(int carCount, int stintsPerCar, long seasonLink, long weekendLink, long sessionLink, string sessionKind = "Race", string sessionType = "Race", int playerCarIndex = 0, int trackId = <시드 트랙>, string namePrefix = "DRIVER") → object`(Task 5도 사용).

- [ ] **Step 1: 단위 테스트 추가** — `TelemetryIngestServiceTests`(생성자에 반환값을 지정할 수 있는 `FakeClassificationIngestor` 주입):

```csharp
[Fact] SessionClassified_Stored_RecordsProcessedEventAndSavesOnce  // ProcessedEvent(EventType "SessionClassified") 1건, SaveCount == 1, Ack
[Fact] SessionClassified_Ignored_StillRecordsProcessedEvent        // Ack, ProcessedEvent 1건, SaveCount == 1
[Fact] SessionClassified_Rejected_SavesOnlyLastSeen               // Reject("x"), ProcessedEvent 없음, LastSeen 바뀐 경우에만 SaveCount == 1
[Fact] SessionClassified_FromRevokedDevice_RejectsBeforeIngestor  // ingestor 호출 0회
[Fact] LapFinished_WithCareerContext_StoresLinkSessionKey          // gameMode "DriverCareer", 링크 11·22·33 → lap.SessionKey == "link:11:22:33"
[Fact] LapFinished_WithoutContext_StoresUidKey                     // 기존 페이로드(필드 없음) → "uid:0xSESSION"
[Fact] LapFinished_OverlongSessionRef_StoresNullKey                // 33자 sessionRef → SessionKey null, 랩은 저장
```

- [ ] **Step 2: E2E 테스트 작성** (기존 `TelemetryIngestE2ETests`처럼 가입 → 연결 → 장치 키로 허브 접속, 실제 WebSocket)

```csharp
[Fact] SessionClassified_CareerRace_PersistsSeasonWeekendSessionAndResults
    // 22대·스틴트 2개 → Ack. DB: seasons 1, race_weekends 1, game_sessions 1(SessionKey "link:11:22:33"), 활성 session_results 22, 스틴트 44, IsPlayer 행 1
[Fact] Reclassified_SameKey_FewerCars_MergesWithoutError
    // 같은 키로 20대(다른 eventId, occurredAt +1분) → Ack(예외 없음), 활성 결과 20행, soft-deleted 2행, game_sessions 여전히 1
[Fact] Reclassified_SameKey_NewCarAndNewStints_AreInserted
    // 같은 키로 car 23 추가 + 기존 차의 스틴트 변경 → Ack(DbUpdateConcurrencyException 없음 — ValueGeneratedNever 회귀), 새 행·새 스틴트가 DB에 있음
[Fact] SessionClassified_ValidationMaxPayload_PassesHub
    // 32대 × 스틴트 8개, 이름 = 비ASCII 64자(직렬화 약 44KB — 기본 32KB 한도 초과) → Ack(명시한 64KiB 한도 회귀)
[Fact] SameKeyDifferentTrack_StoredWithoutSeason          // 같은 링크 키·다른 트랙 → game_sessions 2, 두 번째는 season_id·race_weekend_id null
[Fact] LapFinished_PersistsSessionKey                     // laps.session_key == "link:11:22:33"
```

- [ ] **Step 3: 실패 확인** — `dotnet test backend/SimCenter.sln --nologo` → 컴파일 실패.
- [ ] **Step 4: 구성·저장소 구현** — 스펙 §4.2 그대로: enum은 `HasConversion<string>()` + 길이, 문자열 길이, FK `Restrict`(결과·스틴트는 부모 `Cascade`), **모든 unique index에 `.HasFilter("is_deleted = false")`** — `(UserId, GameCode, SeasonLinkId)`, `(SeasonId, WeekendLinkId)`, `(UserId, GameCode, SessionKey)`, `(GameSessionId, CarIndex)`. 일반 인덱스 `(UserId, LastSessionAt)`, `(UserId, ClassifiedAt)`, `(RaceWeekendId)`, `(SeasonId)`, `(GameSessionId, DriverKey)`. `GameSession`→`AgentDevice`·`User`는 내비게이션 없이 FK만(`HasOne<AgentDevice>().WithMany().HasForeignKey(x => x.AgentDeviceId)`). 새 엔티티 5종 모두 `Property(x => x.Id).ValueGeneratedNever()`. `GetByKeyWithResultsAsync`는 `Include(Results).ThenInclude(TyreStints)`(전역 필터가 활성 행만 싣는다).
  이어서 배선: `TelemetryIngestService` 4단계를 `switch (envelope.Type)`로 바꾸고, Stored·Ignored면 `ProcessedEvent`를 추가하고 `SaveChangesAsync` 한 번, Rejected면 기존 `FinishWithoutLapAsync`. 클래스 주석의 처리 순서도 갱신한다. Application DI에 ingestor Scoped 등록.
- [ ] **Step 5: 마이그레이션 생성** — `cd backend; dotnet ef migrations add AddSeasonsAndSessions --project src/SimCenter.Infrastructure --output-dir Persistence/Migrations` → `Up`이 테이블 5개 생성 + `laps.session_key` 추가만 포함하는지, unique index 4개에 `filter: "is_deleted = false"`가 있는지 확인.
- [ ] **Step 6: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → 전체 PASS. 백엔드를 한 번 실행해 로컬 DB에 마이그레이션이 적용되고 시작 로그에 오류가 없는지 확인 후 종료.
- [ ] **Step 7: 커밋** — `feat(infra): 시즌·세션 결과 저장소와 AddSeasonsAndSessions 마이그레이션 추가(P7)`

---

### Task 4: 조회 계산기 · 팀 카탈로그 · 조회 서비스 (Application, Fake 저장소)

**Files:**
- Create: `backend/src/SimCenter.Application/Seasons/Queries/SeasonReadRows.cs`, `SeasonSessionSelector.cs`, `RoundNumbering.cs`, `StandingsCalculator.cs`, `TeamCatalog.cs`, `SeasonDtos.cs`, `SessionDtos.cs`, `ISeasonQueryService.cs`, `SeasonQueryService.cs`, `ISessionQueryService.cs`, `SessionQueryService.cs`
- Modify: `ISeasonRepository.cs`, `IGameSessionRepository.cs`(조회 메서드 추가), `backend/src/SimCenter.Application/DependencyInjection.cs`
- Test: `backend/tests/SimCenter.Application.Tests/Seasons/SeasonSessionSelectorTests.cs`, `StandingsCalculatorTests.cs`, `RoundNumberingTests.cs`, `TeamCatalogTests.cs`, `SeasonQueryServiceTests.cs`, `SessionQueryServiceTests.cs`

**Interfaces:**
- Consumes: Task 1 enum·엔티티, 기존 `PagedResult<T>`, `NotFoundException`.
- Produces:
  - 읽기 행: `SeasonResultRow(Guid SeasonId, Guid WeekendId, Guid SessionId, SessionType SessionType, SessionKind SessionKind, DateTime ClassifiedAt, string DriverKey, string? DriverName, int CarIndex, int? TeamId, bool IsPlayer, bool IsAiControlled, int Position, ResultStatus ResultStatus, int Points)`,
    `WeekendRow(Guid WeekendId, Guid SeasonId, string TrackName, DateTime FirstSessionAt)`,
    `SessionSummaryRow(Guid SessionId, DateTime ClassifiedAt, string TrackName, SessionType SessionType, SessionKind SessionKind, GameMode GameMode, Guid? SeasonId, int CarCount, int? MyPosition, int? MyGridPosition, ResultStatus? MyResultStatus, int? MyBestLapTimeMs, int? MyPoints)`
  - 저장소 조회 추가(모두 no tracking, `UserId` 조건 필수):
    `ISeasonRepository.GetMyPageAsync(Guid userId, int skip, int take, ct) → (IReadOnlyList<Season> Items, int Total)`, `GetMineAsync(Guid userId, Guid seasonId, ct) → Season?`,
    `GetWeekendRowsAsync(IReadOnlyCollection<Guid> seasonIds, ct) → IReadOnlyList<WeekendRow>`,
    `GetResultRowsAsync(IReadOnlyCollection<Guid> seasonIds, bool scoringRowsOnly, ct) → IReadOnlyList<SeasonResultRow>`(`scoringRowsOnly` = 레이스 세션이거나 `Points > 0`인 행만);
    `IGameSessionRepository.GetMyPageAsync(Guid userId, SessionType? sessionType, int skip, int take, ct) → (IReadOnlyList<SessionSummaryRow> Items, int Total)`, `GetMineDetailAsync(Guid userId, Guid sessionId, ct) → GameSession?`(Track·활성 Results·활성 TyreStints 포함)
  - `SeasonSelection(IReadOnlyList<SeasonResultRow> CountedRows, IReadOnlyDictionary<Guid, Guid> MainRaceSessionByWeekend)`; `static class SeasonSessionSelector { SeasonSelection Select(IReadOnlyList<SeasonResultRow> rows); }`
  - `static class RoundNumbering { IReadOnlyDictionary<Guid, int> Assign(IEnumerable<WeekendRow> weekends); }`
  - `DriverStanding(int Position, string DriverKey, string Name, int? TeamId, bool IsPlayer, bool IsAiControlled, int Points, int Wins, int Podiums, IReadOnlyList<StandingCell> Cells)`, `StandingCell(Guid WeekendId, int? Position, ResultStatus? ResultStatus, int Points)`, `ConstructorStanding(int Position, int TeamId, int Points, int Wins)`, `SeasonStandings(IReadOnlyList<DriverStanding> Drivers, IReadOnlyList<ConstructorStanding> Constructors)`;
    `static class StandingsCalculator { SeasonStandings Calculate(SeasonSelection selection, string gameCode); }` — **대상 행** = `CountedRows` 중 `SessionType.Race`이거나 `Points > 0`인 행(스펙 D-31). 시즌 목록(DB에서 이미 대상 행만 읽음)과 상세(전체 행)가 같은 결과를 낸다. 팀 이름은 `TeamCatalog.Resolve(gameCode, teamId)`.
    `static class WinnerNames { IReadOnlyDictionary<Guid, string> ByWeekend(SeasonSelection selection); }` — 본 레이스 1위 행의 `DriverName` ?? `Car {carIndex+1}`.
  - `TeamInfo(string Name, string Color)`; `static class TeamCatalog { const string FallbackColor = "#9CA3AF"; TeamInfo Resolve(string gameCode, int? teamId); }`
  - DTO는 스펙 §7.2 필드 그대로: `SeasonSummaryDto`, `SeasonDetailDto(SeasonSummaryDto Season, IReadOnlyList<SeasonRoundDto> Rounds, SeasonStandingsDto Standings)`, `SeasonRoundDto`, `SeasonRoundSessionDto`, `SeasonStandingsDto`, `DriverStandingDto`(+ `Cells: IReadOnlyList<StandingCellDto>`, `Round` 번호로), `StandingCellDto`, `ConstructorStandingDto`, `SessionSummaryDto`, `SessionDetailDto(SessionDetailHeaderDto Session, IReadOnlyList<SessionResultDto> Results)`, `SessionDetailHeaderDto`, `SessionResultDto`, `TyreStintViewDto`
  - `ISeasonQueryService { Task<PagedResult<SeasonSummaryDto>> GetMySeasonsAsync(Guid userId, int page, int pageSize, ct); Task<SeasonDetailDto> GetMySeasonAsync(Guid userId, Guid seasonId, ct); }` — 상수 `DefaultPageSize = 20`, `MaxPageSize = 20`.
  - `ISessionQueryService { Task<PagedResult<SessionSummaryDto>> GetMySessionsAsync(Guid userId, SessionType? sessionType, int page, int pageSize, ct); Task<SessionDetailDto> GetMySessionAsync(Guid userId, Guid sessionId, ct); }` — 상수 `DefaultPageSize = 20`, `MaxPageSize = 100`.

- [ ] **Step 1: 계산기 테스트 작성** (`Row(...)` 헬퍼로 `SeasonResultRow` 생성)

```csharp
// SeasonSessionSelectorTests
[Fact] Select_DuplicateKindInWeekend_KeepsLatest           // 같은 주말 Race 2건(10:00, 11:00) → 11:00 세션 행만 CountedRows에
[Fact] Select_UnknownKind_IsNotDeduplicated               // Unknown 2건 → 둘 다 남음
[Fact] Select_MainRace_IsLatestRaceSession               // Race(10:00, 스프린트) + Race2(14:00) → MainRace = Race2 세션
[Fact] Select_WeekendWithoutRace_HasNoMainRace
[Fact] Select_SprintOnlyWeekend_SprintIsMainRace           // 레이스가 스프린트 1건뿐 → 그 세션이 MainRace
// StandingsCalculatorTests
[Fact] Calculate_SumsPointsAcrossCountedSessions_OrdersDesc     // 본 레이스 25+18, 스프린트 8 → 51
[Fact] Calculate_DuplicateSession_NotDoubleCounted              // 같은 주말 Race 2건(25점씩) → 25
[Fact] Calculate_SprintWin_IsNotAWin                            // 스프린트 1위 → Wins 0, 본 레이스 1위 → Wins 1
[Fact] Calculate_Tie_BrokenByMainRaceCountback                  // 같은 점수: 1위 1회 vs 2위 2회 → 1위 1회가 앞
[Fact] Calculate_TieAfterCountback_BrokenByName                 // Ordinal 순
[Fact] Calculate_SameNameAndRecord_BrokenByDriverKey            // 이름 "Car 5" 두 명 → DriverKey Ordinal 순
[Fact] Calculate_PracticeOnlyDriver_IsNotInStandings            // FP1에만 있는 드라이버 → Drivers에 없음
[Fact] Calculate_ScoringRowsOnlyInput_EqualsFullInput           // 같은 시즌의 전체 행과 대상 행만 넣은 결과가 같다(목록·상세 일치)
[Fact] Calculate_UsesLatestNameTeamAndAiFlag
[Fact] Calculate_NullName_FallsBackToCarLabel                   // DriverName null, CarIndex 4 → "Car 5"
[Fact] Calculate_Podiums_CountMainRaceTop3
[Fact] Calculate_Cells_OnlyRoundsWithResults                    // 2라운드 중 1라운드만 결과 → Cells 1개
[Fact] Cells_SprintWeekend_UseMainRacePosition_AndSumWeekendPoints // 스프린트 P3(6점) + 본 레이스 P1(25점) → Position 1, Points 31
[Fact] Cells_WeekendWithoutRace_PositionAndStatusNull           // 예선만 → Position null, ResultStatus null, Points 0
[Fact] Calculate_Constructors_SumByTeam_ExcludeNullTeam_TieByWinsThenNameThenTeamId // 팀 2와 478(둘 다 "Red Bull Racing") → 별도 행, 동점이면 TeamId 순
[Fact] WinnerNames_UseMainRaceWinner_WithCarFallback
// RoundNumberingTests
[Fact] Assign_OrdersByFirstSessionAt_ThenId
// TeamCatalogTests
[Theory] [InlineData(2, "Red Bull Racing")] [InlineData(8, "McLaren")] [InlineData(104, "My Team")] [InlineData(187, "Red Bull Racing")]
[InlineData(478, "Red Bull Racing")] [InlineData(485, "Audi")] [InlineData(486, "Cadillac")]
Resolve_KnownTeam(int id, string name)
[Fact] Resolve_UnknownTeam_UsesFallback                         // 999 → ("Team 999", "#9CA3AF")
[Fact] Resolve_NullTeam_IsUnknownTeam                           // null → ("Unknown Team", "#9CA3AF")
[Fact] Resolve_OtherGameCode_UsesFallback                       // ("ACC", 2) → ("Team 2", "#9CA3AF")
[Fact] AllColors_AreHexRrggbb                                   // 등록된 모든 색이 ^#[0-9A-F]{6}$
```

- [ ] **Step 2: 조회 서비스 테스트 작성** (Fake 저장소 — 호출 횟수 기록)

```csharp
// SeasonQueryServiceTests
[Fact] GetSeasons_MapsSummary_WithMyPositionAndLeader
[Fact] GetSeasons_PlayerAbsent_MyFieldsNull
[Fact] GetSeasons_NoResults_LeaderNull
[Fact] GetSeasons_ManySeasons_LoadsResultRowsOnce             // 시즌 3개 → GetResultRowsAsync 1회(scoringRowsOnly: true), GetWeekendRowsAsync 1회
[Fact] GetSeasons_ClampsPaging                                 // page 0 → 1, pageSize 0 → 20, 50 → 20
[Fact] GetSeason_BuildsRoundsAndStandings                      // 라운드 2개(winnerName·myPoints·세션 칩 ClassifiedAt 순), 드라이버 cells의 round 번호, 팀 이름·색
[Fact] GetSeason_NotMine_ThrowsNotFound                        // GetMineAsync null → NotFoundException
// SessionQueryServiceTests
[Fact] GetSessions_PassesFilterAndPaging                       // sessionType Race, page 2, pageSize 15 → skip 15, take 15
[Fact] GetSessions_ZeroBestLap_IsNull                          // MyBestLapTimeMs 0 → null
[Fact] GetSession_MapsResults_FastestLapNullsAndFallbackName   // 최소 bestLap 행 isFastestLap, bestLap 0 → null·false, totalRaceTime 0 → null, DriverName null → "Car N", Position 같으면 CarIndex 순
[Fact] GetSession_InSeason_HasRoundMatchingSeason              // round = RoundNumbering 결과
[Fact] GetSession_NotMine_ThrowsNotFound
```

- [ ] **Step 3: 실패 확인** — `dotnet test backend/tests/SimCenter.Application.Tests --filter "FullyQualifiedName~Seasons" --nologo` → 컴파일 실패.
- [ ] **Step 4: 구현** — 카운트백은 본 레이스 순위별 개수를 1위부터 비교한다. `TeamCatalog` 값(`F1_25`만, 색은 `#RRGGBB`): 0 Mercedes `#27F4D2`, 1 Ferrari `#E8002D`, 2 Red Bull Racing `#3671C6`, 3 Williams `#64C4FF`, 4 Aston Martin `#229971`, 5 Alpine `#0093CC`, 6 Racing Bulls `#6692FF`, 7 Haas `#B6BABD`, 8 McLaren `#FF8000`, 9 Sauber `#52E252`, 41 F1 Generic `#9CA3AF`, 104 My Team `#6366F1`, 185~194는 0~9와 같은 이름·색, 476~484는 0~8과 같은 이름·색, 485 Audi `#BB0A30`, 486 Cadillac `#B5B5B5`. 시즌 상세의 내 칩 값은 `SeasonResultRow.IsPlayer` 행에서 읽는다(상세는 `scoringRowsOnly: false`).
- [ ] **Step 5: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → 전체 PASS.
- [ ] **Step 6: 커밋** — `feat(app): 시즌 Standings 계산과 시즌·세션 조회 서비스 추가(P7)`

---

### Task 5: 조회 API · 저장소 조회 구현 · OpenAPI · 조회 E2E

**Files:**
- Create: `backend/src/SimCenter.Api/Controllers/MySeasonsController.cs`(`[Route("api/v1/me/seasons")]`), `MySessionsController.cs`(`[Route("api/v1/me/sessions")]`)
- Modify: `SeasonRepository.cs`, `GameSessionRepository.cs`(Task 4 조회 메서드), `shared/openapi/openapi.yaml`, `backend/src/SimCenter.Api/SimCenter.Api.http`(예시 요청)
- Test: `backend/tests/SimCenter.Api.IntegrationTests/SeasonsApiE2ETests.cs`

**Interfaces:**
- Consumes: Task 4 서비스·DTO, Task 3 `SessionClassifiedPayloads`, 기존 `User.GetRequiredUserId()`, `ValidationException(field, error)`.
- Produces: 스펙 §7.1 엔드포인트 4개(`[Authorize]`, `ProducesResponseType` 200·400·404). `MySessionsController.ParseSessionType(string?) → SessionType?`(private).

- [ ] **Step 1: E2E 테스트 작성** (가입 → 연결 → 허브로 2라운드 × (Q1 + Race) 전송 후 REST 확인)

```csharp
[Fact] GetSeasons_NoData_ReturnsEmptyPage                 // 새 사용자: total 0, items []
[Fact] Seasons_AfterTwoRounds_ListAndDetail
    // /me/seasons: 1개, roundCount 2, myPosition·myPoints 기대값 / /me/seasons/{id}: rounds 2(각 세션 2개, ClassifiedAt 순), standings.drivers 22(각 cells 2), 1위 points 기대값
[Fact] Sessions_ListFilterAndDetail
    // /me/sessions?pageSize=15: total 4, ClassifiedAt DESC / ?sessionType=race: total 2 / /me/sessions/{id}: results 22, position 오름차순, round 2
[Fact] OtherUsersSeasonAndSession_Return404               // 다른 사용자 토큰으로 상세 2개 → 404
[Fact] NonGuidId_Returns404                               // /me/sessions/abc
[Fact] NoToken_Returns401
[Theory] [InlineData("TimeTrial")] [InlineData("4")] [InlineData("Banana")]
Sessions_InvalidSessionType_Returns400StandardProblem(string value) // type == "https://simcenter/errors/validation", errors["sessionType"] 존재
```

- [ ] **Step 2: 실패 확인** — `dotnet test backend/tests/SimCenter.Api.IntegrationTests --filter "FullyQualifiedName~SeasonsApiE2ETests" --nologo` → 404/컴파일 실패.
- [ ] **Step 3: 저장소 조회 구현** — 모두 `AsNoTracking` + `UserId` 조건. `GetResultRowsAsync`는 `session_results` ⨝ `game_sessions`(시즌 Id 목록, 전역 필터로 활성 행만) 프로젝션 **1쿼리**. 세션 `GetMyPageAsync`는 `Tracks` 조인 + 플레이어 행(`IsPlayer`) 서브쿼리 프로젝션, `CarCount`는 활성 결과 수. 트랙 이름은 조인 프로젝션(내비게이션 Include 대신).
- [ ] **Step 4: 컨트롤러 구현** — `MeController`와 같은 형식(primary constructor, `[FromQuery] int page = 1, [FromQuery] int pageSize = 20`). `sessionType`은 `[FromQuery] string? sessionType`을 `ParseSessionType`으로(`RankingsController.ParsePeriod`와 같은 방식, Global Constraints의 문구). 상세는 `{seasonId:guid}`·`{sessionId:guid}` 제약.
- [ ] **Step 5: OpenAPI 갱신** — 경로 4개와 스키마(스펙 §7.2 DTO, nullable 표시), 400·404는 기존 `ProblemDetails` 참조, 이벤트 계약 설명에 `SessionClassified` 링크.
- [ ] **Step 6: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → 전체 PASS. 백엔드 실행 후 Swagger에서 4개 경로가 보이는지 확인.
- [ ] **Step 7: 커밋** — `feat(api): 내 시즌·세션 조회 API 추가(P7)`

---

### Task 6: Agent.Core — 프레임 · `SessionResultTracker` · `SessionClassified` · 랩 맥락

**Files:**
- Create: `agent/src/SimCenter.Agent.Core/Telemetry/GameMode.cs`, `SessionKind.cs`, `ResultStatus.cs`, `TyreCompound.cs`, `TyreStint.cs`
- Create: `agent/src/SimCenter.Agent.Core/Telemetry/Frames/ParticipantsFrame.cs`, `ClassificationFrame.cs`; Modify: `Frames/SessionFrame.cs`
- Modify: `agent/src/SimCenter.Agent.Core/Telemetry/Events/TelemetryEvents.cs`, `TelemetryEventType.cs`
- Create: `agent/src/SimCenter.Agent.Core/Analysis/ITelemetryAnalyzer.cs`, `SessionResultTracker.cs`; Modify: `Analysis/LapAnalyzer.cs`
- Test: `agent/tests/SimCenter.Agent.Core.Tests/SessionResultTrackerTests.cs`; Modify: `LapAnalyzerTests.cs`(테스트 추가만)

**Interfaces:**
- Consumes: 기존 `SessionType`, `ITelemetryFrame`, `TelemetryEvent`, `EventMarker`.
- Produces:
  - enum 4종(Global Constraints, 백엔드와 같은 이름·순서). `TyreStint(int EndLap, TyreCompound VisualCompound, string? ActualCompound)`(namespace `SimCenter.Agent.Core.Telemetry`).
  - `SessionFrame(string SessionRef, int TrackId, SessionType SessionType, int PacketFormat, SessionKind SessionKind = SessionKind.Unknown, GameMode GameMode = GameMode.Other, uint SeasonLinkId = 0, uint WeekendLinkId = 0, uint SessionLinkId = 0, int TotalLaps = 0, int AiDifficulty = 0, bool IsNetworkGame = false)` — 기존 호출부 무수정.
  - `ParticipantInfo(int CarIndex, string Name, int? GameDriverId, int TeamId, int RaceNumber, bool IsAiControlled)`, `ParticipantsFrame(string SessionRef, IReadOnlyList<ParticipantInfo> Participants) : ITelemetryFrame`
  - `ClassificationRow(int CarIndex, int Position, int GridPosition, int NumLaps, int Points, int NumPitStops, int NumPenalties, ResultStatus ResultStatus, int BestLapTimeMs, int TotalRaceTimeMs, int PenaltiesTimeMs, IReadOnlyList<TyreStint> TyreStints)`, `ClassificationFrame(string SessionRef, int PlayerCarIndex, IReadOnlyList<ClassificationRow> Rows) : ITelemetryFrame`
  - `ClassifiedResult(int CarIndex, bool IsPlayer, int Position, int GridPosition, int NumLaps, int Points, int NumPitStops, int NumPenalties, ResultStatus ResultStatus, int BestLapTimeMs, int TotalRaceTimeMs, int PenaltiesTimeMs, string? DriverName, int? GameDriverId, int? TeamId, int? RaceNumber, bool IsAiControlled, IReadOnlyList<TyreStint> TyreStints)`
  - `SessionClassified(string SessionRef, int TrackId, SessionType SessionType, SessionKind SessionKind, GameMode GameMode, uint SeasonLinkId, uint WeekendLinkId, uint SessionLinkId, int TotalLaps, int AiDifficulty, bool IsNetworkGame, IReadOnlyList<ClassifiedResult> Results) : TelemetryEvent` (`Type => TelemetryEventType.SessionClassified`)
  - `LapFinished`에 뒤쪽 기본값 매개변수 `GameMode GameMode = GameMode.Other, uint SeasonLinkId = 0, uint WeekendLinkId = 0, uint SessionLinkId = 0`.
  - `ITelemetryAnalyzer { IReadOnlyList<TelemetryEvent> Process(ITelemetryFrame frame); }` — `LapAnalyzer`, `SessionResultTracker`가 구현(둘 다 상태 저장·스레드 안전 아님).

- [ ] **Step 1: 테스트 작성** (`Session(ref, type = Race, mode = DriverCareer)`, `Participants(ref, n)`, `Classification(ref, n, player)` 헬퍼)

```csharp
// SessionResultTrackerTests
[Fact] Classification_WithContextAndParticipants_EmitsOneEvent
    // Session("A") → Participants("A", 3) → Classification("A", 3, player: 1)
    // → SessionClassified 1건: 맥락(trackId·sessionKind·gameMode·링크 3개·totalLaps·aiDifficulty·isNetworkGame) 복사, Results 3행,
    //   carIndex별 이름·드라이버·팀·번호·AI 결합, Results[1].IsPlayer == true·나머지 false, 스틴트 그대로
[Fact] SecondClassification_SameSessionRef_IsIgnored
[Fact] Classification_ForDifferentSessionRef_IsIgnored      // 맥락 "A", 순위표 "B" → 0건
[Fact] Classification_WithoutContext_IsIgnored
[Fact] Classification_InTimeTrial_IsIgnored                 // SessionType.TimeTrial → 0건
[Fact] MissingParticipant_SendsNullIdentity                 // 참가자 2명, 순위표 3대 → car 2: DriverName/GameDriverId/TeamId/RaceNumber null, IsAiControlled false
[Fact] NewSessionRef_ClearsParticipants                     // Participants("A") → Session("B") → Classification("B") → 이름 모두 null
[Fact] ParticipantsForOtherSession_AreIgnored
[Fact] NewSessionAfterEmit_EmitsAgain                       // "A" 보냄 → Session("B")·Classification("B") → 1건 더
[Fact] SessionEnded_DoesNotResetTracker                     // EventMarker(End) 뒤에 온 같은 세션 순위표도 1건
// LapAnalyzerTests (추가)
[Fact] LapFinished_CarriesSessionModeAndLinks               // Session(mode DriverCareer, 링크 11·22·33) 후 랩 완료 → LapFinished.GameMode·링크 일치
```

- [ ] **Step 2: 실패 확인** — `dotnet test agent/tests/SimCenter.Agent.Core.Tests --nologo` → 컴파일 실패.
- [ ] **Step 3: 구현** — 스펙 §5.3·§5.4. 참가자는 carIndex → `ParticipantInfo` 사전으로 보관. `LapAnalyzer`는 `OnSession`에서 모드·링크를 보관하고 `ResetSession`에서 초기화.
- [ ] **Step 4: 통과 확인** — `dotnet test agent/SimCenter.Agent.sln --nologo` → 전체 PASS(기존 `LapAnalyzerTests`·`DomainEventFactoryTests` 무수정 통과).
- [ ] **Step 5: 커밋** — `feat(agent): 세션 최종 순위표를 SessionClassified 1건으로 만드는 추적기 추가(P7)`

---

### Task 7: Agent.Infrastructure — 패킷 매핑 · 파이프라인 · 크기 검사

**Files:**
- Create: `agent/src/SimCenter.Agent.Infrastructure/Mapping/F1EnumMaps.cs`
- Modify: `agent/src/SimCenter.Agent.Infrastructure/Mapping/F1PacketMapper.cs`, `Pipeline/TelemetryPipeline.cs`, `Sinks/OutboxTelemetrySink.cs`, `DependencyInjection.cs`
- Test: `agent/tests/SimCenter.Agent.Infrastructure.Tests/F1EnumMapsTests.cs`, `F1PacketMapperTests.cs`(추가), `OutboxTelemetrySinkSizeTests.cs`, `TelemetryPipelineAnalyzerTests.cs`, `DependencyInjectionTests.cs`

**Interfaces:**
- Consumes: Task 6 프레임·이벤트·`ITelemetryAnalyzer`, F1Game.UDP 26.0.0(`ParticipantsDataPacket`, `FinalClassificationDataPacket`, `ParticipantData`, `FinalClassificationData`, enum `GameMode`·`SessionType`·`ResultStatus`·`VisualCompound`·`ActualCompound`·`Driver.NetworkHuman`).
- Produces:
  - `static class F1EnumMaps { GameMode ToGameMode(F1Enums.GameMode); SessionKind ToSessionKind(F1Enums.SessionType); ResultStatus ToResultStatus(F1Enums.ResultStatus); TyreCompound ToVisualCompound(F1Enums.VisualCompound); string? ToActualCompoundLabel(F1Enums.ActualCompound); }`
  - `F1PacketMapper.MapParticipants(ParticipantsDataPacket) → ParticipantsFrame`, `MapClassification(FinalClassificationDataPacket) → ClassificationFrame`; `MapSession`은 새 필드를 채운다(기존 `SessionType` 정규화 결과는 그대로).
  - `TelemetryPipeline`은 `LapAnalyzer` 대신 `IEnumerable<ITelemetryAnalyzer> analyzers`를 받는다. 파이프라인의 프레임 처리부를 테스트할 수 있게 `internal Task ProcessFramesAsync(IReadOnlyList<ITelemetryFrame> frames, CancellationToken ct)`로 분리하고, 분석기마다 try/catch(오류 로그 후 다음 분석기).
  - `OutboxTelemetrySink(TelemetryOutbox outbox, ILogger<OutboxTelemetrySink> logger)`, `internal const int MaxEnvelopeBytes = 48 * 1024;` — 직렬화 UTF-8 바이트가 넘으면 `SessionClassified`는 모든 결과의 `TyreStints`를 빈 목록으로 바꿔 다시 재고(경고), 그래도 넘거나 다른 유형이면 적재하지 않는다(오류).
  - DI: `services.AddSingleton<LapAnalyzer>(); services.AddSingleton<SessionResultTracker>(); services.AddSingleton<ITelemetryAnalyzer>(sp => sp.GetRequiredService<LapAnalyzer>()); services.AddSingleton<ITelemetryAnalyzer>(sp => sp.GetRequiredService<SessionResultTracker>());`

- [ ] **Step 1: 테스트 작성** (기존 `Header()` 헬퍼, 배열은 `new FinalClassificationData[24]`·`new ParticipantData[24]`를 암시 변환)

```csharp
// F1EnumMapsTests
[Theory]
[InlineData(F1Enums.GameMode.GrandPrix23, GameMode.GrandPrix)] [InlineData(F1Enums.GameMode.TimeTrial, GameMode.TimeTrial)]
[InlineData(F1Enums.GameMode.OnlineCustom, GameMode.Online)] [InlineData(F1Enums.GameMode.OnlineWeeklyEvent, GameMode.Online)]
[InlineData(F1Enums.GameMode.StoryMode, GameMode.Story)] [InlineData(F1Enums.GameMode.StoryModeApxGp, GameMode.Story)]
[InlineData(F1Enums.GameMode.MyTeamCareer25, GameMode.MyTeamCareer)] [InlineData(F1Enums.GameMode.DriverCareer25, GameMode.DriverCareer)]
[InlineData(F1Enums.GameMode.Career25Online, GameMode.OnlineCareer)] [InlineData(F1Enums.GameMode.ChallengeCareer25, GameMode.ChallengeCareer)]
[InlineData(F1Enums.GameMode.SplitScreen, GameMode.Other)] [InlineData(F1Enums.GameMode.Benchmark, GameMode.Other)]
ToGameMode_Maps(F1Enums.GameMode input, GameMode expected)
[Fact] ToGameMode_UnknownValue_IsOther                       // (F1Enums.GameMode)200
[Fact] ToGameMode_LegacyGrandPrixValue3_IsGrandPrix          // (F1Enums.GameMode)3 → GrandPrix (상수 LegacyGrandPrixValue = 3)
[Fact] ToSessionKind_MapsAllNineteenByName                    // Enum.GetValues<F1Enums.SessionType>() 전부 → 같은 이름의 SessionKind
[Theory] ToResultStatus_Maps                                  // Invalid·Inactive → Unknown, 나머지 같은 이름
[Theory] ToVisualCompound_Maps                                // F1Soft→Soft, F1Medium→Medium, F1Hard→Hard, F1Inter→Intermediate, F1Wet→Wet, F2Soft→Unknown
[Theory] ToActualCompoundLabel_Maps                           // F1C0→"C0" … F1C6→"C6", F1Inter→"Inter", F1Wet→"Wet", F2Hard→null
// F1PacketMapperTests (추가)
[Fact] MapSession_MapsLinksModeAndContext                     // 링크 3개, DriverCareer25 → DriverCareer, Qualifying2 → SessionKind.Qualifying2, TotalLaps, AIDifficulty, IsNetworkGame
[Fact] MapParticipants_MapsSlots_AndNetworkHumanToNull        // car 0 AI(Driver 9, Team 2) → GameDriverId 9, TeamId 2 / car 1 NetworkHuman → GameDriverId null
[Fact] MapClassification_SkipsEmptySlots_AndConvertsUnits     // car 0 Finished P1, car 1 Inactive, car 2 Position 0 → Rows 1개;
                                                              // TotalRaceTime 1598.7654 → 1598765, PenaltiesTime 5 → 5000, NumTyreStints 2 → 스틴트 2개(EndLap·컴파운드)
[Fact] Map_RoutesParticipantsAndClassificationPackets         // UnionPacket(ParticipantsDataPacket)·UnionPacket(FinalClassificationDataPacket) → 각 프레임 1개
// OutboxTelemetrySinkSizeTests (임시 SQLite Outbox — 기존 TelemetryOutboxTests 방식)
[Fact] SessionClassified_IsCamelCaseWithStringEnums           // "type":"SessionClassified", "gameMode":"DriverCareer", "visualCompound":"Medium", "gameDriverId":null
[Fact] MaxRealisticPayload_IsEnqueued_UnderLimit              // 24대 × 스틴트 8개, 이름 = 비ASCII 10자 → 적재됨, 바이트 ≤ MaxEnvelopeBytes
[Fact] OversizedSessionClassified_IsEnqueuedWithoutStints     // 스틴트만으로 한도를 넘도록 만든 페이로드 → 적재됨, 모든 tyreStints == []
[Fact] OversizedEvenWithoutStints_IsDropped                   // 이름 길이로 한도를 넘김 → 적재 0건
// TelemetryPipelineAnalyzerTests
[Fact] ThrowingAnalyzer_DoesNotBlockOthers                    // [던지는 분석기, 이벤트 1건 분석기] → 싱크에 1건
// DependencyInjectionTests
[Fact] Analyzers_AreRegistered_AsSingletons                   // IEnumerable<ITelemetryAnalyzer>에 LapAnalyzer·SessionResultTracker, LapAnalyzer는 같은 인스턴스
```

- [ ] **Step 2: 실패 확인** — `dotnet test agent/tests/SimCenter.Agent.Infrastructure.Tests --nologo` → 컴파일 실패.
- [ ] **Step 3: 구현** — 스펙 §5.2. `TotalRaceTimeMs = (int)Math.Round(TotalRaceTime * MillisecondsPerSecond, MidpointRounding.AwayFromZero)`, `MillisecondsPerSecond = 1000`. 스틴트는 `Math.Min(NumTyreStints, 8)`개. 빈 칸 판정 `ResultStatus is Invalid or Inactive || Position == 0`. 파이프라인 클래스 주석을 "분석기 목록(순서 무관, 분석기별 예외 격리)"으로 고친다.
- [ ] **Step 4: 통과 확인** — `dotnet test agent/SimCenter.Agent.sln --nologo` → 전체 PASS. `dotnet build agent/SimCenter.Agent.sln --nologo` 경고 0.
- [ ] **Step 5: 커밋** — `feat(agent): Participants·Final Classification 매핑과 분석기 파이프라인·크기 검사 추가(P7)`

---

### Task 8: Flutter Sessions (공용 위젯 · 표시 규칙 · 목록 · 세션 결과)

**Files:**
- Create: `app/lib/core/widgets/pagination_bar.dart`(Laps의 `_PaginationBar` 추출), `app/lib/core/widgets/not_found_state.dart`, `app/lib/core/util/hex_color.dart`; Modify: `app/lib/features/laps/presentation/track_laps_page.dart`(공용 위젯 사용)
- Create: `app/lib/features/sessions/domain/session_models.dart`, `session_display.dart`
- Create: `app/lib/features/sessions/data/sessions_repository.dart`, `application/sessions_providers.dart`
- Create: `app/lib/features/sessions/presentation/sessions_page.dart`, `session_detail_page.dart`, `session_results_table.dart`, `tyre_stints_view.dart`
- Modify: `app/lib/core/theme/app_colors.dart`(토큰), `app/lib/core/router/app_router.dart`(`/sessions`, `/sessions/:sessionId`), `app/lib/core/shell/nav_items.dart`(Sessions를 Laps 앞에)
- Test: `app/test/session_display_test.dart`, `app/test/hex_color_test.dart`, `app/test/session_models_test.dart`, `app/test/sessions_repository_test.dart`, `app/test/sessions_page_test.dart`, `app/test/session_detail_page_test.dart`; Modify: `app/test/laps_page_test.dart`(공용 바로 페이지 이동), `app/test/app_router_test.dart`, `app/test/app_shell_test.dart`, `app/test/support/fakes.dart`

**Interfaces:**
- Consumes: 스펙 §7.2 JSON, 기존 `dioProvider`, `ApiException(statusCode)`, `paginationLabel`, `lap_time.dart`, `ErrorRetry`, `isNavItemSelected`.
- Produces:
  - `PaginationBar({required int page, required int pageSize, required int total, required ValueChanged<int> onPageChanged})`
  - `Color parseHexColor(String? hex, {required Color fallback})` — `#RRGGBB`만 허용.
  - 모델(`fromJson`): `SessionSummary`, `SessionsPage(page, pageSize, total, items)`, `SessionDetail(header, results)`, `SessionDetailHeader`, `SessionResult`, `TyreStintView`.
  - `session_display.dart`(순수): `String sessionKindLabel(String kind)`, `String resultStatusLabel(String status)`, `bool isRunningOrFinished(String status)`, `String gameModeLabel(String mode)`, `String formatRaceTime(int ms)`, `String formatGapMs(int ms)`, `SessionResult? referenceRow(List<SessionResult> results, {required bool isRace})`(레이스: 순위가 가장 앞인 Finished·Active 행, 그 외: 베스트 랩이 가장 빠른 행 — 스펙 §8.4), `String timeOrGap(SessionResult row, SessionResult? reference, {required bool isRace})`, `String penaltyLabel(int numPenalties, int penaltiesTimeMs)`.
    `gameModeLabel`: DriverCareer → `Driver Career`, MyTeamCareer → `My Team`, OnlineCareer → `Online Career`, ChallengeCareer → `Challenge Career`, GrandPrix → `Grand Prix`, TimeTrial → `Time Trial`, Online → `Online`, Story → `Story`, 그 외 → `Other`.
  - 상수: `kSessionsPageSize = 15`, `kSessionTableCompactWidth = 600`. 필터 `all|race|qualifying|practice` ↔ API `sessionType`(null|`Race`|`Qualifying`|`Practice`), 모르는 값 → `all`.
  - `SessionsRepository { Future<SessionsPage> getMySessions({String? sessionType, int page = 1, int pageSize = kSessionsPageSize}); Future<SessionDetail> getMySession(String sessionId); }`, `sessionsRepositoryProvider`
  - `SessionsQuery(String filter, int page)`(값 동등성), `sessionsProvider` = `FutureProvider.autoDispose.family<SessionsPage, SessionsQuery>`, `sessionDetailProvider` = `FutureProvider.autoDispose.family<SessionDetail, String>`
  - `AppColors`: `podiumGold #F5C542`, `podiumSilver #C0C7D1`, `podiumBronze #CD7F32`, `fastestLap #D946EF`, `tyreSoft #EF4444`, `tyreMedium #FACC15`, `tyreHard #F3F4F6`, `tyreIntermediate #22C55E`, `tyreWet #3B82F6`.
  - 위젯: `SessionsPage(filter)`, `SessionDetailPage(sessionId)`, `SessionResultsTable(results, isRace)`, `TyreStintsView(stints)`, `NotFoundState(message, backLabel, backPath)`.

- [ ] **Step 1: 표시 규칙·색 테스트 작성**

```dart
test('sessionKindLabel maps every kind', ...);     // Practice1→P1, ShortPractice→P, Qualifying3→Q3, ShortQualifying→Q, OneShotQualifying→OSQ, SprintShootout2→SQ2,
                                                   // ShortSprintShootout→SQ, OneShotSprintShootout→OSSQ, Race→R, Race2→R2, Race3→R3, TimeTrial→TT, Unknown→'-', 'Weird'→'-'
test('resultStatusLabel', ...);                    // DidNotFinish→DNF, Disqualified→DSQ, NotClassified→NC, Retired→RET, Unknown→'-', Finished→'', Active→''
test('formatRaceTime_HourBoundary', ...);          // 3599999 → '59:59.999', 3600000 → '1:00:00.000', 83456 → '1:23.456'
test('formatGapMs_MinuteBoundary', ...);           // 16235 → '+16.235', 59999 → '+59.999', 75123 → '+1:15.123', -5 → '+0.000'
test('referenceRow_SkipsNotRunningLeader', ...);   // P1 DNF, P2 Finished → P2; 전원 DNF → null
test('timeOrGap_Race_Leader_ShowsTotalIncludingPenalties', ...); // total 1598765 + pen 5000 → '26:43.765'
test('timeOrGap_Race_SameLap', ...);               // 기준 1598765(+0), 행 1610000(+5000) → '+16.235'
test('timeOrGap_Race_Lapped', ...);                // 기준 15랩, 행 14랩 → '+1 Lap', 13랩 → '+2 Laps'
test('timeOrGap_Race_NotRunning_ShowsStatus', ...);// DidNotFinish → 'DNF'
test('timeOrGap_Race_NullTotal_ShowsDash', ...);   // 행 또는 기준 totalRaceTimeMs null(같은 랩) → '-'
test('timeOrGap_Race_NoReference', ...);           // 기준 null → Finished '-', DNF 'DNF'
test('timeOrGap_Qualifying', ...);                 // 기준(가장 빠른 행, P1이 아니어도) best 81234 → '1:21.234', 행 81500 → '+0.266', 행 best null & Finished → '-', & Retired → 'RET'
test('timeOrGap_Qualifying_NoTimes', ...);         // 모든 행 best null → Finished '-', DidNotFinish 'DNF'
test('penaltyLabel', ...);                         // (0, 0) → '-', (2, 5000) → '+5s (2)', (1, 0) → '(1)'
test('parseHexColor', ...);                        // '#FF8000' → Color(0xFFFF8000), null·'red'·'#FFF' → fallback
```

- [ ] **Step 2: 모델·저장소·화면·라우터 테스트 작성**

```dart
// session_models_test: 스펙 §7.2 예시 JSON fromJson, my* null, seasonId·round null, bestLapTimeMs null, tyreStints 빈 목록
// sessions_repository_test (기존 devices_repository_test 방식): getMySessions(sessionType: 'Race', page: 2) → GET /me/sessions?sessionType=Race&page=2&pageSize=15
// sessions_page_test (Fake 저장소 override)
testWidgets('SessionsPage_Empty_ShowsGuide', ...);             // '결과 화면까지 마친 세션이 여기에 기록됩니다.' + Telemetry App 링크
testWidgets('SessionsPage_FilteredEmpty_ShowsNoMatch', ...);   // filter race, total 0 → '이 조건에 맞는 세션이 없습니다.'
testWidgets('SessionsPage_ShowsRowsAndPagination', ...);       // 'Showing 1 to 15 of 16', 행에 'R'·트랙명·'P4 / 22'
testWidgets('SessionsPage_FilterChip_RequestsSessionType_AndResetsPage', ...); // 2페이지에서 Race 칩 → 호출 (sessionType 'Race', page 1), URL ?type=race
testWidgets('SessionsPage_UnknownTypeQuery_FallsBackToAll', ...);
testWidgets('SessionsPage_PlayerAbsent_ShowsDash', ...);
testWidgets('SessionsPage_NarrowScreen_DoesNotOverflow', ...); // 400px
// session_detail_page_test
testWidgets('SessionDetail_ShowsResultsInOrder_WithAiBadgeAndMyRowHighlight', ...);
testWidgets('SessionDetail_Narrow_HidesGridTyresPitsPen', ...); // 콘텐츠 폭 500 → 'Grid' 헤더 없음, 900 → 있음, 넘침 없음
testWidgets('SessionDetail_FastestLap_UsesFastestColor', ...);
testWidgets('SessionDetail_NotFound_ShowsNotFoundState', ...);  // ApiException(statusCode: 404) → '찾을 수 없는 세션입니다.' + Sessions 링크, 다시 시도 없음
testWidgets('SessionDetail_LoadFails_RetryReloads', ...);
// laps_page_test: 트랙별 랩 표가 공용 PaginationBar로 다음 페이지를 연다(기존 기대값 유지)
// app_router_test: '/sessions'·'/sessions/abc'가 각 화면을 연다. app_shell_test: 메뉴 순서 Dashboard·Sessions·Laps·Leaderboard·Telemetry App, '/sessions/abc'에서 Sessions 선택
```

- [ ] **Step 3: 실패 확인** — `cd app; flutter test` → 컴파일 실패.
- [ ] **Step 4: 구현** — 기존 `features/laps`와 같은 계층·이름 규칙. 필터는 GoRouter 쿼리 `type`에서 읽고 바꿀 때 `Router.neglect(context, () => context.go('/sessions?type=$value'))`; 페이지는 `ConsumerStatefulWidget` 상태(필터가 바뀌면 1로). 세션 결과 표는 `LayoutBuilder` 폭 < `kSessionTableCompactWidth`에서 열을 숨기고 가로 스크롤로 감싼다. 시즌 `R{n}` 링크는 Task 9에서 활성화한다(이 태스크에서는 텍스트만).
- [ ] **Step 5: 통과 확인** — `flutter analyze` 이슈 0, `flutter test` PASS. 수동: `flutter run -d web-server --web-hostname localhost --web-port 5960 --dart-define=API_BASE_URL=http://localhost:5284`로 1000px·500px 폭 확인.
- [ ] **Step 6: 커밋** — `feat(app): Sessions 목록과 세션 결과 화면 추가, 페이지 바 공용화(P7)`

---

### Task 9: Flutter Seasons (목록 · 시즌 상세 3탭)

**Files:**
- Create: `app/lib/features/seasons/domain/season_models.dart`, `data/seasons_repository.dart`, `application/seasons_providers.dart`
- Create: `app/lib/features/seasons/presentation/seasons_page.dart`, `season_detail_page.dart`, `season_rounds_tab.dart`, `season_results_tab.dart`, `season_standings_tab.dart`
- Modify: `app/lib/core/router/app_router.dart`(`/seasons`, `/seasons/:seasonId`), `app/lib/core/shell/nav_items.dart`(Seasons를 Dashboard 다음에), `app/lib/features/sessions/presentation/session_detail_page.dart`(`R{n}` → `/seasons/{seasonId}?tab=season` 링크)
- Test: `app/test/season_models_test.dart`, `app/test/seasons_page_test.dart`, `app/test/season_detail_page_test.dart`; Modify: `app/test/app_router_test.dart`, `app/test/app_shell_test.dart`, `app/test/support/fakes.dart`

**Interfaces:**
- Consumes: Task 8 `session_display.dart`, `PaginationBar`, `parseHexColor`, `NotFoundState`, `AppColors` 토큰, 스펙 §7.2 JSON.
- Produces:
  - 모델(`fromJson`): `SeasonSummary`, `SeasonsPage`, `SeasonDetail(season, rounds, standings)`, `SeasonRound`, `SeasonRoundSession`, `SeasonStandings`, `DriverStanding`(+ `cells`), `StandingCell`, `ConstructorStanding`.
  - `SeasonsRepository { Future<SeasonsPage> getMySeasons({int page = 1, int pageSize = kSeasonsPageSize}); Future<SeasonDetail> getMySeason(String seasonId); }`, `kSeasonsPageSize = 20`
  - `seasonsProvider` = `FutureProvider.autoDispose.family<SeasonsPage, int /*page*/>`, `seasonDetailProvider` = `FutureProvider.autoDispose.family<SeasonDetail, String>`
  - `String seasonTitle(SeasonSummary s)` = `'${gameModeLabel(s.gameMode)} · ${yyyy.MM.dd(firstSessionAt 로컬)}'`
  - 탭 값 `season|results|standings`(기본·모르는 값 → `season`). 상수 `kResultsRowHeight = 40`, `kResultsNameColumnWidth = 180`.

- [ ] **Step 1: 테스트 작성**

```dart
// season_models_test: SeasonSummary(my*·leader* null 포함), SeasonDetail(rounds·standings.drivers.cells·constructors) fromJson, cell.position null
test('seasonTitle_UsesModeLabelAndStartDate', ...);           // DriverCareer, 2026-10-17 → 'Driver Career · 2026.10.17'
// seasons_page_test
testWidgets('SeasonsPage_Empty_ShowsGuide', ...);             // '커리어나 그랑프리 모드에서 세션을 결과 화면까지 마치면 시즌이 기록됩니다.' + Telemetry App 링크
testWidgets('SeasonsPage_ShowsCardWithMyStandingAndLeader', ...); // 'P3 · 87 pts', 'VERSTAPPEN 120', '6 rounds'
testWidgets('SeasonsPage_PlayerAbsent_ShowsDash', ...);
testWidgets('SeasonsPage_Paginates', ...);                    // total 25 → 다음 페이지 호출 page 2
// season_detail_page_test
testWidgets('SeasonDetail_DefaultTab_IsSeason_ShowsRoundsAndSessionChips', ...); // 'R1 · Bahrain', 우승자, 칩 'Q1'·'R' + 내 순위, 칩 탭 → '/sessions/{id}'
testWidgets('SeasonDetail_TabQuery_SelectsResults', ...);     // ?tab=results → 헤더 'R1' 'R2', 내 행 강조, DNF 칸 'DNF', 기록 없는 칸 '-'
testWidgets('SeasonDetail_Results_NameColumnStaysFixed_NoOverflowWhenNarrow', ...); // 400px, 가로 스크롤 후에도 이름 보임
testWidgets('SeasonDetail_StandingsTab_ShowsDriversConstructorsAndNote', ...); // '기록된 세션 기준입니다. 라운드 번호는 기록된 주말 순서라 게임과 다를 수 있습니다.'
testWidgets('SeasonDetail_UnknownTab_FallsBackToSeason', ...);
testWidgets('SeasonDetail_NotFound_ShowsNotFoundState', ...); // '찾을 수 없는 시즌입니다.' + Seasons 링크
// app_router_test: '/seasons', '/seasons/abc?tab=standings'. app_shell_test: 메뉴 순서 Dashboard·Seasons·Sessions·Laps·Leaderboard·Telemetry App, '/seasons/abc'에서 Seasons 선택
// session_detail_page_test (추가): 시즌 세션이면 'R7' 탭 → '/seasons/{seasonId}?tab=season'
```

- [ ] **Step 2: 실패 확인** — `flutter test` → 컴파일 실패.
- [ ] **Step 3: 구현** — 탭은 `TabBar` + 쿼리 동기화(`Router.neglect(context, () => context.go('/seasons/$id?tab=…'))`). 결과표는 이름 열(`SizedBox(width: kResultsNameColumnWidth)` 안의 `Column`)과 가로 `SingleChildScrollView` 안의 본문 `Column`을 `kResultsRowHeight`로 맞춘다(새 패키지 없음). 칸 색: 1·2·3위 `podiumGold/Silver/Bronze`, 상태 칸 `textMuted`. 팀 색은 `parseHexColor(…, fallback: AppColors.textMuted)`.
- [ ] **Step 4: 통과 확인** — `flutter analyze` 0, `flutter test` PASS. 수동: 1000px·500px 폭에서 3탭 확인.
- [ ] **Step 5: 커밋** — `feat(app): Seasons 목록과 Season·Results·Standings 탭 추가(P7)`

---

### Task 10: 문서 · 헌장 갱신 + 전체 확인

**Files:**
- Modify: `CLAUDE.md`, `docs/08-open-decisions.md`, `docs/11-personal-mode.md`, `docs/02-domain-design.md`, `docs/03-entity-design.md`, `docs/04-api-design.md`, `docs/05-signalr-design.md`, `docs/06-telemetry-design.md`, `docs/PROGRESS.md`, `docs/TESTING-local-e2e.md`, `docs/12-seasons-sessions.md`(Status → Implemented, 구현 중 달라진 점)

- [ ] **Step 1: 헌장** — Agent Rules의 이벤트 목록에 `SessionClassified`(세션당 최종 순위표 1건) 추가, Confirmed Decisions에 "시즌 묶음 = 게임 링크 식별자(시즌 대상 모드, D-29), Standings = 기록된 세션 점수 합·본 레이스 카운트백(D-31)" 한 줄. Last Updated 날짜.
- [ ] **Step 2: 결정 기록** — docs/08에 "I. Phase 7 시즌·세션 결정"으로 D-28~D-34(스펙 §2 요약 + 대안), 요약표에 7행 추가. docs/11 §0 P7 행에 `[12](./12-seasons-sessions.md)` 링크.
- [ ] **Step 3: 설계 문서 동기화** — 02(시즌 계층), 03(엔티티 5종 + `laps.session_key`, 필터 unique index 규칙), 04(API 4개), 05(허브 이벤트 유형 `SessionClassified`, `MaxMessageBytes` 64KiB), 06(파싱 패킷에 Participants(4)·Final Classification(8) 추가, `LapFinished` 맥락 필드, Agent 크기 검사).
- [ ] **Step 4: 진행·테스트 가이드** — PROGRESS.md에 P7 항목. TESTING-local-e2e.md에 "게임으로 확인" 절차: 커리어에서 예선·레이스를 결과 화면까지 진행 → Agent 로그에서 `SessionClassified` 1건 → `/seasons`·`/sessions` 확인, 그리고 스펙 §3.3 가정 7개 체크리스트(확인 결과는 docs/12 §3.3에 적는다).
- [ ] **Step 5: 전체 확인** — `dotnet test backend/SimCenter.sln --nologo`, `dotnet test agent/SimCenter.Agent.sln --nologo`, `cd app; flutter analyze; flutter test` → 모두 PASS·이슈 0.
- [ ] **Step 6: 커밋** — `docs: P7 시즌·세션 결정(D-28~34)과 설계 문서 갱신`
