# PROGRESS — 진행 상황 / 인수인계

> Last Updated: 2026-10-18
> **이 문서 목적:** 다른 PC·다른 세션에서도 작업을 그대로 이어가기 위한 단일 상태 파일.
> 새 세션은 이 파일 → `CLAUDE.md` → `docs/00~14` 순으로 읽으면 맥락이 복원된다.
> (주의: AI 메모리는 머신 로컬(`~/.claude`)이라 이동하지 않는다. **진행 상태의 진실 원천은 이 문서**다.)

---

## 1. 한 줄 상태

**실제 게임 연동 버그 수정(D-41) — F1 25로 랩을 돌아도 기록이 저장되지 않던 문제. F1Game.UDP 26.0.0은 2026 시즌팩 레이아웃(24대)이라 실제 게임(F1 25 v1.26, 22대)의
Session·LapData를 모두 "바이트 부족"으로 버렸다 → 25.1.1로 교체, 해석 실패 경고 로그, 실제 패킷 회귀 테스트(`F1WireLayoutTests`). 캡처 재생으로 Tray → 허브 수신까지 확인,
랩 저장(LapFinished)은 게임으로 한 랩 더 돌아 확인해야 한다. 테스트: Agent 246(Core 41 + Infrastructure 205) 통과.**

(이전) **프로필·계정 설정(Edit Profile) 완료 — 사이드바 하단 프로필(팀 색 사진 + 이름 + "계정 설정")을 누르면 `/settings`가 열린다. 이메일·닉네임 변경, 랭킹 이름 공개 설정
(끄면 랭킹에 "익명 드라이버"), 게임·컨트롤러·플랫폼·단위·타임존·테마, 프로필 사진(팀 색 원), 저장/취소, 로그아웃. 밝은 테마 추가 — 기본 테마는 Dark(D-40), System을 고르면 기기 밝기.
설계·결정: [14](./14-profile-settings.md), D-39·D-40(리뷰 반영 포함). 테스트: Backend 451(Domain 55 + Application 344 + 통합 52) · App 364 전부 통과, `flutter analyze` 이슈 0, 빌드 경고 0. Agent 변경 없음.
마이그레이션 `AddUserProfileSettings`·`DefaultThemeDark`는 백엔드 재시작 시 개발 DB에 적용된다. 브라우저 육안 확인(밝은 테마 포함)은 아직이다. 다음 = P8 세션 상세.**

(이전) **Phase 7(시즌·세션 결과 수집) 완료 — Agent가 세션 끝의 최종 순위표를 Participants와 합쳐 `SessionClassified` 1건으로 보내고, 백엔드가
게임 링크 식별자로 시즌 → 그랑프리 주말 → 세션 → 드라이버별 결과(AI 포함)를 저장한다. 앱은 Seasons(Season · Results · Standings 탭)·Sessions 화면을 갖는다.
테스트: Backend 363(Domain 49 + Application 278 + 통합 36) · Agent 189(Core 41 + Infrastructure 148) · App 303 전부 통과, `flutter analyze` 이슈 0,
빌드 경고 0. **게임으로 확인한 것은 아직 없다** — [12](./12-seasons-sessions.md) §3.3의 가정 8개와 실제 Final Classification 수신은 F1 25로 확인해야 한다
([TESTING-local-e2e.md](./TESTING-local-e2e.md) §10). 다음 = P8 세션 상세.**

(이전) Phase 6(개인 모드 전환 + 웹 셸) 완료 — 카페 모델(매장·좌석·체크인)을 개인 모델로 전환. 웹에서 1회용 연결 코드를 받아
Agent가 `pair`(장치별 키, DPAPI 저장)로 내 계정에 연결하고, 랩은 장치 주인에게 귀속된다. 앱은 사이드바 셸
(Dashboard · Laps · Leaderboard · Telemetry App). 테스트: Backend 95(Domain 3 + Application 76 + 통합 16) ·
Agent 95(Core 19 + Infrastructure 76) · App 127 전부 통과, `flutter analyze` 이슈 0, 빌드 경고 0
(NuGet 취약성 권고 NU1902/NU1903도 해소 — SignalR.Client·Data.Sqlite 10.0.13, Cryptography.Xml/Pkcs 10.0.13 고정).
헤드리스 통합 확인(가입→코드 발급→`pair`→허브 연결→장치 목록→해제→Agent 401 중단) 통과, 랩 단계만 F1 25 없어 보류.

(이전) Phase 5(Flutter MVP 앱) 완료 — MVP 스코프 달성. 앱: Splash→Login→Home→Today's Ranking(실시간)
→My Lap Record 풀 라우팅, Riverpod+GoRouter+dio(REST)+signalr_netcore(RankingHub 구독/재동기화).
`flutter analyze` 이슈 0 · `flutter test` 6/6 통과. 백엔드는 개발용 CORS·SignalR 쿼리토큰 지원 추가
(빌드 경고0/테스트 54 유지). 남은 이월분 = Agent 자동실행 + 실 F1 라이브 검증(§4-B).

(이전) Phase 4(랭킹 계산 REST + RankingHub 브로드캐스트) 완료 — 백엔드 빌드 경고0/테스트 54
(Domain 3 + Application 49 + E2E 2), 실 PostgreSQL에서 마이그레이션(`AddStoreTimeZone`)·시더 백필·
`/rankings`·`/me/laps` E2E 통과.

(이전) Phase 3(실시간 인입: Agent Outbox+SignalR → TelemetryHub → DB) 완료 — E2E 통합테스트
(회원가입→로그인→체크인→Hub→DB Lap 귀속)를 실 PostgreSQL에서 통과.

(이전) Phase 2 + Tray GUI(연결 상태 신호등) 완료 — Cli/Tray UDP 20777 바인딩 + 수신 스모크, Tray 실행 확인.

(이전) Phase 1(Backend 데이터/인증 코어) 완료 — 실 PostgreSQL 마이그레이션+시드+register/login/me E2E 검증.

---

## 2. 리포지토리 현재 상태

- 위치(개발 PC 기준): `D:\Project\SimHub` (경로는 환경마다 다를 수 있음)
- 형상: **Phase 0~7 완료.** 계약 스펙 + 3개 솔루션이 구현됨. 빌드·테스트 통과 확인. (브랜치 `feat/p6-personal-mode`에서 P6, `feat/p7-seasons-sessions`에서 P7 작업 — 머지 여부는 git으로 확인)
  ```
  CLAUDE.md                        # 프로젝트 헌장(압축본)
  docs/00~14 + PROGRESS.md + TESTING-local-e2e.md   # 설계 문서 + 진행 상황 + 로컬 E2E 가이드
  global.json                      # .NET 10 SDK 버전 고정
  shared/                          # 계약(Contract) — OpenAPI, JSON Schema, Telemetry Spec, Samples
  backend/                         # ASP.NET Core 10 Clean Architecture (빌드 ✅)
  agent/                           # .NET 10 Agent — WPF Tray + Core + Infrastructure (빌드 ✅)
  app/                             # Flutter Feature-First (pub get ✅)
  ```
- Git: 초기화 완료. `main` 브랜치.

---

## 3. 완료된 작업 ✅

1. **전체 설계 문서 세트 작성** (`docs/`)
   | 문서 | 내용 |
   |---|---|
   | `00-overview.md` | Monorepo 구조 · 프로젝트 역할 · Dependency 방향 |
   | `01-architecture.md` | Backend(Clean Arch)/Agent/App Solution·폴더 구조·레이어 규칙 |
   | `02-domain-design.md` | Bounded Context 지도 + MVP 도메인 |
   | `03-entity-design.md` | ERD · Entity · PK/공통규약 · 인덱스 |
   | `04-api-design.md` | MVP REST API · DTO · 인증 · 에러 규약 |
   | `05-signalr-design.md` | SignalR 2-Hub 이벤트 계약 |
   | `06-telemetry-design.md` | F1 25 UDP 파이프라인 · Lap/Sector 판정 · Outbox |
   | `07-roadmap.md` | Phase 0~5 MVP + Future |
   | `08-open-decisions.md` | 결정 근거 + 전체 확정 요약표 |
   | `09-lap-telemetry-trace.md` | 상세 텔레메트리 조회(Future 설계) |
   | `10-realtime-ingest.md` | P3 실시간 인입 As-Built (P6 반영) |
   | `11-personal-mode.md` | P6 개인 모드 전환 + 웹 셸 설계·구현 기록 |
   | `12-seasons-sessions.md` | P7 시즌·세션 결과 수집 설계·구현 기록 (D-28~34, 구현 중 달라진 점 §14) |
   | `13-outbox-dead-letter.md` | Agent Outbox 독성 항목 미루기 + dead-letter (D-35~38) |
   | `14-profile-settings.md` | 프로필·계정 설정(Edit Profile)·랭킹 이름 비공개·밝은 테마 (D-39·D-40) |
   | `TESTING-local-e2e.md` | 로컬 E2E 가이드 (웹 가입 → 코드 발급 → `pair` → 주행 확인 → §10 시즌·세션 게임 확인) |
2. **핵심 결정 D-1~D-16 + D-8a 전부 확정** (§5 참조), 각 문서 반영 완료. (P6에서 D-1·D-2·D-10·D-12·D-21·D-22는 D-25로 대체)
3. **사용자 최종 승인 완료** (설계 세트 approve).
4. **`CLAUDE.md` 압축 재작성** (646줄 → 71줄, 상세는 docs로 위임).
5. **Phase 0 — 계약 & 스캐폴딩 완료:**
   - `shared/openapi/openapi.yaml` — REST API OpenAPI 3.0 명세 (04 기반)
   - `shared/schema/*.json` — SignalR/Telemetry 이벤트 페이로드 9종 JSON Schema
   - `shared/telemetry/f1_25_udp_spec.md` — F1 25 UDP 패킷 오프셋 문서
   - `shared/samples/` — LapFinished Envelope, RankingUpdated 샘플 JSON
   - `backend/SimCenter.sln` — 4 src + 3 tests 프로젝트, 참조 관계 설정, **빌드 성공 (0 경고, 0 오류)**
   - `agent/SimCenter.Agent.sln` — 3 src(Core/Infrastructure/WPF Tray) + 1 tests, **빌드 성공 (0 경고, 0 오류)**
   - `app/` — Flutter Feature-First 구조, Riverpod/GoRouter/Dio/SignalR 의존성 설정 완료
6. **Phase 1 — Backend 데이터/인증 코어 (완료: 빌드·단위테스트·실 DB E2E 검증):**
   - **Domain:** `BaseEntity`, 열거형(`SessionType`/`SessionStatus`), 7개 엔티티
     (User/Store/SimRig/Track/DrivingSession/Lap/LapSector), `GameCodes` 상수. 프레임워크 무의존.
   - **Application:** 포트(`IIdGenerator`/`IPasswordHasher`/`IJwtTokenGenerator`/`IUserRepository`/`IUnitOfWork`),
     예외(Validation/Conflict/NotFound/Authentication), `AuthService`(register/login/me), `AddApplication()`.
   - **Infrastructure:** `AppDbContext`(소프트삭제 전역필터 + UTC 컨버터 + snake_case), 엔티티별 Configuration
     (User Email uq, SimRig RigCode uq, Track (GameCode,GameTrackId) uq, DrivingSession **부분 유니크 `status='Active'`**,
     Lap 랭킹 인덱스 3종, LapSector (LapId,SectorNumber) uq), `UserRepository`, `DbSeeder`(Store1/Rig4/F1트랙27),
     `BCryptPasswordHasher`, `JwtTokenGenerator`(HS256), `SystemClock`, `UuidV7Generator`, `AddInfrastructure()`,
     `DesignTimeDbContextFactory`, **`InitialCreate` 마이그레이션 생성**.
   - **Api:** `Program.cs`(Serilog + Swagger(JWT) + 인증/인가 + 예외미들웨어 + 시작 시 Migrate&Seed),
     `AuthController`(POST auth/register·auth/login, GET me), `ExceptionHandlingMiddleware`(RFC7807),
     appsettings(Jwt/ConnectionStrings 구조), UserSecretsId.
   - **Tests:** Domain 3 + Application(AuthService) 13 통과. `dotnet build` 경고 0/오류 0.
   - **로컬 도구:** `dotnet-ef` 9.0.0 로컬 도구(`.config/dotnet-tools.json`) 설치.
7. **Phase 2 — Telemetry Agent (Core + UDP 수신) (완료: 빌드·단위테스트·Cli 스모크):**
   - **Agent.Core (라이브러리 무의존, 순수):** `IClock`/`IIdGenerator`, 게임중립 프레임(`SessionFrame`/`LapFrame`/
     `EventMarker`, `ITelemetryFrame`), 이벤트 모델(SessionStarted/LapStarted/SectorCompleted/LapFinished/SessionEnded
     + `TelemetryEnvelope`/`AgentIdentity`), **`LapAnalyzer`**(엣지 트리거 상태머신, 3섹터 분해·유효성·아웃인랩), `DomainEventFactory`.
   - **Agent.Infrastructure:** **F1Game.UDP 26.0.0** 참조. `F1PacketMapper`(UnionPacket→게임중립 프레임, PlayerCarIndex,
     세션타입 정규화, 섹터 분+ms 합산, `m_packetFormat` 검증), `UdpTelemetryListener`(UdpClient 수신 루프),
     `TelemetryPipeline`(수신→매핑→분석→봉투→싱크), `ITelemetrySink`+`LoggingTelemetrySink`, `SystemClock`/`UuidV7Generator`,
     `AgentOptions`, `AddAgentInfrastructure()`.
   - **Agent.Cli (신규 프로젝트):** Generic Host + `TelemetryWorker`(BackgroundService) + Serilog 콘솔 + appsettings. `sln` 추가.
   - **Tests:** Core 11(LapAnalyzer/Factory) + 신규 Infrastructure 17(매퍼/리스너) = **28 통과**, 경고 0.
   - **검증:** Cli 실행 → UDP 20777 바인딩 로그 확인, 임의 데이터그램 수신 시 무크래시(매퍼 예외 흡수).
   - **contract:** `shared/schema/lap_finished.json`에 `sessionType` 추가(코드/docs/06 일치화).
   - **미구현(P3):** 서버 전송·Outbox(SQLite)·SignalR·재접속·자동실행. `ITelemetrySink`가 교체 지점. (Tray 호스트/트레이아이콘 = item 8에서 완료)
   - **참고:** F1 `Track` enum 확인 결과 7=Silverstone, 2=Shanghai → 백엔드 시드가 옳았음(스펙 문서 예시가 오기).
8. **Phase 2.5 — Tray GUI(게임 연결 상태 표시) (완료: 빌드·단위테스트·실행 확인):**
   - **Agent.Core.Connection (순수, IClock 기반):** `ConnectionState`(🔴/🟡/🟢), `ConnectionSnapshot`,
     `ConnectionThresholds`(Connected 2s/Waiting 6s), **`GameConnectionMonitor`**(lock 스레드안전 — UDP 스레드가 통지, GUI 스레드가 폴링).
   - **Agent.Infrastructure:** `TelemetryHostedService`(Cli·Tray 공유 BackgroundService, 리스너 실패→모니터 통지),
     `TelemetryPipeline`이 데이터그램마다 `RecordDatagram`(앞 2바이트 = m_packetFormat) 통지. Cli는 `TelemetryWorker`→`TelemetryHostedService`로 교체.
   - **Agent.Tray:** WPF+WinForms(`NotifyIcon` 신호등 아이콘/툴팁, 트레이 메뉴 열기·종료), Generic Host 조립(Cli와 동일 파이프라인),
     `MainWindow`가 500ms `DispatcherTimer`로 `GetSnapshot()` 폴링 → 상태·포트·수신수·마지막 수신·감지 포맷·오류 표시. 닫기=트레이 최소화.
   - **Tests:** Core에 `GameConnectionMonitorTests` 8종 추가(상태 전이/임계값/리스너 실패). 총 **36 통과**(Core 19 + Infra 17), 경고 0.
   - **검증:** 솔루션 빌드 0오류, Tray 실행 확인. (실제 F1 연결 라이브 검증은 §4-B, 하드웨어 의존 보류)
   - **미구현:** 연결 상태는 "패킷 도착"만 판정(파싱 성공 무관) — 포맷 불일치는 "감지 포맷" 필드로 노출. 랩 이벤트는 GUI 미표시(로그 싱크, Cli 콘솔로 관찰).
9. **Phase 3 — 실시간 인입 (완료: 빌드·단위테스트·실 DB E2E):** 상세 [docs/10](./10-realtime-ingest.md). 결정 D-21~23.
   - **Backend Application:** `SessionService`(체크인/아웃/활성, D-10 자동종료·타인점유 409),
     `TelemetryIngestService`(멱등→세션매칭→Track매핑→랭킹적격→Lap+LapSector 저장), 포트
     (`ISimRigRepository`/`IDrivingSessionRepository`/`ITrackRepository`/`ILapRepository`/`IProcessedEventRepository`/`IApiKeyHasher`),
     Telemetry DTO(camelCase 계약), `ForbiddenException`(403).
   - **Backend Infrastructure:** 리포지토리 구현 6종, `Sha256ApiKeyHasher`, `AgentApiKeyAuthenticationHandler`(스킴 `AgentApiKey`),
     `ProcessedEvent`/`SimRig.ApiKeyHash` Configuration, **마이그레이션 `AddTelemetryIngest`**, 시더 좌석별 dev 키 프로비저닝.
   - **Backend Api:** `SessionsController`(check-in/check-out/active), `Hubs/TelemetryHub`(`SubmitEvent`→반환값 Ack, `[Authorize(AgentApiKey)]`),
     `Program.cs` SignalR(camelCase+enum문자열)·`MapHub("/hubs/telemetry")`.
   - **Agent:** `ITelemetrySink`를 **`OutboxTelemetrySink`(SQLite Outbox 적재)** 로 교체, `TelemetryUploadService`
     (HubConnection 자동재접속 + 지수백오프 배수, 응답 시 삭제·무응답만 재전송), `AgentOptions`에 BackendUrl/AgentCredential/OutboxPath.
   - **Tests:** Backend Application +22(Session 13/Ingest 9) = 35, **E2E 통합 1**(실 PostgreSQL, 재실행 가능). Agent +4(Outbox/직렬화) = Infra 21. 경고 0.
   - **정련(D-23):** Hub를 요청/응답(반환값 Ack)로 구현 — 05의 별도 Ack/Reject S→C 메서드 대신(상관관계 단순).
   - **미구현(P4):** RankingHub 브로드캐스트·랭킹 재계산·랭킹 REST·PB 알림. 실 F1 라이브 검증(§4-B).
10. **Phase 4 — 랭킹 계산 + RankingHub 브로드캐스트 (완료: 빌드·단위테스트·실 DB E2E):** 결정 D-24.
   - **Domain:** `Store.TimeZoneId`(IANA) 추가.
   - **Application(`Rankings/`):** `RankingPeriod` enum, **`RankingPeriodRange`**(순수 — 매장 로컬 자정 경계→UTC, periodKey),
     `RankingDtos`(Snapshot/Entry/Track/MyLaps/PagedResult 등), `IRankingService`/`RankingService`(랭킹 TOP10·트랙목록·내 랩+PB),
     `IRankingNotifier` 포트 + payload(LapRecorded/PersonalBest, RankingUpdated=Snapshot 재사용). 포트 확장
     (`ILapRepository`: GetRanking/GetMyLaps/GetPersonalBestLap, `ITrackRepository`: GetById/GetAll, 신규 `IStoreRepository`).
   - **Application(Ingest 통합):** `TelemetryIngestService`가 커밋 전 PB 판정, 커밋 후 best-effort 브로드캐스트
     (유효→LapRecorded, PB→PersonalBest, 적격→월별 TOP10 재조회→RankingUpdated). 실패해도 Ack 유지.
   - **Infrastructure:** `StoreConfiguration` TimeZoneId, `StoreRepository` 신규, `TrackRepository`/`LapRepository` 쿼리 확장
     (랭킹 = 유저별 최고 상위N, 내 랩 페이지+Track/Sectors, PB), `DbSeeder` `Asia/Seoul` 백필, DI 등록,
     **마이그레이션 `AddStoreTimeZone`**(기존 행 기본값 `""`).
   - **Api:** `RankingHub`(`[Authorize]` JWT, OnConnected→user 그룹, Subscribe/UnsubscribeTrack), `RankingNotifier`(`IHubContext`),
     `RankingsController`(`GET /rankings`), `TracksController`(`GET /tracks`), `MeController`(`GET /me/laps`),
     `Program.cs` 등록·`MapHub("/hubs/ranking")`.
   - **Tests:** Application +14(RankingPeriodRange 4/RankingService 6/Ingest 브로드캐스트 4) = 49, E2E +랭킹·내랩 조회 확장. 경고 0.
   - **미구현(P5):** Flutter 앱 소비. 잔여(이월): Agent 자동실행. 실 F1 라이브 검증(§4-B).
11. **Phase 5 — Flutter MVP 앱 (완료: analyze 이슈0·test 6/6·백엔드 회귀0):** 로드맵 07 기준. **MVP 스코프 달성.**
   - **App core(`lib/core/`):** `config/app_config.dart`(baseUrl/Hub URL), `network/`(`dio_provider` JWT 인터셉터·401 이벤트,
     `api_exception`(RFC7807 파싱), `auth_events`), `storage/token_store`(SharedPreferences 토큰 보관),
     `router/app_router`(GoRouter + 인증 리다이렉트 가드 + `_RouterNotifier` refreshListenable), `theme/app_theme`(Material3),
     `realtime/ranking_hub_client`(signalr_netcore 자동재접속 + `SubscribeTrack` 재구독 + `RankingUpdated`/`LapRecorded`/`PersonalBestAchieved` 수신),
     `util/lap_time`(ms→m:ss.mmm 포맷, 음수 플레이스홀더).
   - **App features(Feature-First 4피처 × domain/data/application/presentation):**
     `auth`(LoginResult 모델·AuthRepository·AuthController(세션복원/login/logout)·Splash/Login 화면),
     `session`(체크인/아웃 SessionController·SessionRepository),
     `ranking`(RankingSnapshot/Entry·Track 모델·RankingRepository·Home(트랙목록)·TodayRanking(실시간 TOP10) 화면·providers),
     `laps`(MyLaps/Lap/LapSector 모델(personalBest null 허용)·LapsRepository(`/me/laps`)·MyLaps 화면·providers).
   - **Backend 앱 지원(회귀 없음):** 개발환경 한정 CORS(루프백 오리진만 반사, 운영 미개방), 개발 시 `UseHttpsRedirection` 생략(에뮬레이터/웹 cleartext),
     `JwtBearerEvents.OnMessageReceived`로 `/hubs/ranking` 경로에 한해 `access_token` 쿼리 토큰 채택(WebSocket JWT 표준, REST는 헤더만).
   - **Android:** `INTERNET` 권한(main 매니페스트), `network_security_config.xml`(기본 cleartext 차단 + `10.0.2.2`/`localhost`/`127.0.0.1`만 개발 허용).
   - **Tests:** `models_test`(LoginResult/RankingSnapshot/MyLaps/Track fromJson 4) + `widget_test`(formatLapTime 2) = **6 통과**, `flutter analyze` 이슈 0.
   - **미구현(이월):** Agent 자동실행(Windows 시작 등록). 실 F1 라이브 검증(§4-B). (체크인 UI 정련은 P6에서 체크인 자체가 제거되어 불필요해졌다.)
12. **Phase 6 — 개인 모드 전환 + 웹 셸 (완료: Backend 95 · Agent 94 · App 127 통과, analyze 이슈 0, 헤드리스 통합 확인):** 설계 [docs/11](./11-personal-mode.md), 결정 D-25~27.
    위 3~11번의 `Store`/`SimRig`/`DrivingSession`/체크인/좌석 키 서술은 당시 카페 모델 기록이며 P6에서 대체됐다.
   - **Backend:**
     - Domain: `AgentDevice`(소유자·이름·`ApiKeyHash`·`LastSeenAt`, 해제 = soft delete)·`AgentPairingCode`(해시·만료·`ConsumedAt`) 추가,
       `Lap`에 `AgentDeviceId`·`UserId` FK, `Store`/`SimRig`/`DrivingSession`/`SessionStatus`와 관련 저장소·서비스·`SessionsController`·좌석 시드 제거.
     - Application(`AgentDevices/`): `AgentPairingService`(코드 8자·`XXXX-XXXX`·10분·이전 미사용 코드 무효화, 연결 시 정규화·원자적 소비·장치 생성·키 1회 반환),
       `AgentDeviceService`(목록·해제, 남의 장치 403/없는 장치 404), `/me/tracks` 요약(`bestValidLapTimeMs`), `/me/laps?sort=recent|fastest`,
       랭킹 타임존 = `Ranking:TimeZoneId`(기본 `Asia/Seoul`, `ValidateOnStart`).
     - 인입: `AgentApiKey` 핸들러가 장치 키로 `AgentDevice`를 특정(클레임 `deviceId`·`sub`, 해제 장치는 401),
       `TelemetryIngestService`가 매 이벤트마다 장치 재확인(해제 시 Reject "연결이 해제된 장치입니다."), `LastSeenAt` 1분 제한 갱신, 활성 세션 없는 랩 Drop 규칙 삭제,
       envelope `rigCode` 삭제.
     - Api: `AgentPairingController`(`POST /agent/pair`, 익명·IP당 분당 10회), `MyAgentDevicesController`(`POST /me/agent-pairing-codes` 사용자당 분당 10회, `GET`·`DELETE /me/agent-devices`),
       `MeController`(`/me/tracks`, `/me/laps`). 내장 Rate Limiting 사용(새 패키지 없음).
     - **마이그레이션 2건:** `AddAgentDevices`(가산적) + `PersonalMode`(기존 랩·섹터·멱등 기록 삭제, 세션·좌석·매장 테이블 삭제). 설계는 1건이었으나 EF Core 9+가 태스크 사이의 pending model change를 거부해 나눴다.
   - **Agent:** `ServerBaseUrl`(기본 `http://localhost:5284`)이 `BackendUrl`/`RigCode`/`AgentCredential`을 대체. 장치 키는 `DpapiDeviceCredentialStore`가
     `%LOCALAPPDATA%\SimCenter\Agent\device.key`에 DPAPI(CurrentUser)로 저장(`System.Security.Cryptography.ProtectedData`).
     Cli `dotnet run -- pair <코드>`(`PairCommand`, 성공 0/실패 1), Tray "계정 연결" 영역(`미연결`/`연결됨 · PC 이름`/`다시 연결 필요`, 연결 끊기 = 로컬 키 삭제).
     `TelemetryUploadService`: 키 없으면 업로드 대기(수신·Outbox 적재 계속), 10초마다 키 파일 재확인, 401이면 재시도를 멈추고 Outbox 보존. envelope에서 `rigCode` 제거.
   - **App:** 사이드바 셸(≥900px 고정 220px, 미만 서랍) + 어두운 남색/인디고 테마. 경로 `/`(Dashboard), `/laps`·`/laps/tracks/:trackId`(Laps), `/leaderboard?trackId=`,
     `/telemetry-app`(연결 코드 발급·연결된 PC 목록/해제·Connection Status). `features/session`·체크인 카드·`/home`·`/rankings/:trackId` 제거.
     실행: `flutter run -d web-server --web-hostname localhost --web-port 5960 --dart-define=API_BASE_URL=http://localhost:5284`.
   - **계약·문서:** `shared/openapi/openapi.yaml`(세션 경로 제거, 신규 API), `shared/schema/telemetry_envelope.json`·samples에서 `rigCode` 제거,
     `CLAUDE.md`·`docs/00~08·10·11`·`TESTING-local-e2e.md` 개인 모드로 갱신.
   - **검증(헤드리스, 이 PC):** 백엔드(`--launch-profile http`) 기동 → 임시 사용자 가입·로그인 → 연결 코드 발급 → Cli `pair` 성공(종료 0, `device.key` 생성) →
     `GET /me/agent-devices`에 PC 이름·`lastSeenAt null` → Cli 실행 로그 `TelemetryHub 연결됨` → `DELETE /me/agent-devices/{id}` 204 →
     Agent 재시작 시 401 경고로 업로드 중단("다시 연결이 필요합니다") → 같은 코드 재사용 400, 잘못된 코드 연타 시 429. 끝난 뒤 `device.key` 삭제(PC 미연결 상태로 복원).
     **F1 25가 없어 랩 업로드 단계는 보류**(§4-B). Flutter 화면은 브라우저 육안 확인 대상.
13. **Phase 7 — 시즌·세션 결과 수집 (완료: Backend 363 · Agent 189 · App 303 통과, analyze 이슈 0, 빌드 경고 0):** 설계 [docs/12](./12-seasons-sessions.md), 결정 D-28~34, 구현 중 달라진 점 §14.
   - **Backend:**
     - Domain: enum 4종(`GameMode`·`SessionKind`·`ResultStatus`·`TyreCompound`), 엔티티 5종(`Season`·`RaceWeekend`·`GameSession`·`SessionResult`·`SessionResultTyreStint`),
       순수 규칙 `SeasonPolicy`·`SessionKeys`·`DriverKeys`, 재분류 병합 `GameSession.ReplaceResults`(carIndex 제자리 갱신 + soft delete, `Remove`·`Clear` 금지).
     - Application(`Seasons/Ingest`): `SessionClassificationIngestor`(파싱 → 검증 → Time Trial Ignored → 트랙 → 분류 시각 → 세션 찾기 → 늦은 결과 Ignored → 시즌·주말 업서트 → 세션 생성·병합),
       `SessionClassificationValidator`(DB 열 제약에 걸릴 값을 모두 Reject), 모르는 enum 문자열은 0번 대체값(`LenientEnum`). `TelemetryIngestService`가 유형별로 분기하고 `Lap.SessionKey`를 저장.
       `Seasons/Queries`: `SeasonQueryService`·`SessionQueryService`, 순수 계산 `SeasonSessionSelector`·`StandingsCalculator`·`RoundNumbering`, 정적 `TeamCatalog`.
       읽기 포트는 `ISeasonQueryRepository`·`IGameSessionQueryRepository`로 쓰기 포트와 분리.
     - Infrastructure: 설정 5종(모든 unique index에 `is_deleted = false` 필터, `Id`는 `ValueGeneratedNever`), 저장소 4종, **마이그레이션 `AddSeasonsAndSessions`**(가산적: 테이블 5개 + `laps.session_key`).
     - Api: `GET /me/seasons`·`/me/seasons/{id}`·`/me/sessions`(`sessionType` 필터)·`/me/sessions/{id}`(남의 것 = 404), `TelemetryHub.MaxMessageBytes` = 64KiB 명시.
   - **Agent:** Core — enum 4종·프레임(`ParticipantsFrame`·`ClassificationFrame`, `SessionFrame` 필드 추가)·`SessionResultTracker`·`ITelemetryAnalyzer`, `LapFinished`에 `gameMode`·링크 3개.
     Infrastructure — `F1PacketMapper`가 Participants(4)·Final Classification(8)을 매핑(`F1EnumMaps`, 빈 칸 제외, 깨진 시간값 보정, 이름 NUL 절단),
     `TelemetryPipeline`이 분석기 목록을 분석기별 try/catch로 실행, `OutboxTelemetrySink`가 적재 전 48KiB 검사(초과 시 스틴트를 빼고 재시도).
   - **App:** `features/seasons`(Seasons 목록 · 시즌 상세 Season/Results/Standings 탭)·`features/sessions`(Sessions 목록 + 필터 · 세션 결과), 경로 `/seasons`·`/seasons/:seasonId?tab=`·`/sessions?type=`·`/sessions/:sessionId`,
     사이드바 순서 Dashboard · Seasons · Sessions · Laps · Leaderboard · Telemetry App. 공용 위젯 `PaginationBar`·`NotFoundState`·`Stat`·`TeamColorBar`·`AiBadge`·`EmptyStateCard`(`core/widgets`), `parseHexColor`(`core/util`).
   - **계약·문서:** `shared/schema/session_classified.json`(신규)·`telemetry_envelope.json`·`lap_finished.json`, `shared/samples/telemetry_session_classified_envelope.json`(22대), `shared/openapi/openapi.yaml`,
     `CLAUDE.md`·`docs/02~06·08·11·12`·`TESTING-local-e2e.md` 갱신.
   - **검증 범위:** 단위·통합 테스트(PostgreSQL 통합 36개: 허브 → 인입 → 조회 API, 병합, 64KiB 한도 회귀, 404/400/401). **F1 25로는 확인하지 못했다** — Final Classification 수신,
     Participants 레이아웃, 링크 식별자 동작 등 §3.3의 가정 8개는 미확인([TESTING-local-e2e.md](./TESTING-local-e2e.md) §10).
14. **프로필·계정 설정 (완료: Backend 451 · App 364 통과, analyze 이슈 0, 빌드 경고 0):** 설계 [docs/14](./14-profile-settings.md), 결정 D-39·D-40. 요청 "내 프로필 누르면 설정화면이 나와야 해"(F1Laps Edit Profile 참고).
   - **Backend:** `User`에 `ShowOnLeaderboard`·`AvatarTeam`·`PreferredGame`·`Controller`·`Console`·`Units`·`TimeZoneId`·`Theme`(enum 4종 문자열 저장, 기본값 `UserProfileDefaults`),
     **마이그레이션 `AddUserProfileSettings`**(가산적, 기존 사용자 백필) + **`DefaultThemeDark`**(테마 System → Dark, 열 기본값 Dark — D-40). `GET /me` 설정 포함, `PUT /me/profile`(전체 교체·필드별 400, `ProfileUpdateValidator`)·`POST /me/email`(비밀번호 틀림 400·중복 409)
     — `ProfileService`·`MyProfileController`. 가입과 같은 입력 규칙(`UserInputRules`), 엄격한 enum 해석(`EnumNames`), IANA 타임존 검증·정식 표기 저장, 이메일 변경 사용자당 분당 10회(`RateLimitPolicies.EmailChange`). 랭킹 이름 비공개 = `RankingPrivacy`("익명 드라이버", REST·허브 공통).
   - **App:** `features/profile`(설정 화면·폼 컨트롤러·저장소·사진 고르기·대화상자), 사이드바 하단 프로필 → `/settings`, 로그인 뒤 `GET /me`로 프로필 로드·`applyProfile`로 반영,
     밝은 팔레트(`AppColors.light*` + `AppPalette` 테마 확장 — 상태·시상대 글자색 포함, 위젯은 `context.palette`)·`themeModeProvider`(기본 Dark), `ApiException.fieldErrors`(우리 서버 문서만),
     요약 사용자의 프로필 재조회(`isProfileLoaded`·`profileReloadProvider`, 읽기 전 저장 금지), 저장 중 편집 유지, 공용 `SectionCard`를 `core/widgets`로 이동.
   - **계약·문서:** `shared/openapi/openapi.yaml`(`/me/profile`·`/me/email`·설정 스키마, 로그인 `UserSummary`), `docs/03·04·05·08·14`.
   - **검증 범위:** 단위·위젯·통합 테스트(비공개 사용자의 RankingHub `RankingUpdated`·REST 익명화 포함), 임시 골든 렌더로 밝은/어두운 배치 확인. 실제 브라우저 확인은 서버 재시작 뒤.
15. **실제 게임 연동 버그 수정 (D-41, Agent 246 통과):** 증상 "게임 안에서 127.0.0.1로 설정하고 한랩 돌아봤는데 기록이 저장 안 됨" — Tray는 초당 약 150개를 받는데 Outbox·서버에 이벤트 0.
   - **원인:** F1Game.UDP 26.0.0 = 2026 시즌팩 레이아웃. 실제 게임 패킷 12종이 `NotEnoughBytesException`(예: LapData 1285바이트, 1399 요구)으로 거부되고 `F1PacketMapper`가 로그 없이 버렸다.
   - **수정:** 25.1.1(API 동일), 패킷을 버리는 세 경로(해석 실패·포맷 불일치·플레이어 칸 밖)를 사유마다 1회 경고(`F1PacketMapper`에 `ILogger`), 회귀 테스트 `F1WireLayoutTests`(실제 Session·LapData 바이트 `Fixtures/F1_25` + 16종 스펙 크기 — 26.0.0에서 13개 실패 확인),
     매퍼 테스트 칸 수 24 → 22, 트랙 계약 테스트 = "라이브러리 ⊆ 계약"(Madrid 42는 시드에 남김).
   - **검증 범위:** 캡처한 실제 패킷을 Tray(UDP 20777)로 재생 → Outbox 기록 → 허브 수신·장치 `last_seen_at` 갱신. 랩 저장은 게임으로 확인 필요.

---

## 4. 다음 할 일 (미완료) ⬜

**Phase 7 완료 → 다음 = P8 세션 상세**(랩별 랩타임, 타이어 스틴트별 마모·랩타임, 패널티 내역, 그랑프리 주말 상세 화면. `Lap.SessionKey`로 랩과 세션을 잇는다).
설계 → 리뷰 → 계획 → 구현 → 리뷰 순서로 착수한다(로드맵: [07](./07-roadmap.md), [11](./11-personal-mode.md) §0).
이후 P9 랩 상세·텔레메트리 → P10 Analytics → P11 Agent 배포.

### 4-A. 이월분
- Agent **자동실행(Windows 시작 등록)** — Tray 부팅 시 자동 기동/재접속. (설치 파일·자동 업데이트와 함께 P11에서 다룰 후보)
- P6 웹 화면의 육안 확인(브라우저)은 컨트롤러 확인 대상. P7의 Seasons·Sessions 화면, 설정 화면(`/settings`, 밝은 테마 포함)도 같다(테스트는 통과했지만 브라우저로 본 적은 없다).
- P7 이월: Agent Outbox의 독성 항목 처리(같은 항목이 허브 예외로 계속 실패하면 dead-letter로 옮겨 뒤의 항목을 막지 않기, [12](./12-seasons-sessions.md) §12),
  시즌 이름 변경·삭제·숨기기, Dashboard 시즌 카드, Seasons·Sessions 실시간 갱신, 세션 Details 탭(P8).
- P7 리뷰에서 미뤄 둔 알려진 사항: ① Agent 매퍼가 Final Classification의 `Position`(byte)을 자르지 않는다 — 32를 넘는 깨진 값이면 백엔드 검증이 그 세션을 Reject해 1건을 잃는다(빈 칸으로 취급하는 보정 후보).
  ② 앱의 화면 내부 위젯 중복(`_DriverCell`, 표 스캐폴드 등)과 sessions ↔ seasons 기능 간 상호 import는 정리하지 않았다. ③ `TelemetryHub.MaxMessageBytes` 주석의 "약 30KB"는 실측(32~34KB)과 다르다([12](./12-seasons-sessions.md) §14).

### 4-B. 라이브 검증(하드웨어 의존, 보류 항목)
- Agent Cli/Tray를 실 F1 25(UDP 20777)로 지향해 SessionStarted→LapStarted→SectorCompleted→LapFinished 로그 관찰,
  Time Trial 1랩 후 Laps·Leaderboard·Dashboard 반영 확인([TESTING-local-e2e.md](./TESTING-local-e2e.md) §5).
  2026-10-18: 실제 게임 패킷 수신·해석·허브 전달까지 확인(D-41 수정 후). 남은 것은 한 랩을 끝낸 뒤 LapFinished 저장과 화면 반영.
- **P7 게임 확인:** 커리어에서 예선·레이스를 결과 화면까지 진행 → Agent 로그에서 `SessionClassified` 1건 → `/seasons`·`/sessions` 확인, 그리고 [12](./12-seasons-sessions.md) §3.3의 가정 8개 확인.
  절차와 체크리스트는 [TESTING-local-e2e.md](./TESTING-local-e2e.md) §10. 결과는 12 §3.3 "확인 결과" 열에 적는다.

### 4-C. 확정 범위 메모
- Phase 1 = Auth만(세션 유스케이스 P3로 연기, 엔티티 스키마는 선반영).
- Phase 2 = Core 두뇌 + F1 매퍼 + UDP 소켓(전송 없음). 파싱은 F1Game.UDP(26.0.0) 위임(D-20).

### 4-D. 확인 필요 (문서 정합성)
- `shared/telemetry/f1_25_udp_spec.md` §m_trackId 예시 "2: Silverstone"은 **오기**. F1 `Track` enum 확인 결과
  **2=Shanghai, 7=Silverstone**(코드/시드가 옳음). 스펙 문서 예시 수정만 남음(파싱은 라이브러리 위임이라 기능 영향 없음).
  - 권위 대조 소스: [hotlaps/f1-game-udp-specs](https://github.com/hotlaps/f1-game-udp-specs).
- 로컬 개발 User-Secrets(이 PC): `ConnectionStrings:Postgres`(localhost/postgres/1234), `Jwt:Key`(dev). **다른 환경은 재주입 필요**(리포 미포함).

---

## 5. 확정 결정 요약 (근거: `docs/08`)

| ID | 결정 |
|---|---|
| D-1 | ~~멀티스토어 `StoreId` 선반영~~ → D-25로 대체 |
| D-2 | ~~랩-사용자 귀속 = 앱 체크인 세션(Agent 무상태·무인증)~~ → D-25로 대체 |
| D-3 | 유스케이스 = 얇은 Service + 인터페이스 (MediatR 보류) |
| D-4 | App = `dio` + `signalr_netcore` (잠정) |
| D-5 | Car/차량 개념 MVP 제외 |
| D-6 | PK = `Guid(UUID v7)` |
| D-7 | 섹터 = 가변 `LapSector` 테이블 (타 게임 대비) |
| D-8 | 랭킹 = 일/월/연 지원, 일별 경계 = 로컬 자정(타임존은 D-27 서버 설정) |
| **D-8a** | **실시간 랭킹 기본 기준 = 월별(monthly)** |
| D-9 | Refresh Token MVP 제외 |
| D-10 | ~~중복 활성 세션 = 사용자 본인 이전 세션 자동 종료~~ → D-25로 대체 |
| D-11 | 회원가입 = 앱 직접 가입(self-signup) |
| D-12 | ~~Agent 인증 = 장비별 API Key~~ → D-25로 대체 |
| D-13 | 이벤트 순서 = 세션 단위 |
| D-14 | 대상 게임 = F1 25(`F1_25`), 도메인은 게임 중립 |
| D-15 | 무효 랩 저장 + 랭킹 제외(개별 조회 가능) |
| D-16 | SessionType 구분, 실시간 랭킹 = Time Trial만, 타 세션 개별 조회 |
| **D-20** | **F1 UDP 파싱 = F1Game.UDP 채택(버전은 D-41), Infra에서 게임중립 모델로 매핑(Core 무의존)** |
| D-21 | ~~Agent 인증 = SimRig별 API Key(`rigCode` 귀속)~~ → D-25로 대체 (`X-Agent-Key`·SHA-256 해시 저장은 D-26이 계승) |
| D-22 | ~~활성 세션 없는 랩 = Drop+Ack~~ → D-25로 대체. 영구 무효 = Reject, 무응답만 재전송은 유지 |
| D-23 | P3 = 인입·저장(브로드캐스트 P4). TelemetryHub는 요청/응답(반환값 Ack) |
| **D-24** | **랭킹 = 쿼리 온디맨드. 브로드캐스트 = 커밋 후 best-effort(`IRankingNotifier`)** (타임존 출처 `Store.TimeZoneId`는 D-27로 대체) |
| **D-25** | **개인 모드 전환: 매장·좌석·체크인 제거, 랩 귀속 = 계정에 연결된 Agent 장치(장치 주인)** |
| **D-26** | **Agent 계정 연결 = 1회용 연결 코드(10분) → 장치별 키(`X-Agent-Key`, SHA-256 해시, DPAPI 로컬 저장, `deviceId`·`sub` 클레임)** |
| **D-27** | **랭킹 기간 경계 타임존 = 서버 설정 `Ranking:TimeZoneId`(기본 `Asia/Seoul`, 시작 시 검증)** |
| **D-28** | **세션 결과 수집 = 세션당 최종 순위표 1건(`SessionClassified`, Agent가 Participants·Final Classification을 합침)** |
| **D-29** | **시즌·주말·세션 식별 = 게임 링크 식별자(시즌 대상 모드만), 세션 키 `link:`/`uid:`, 같은 키는 최신 결과로 병합, `Lap.SessionKey` 저장** |
| **D-30** | **Sessions = 최종 순위가 확정된 세션만, Time Trial 제외(Agent·백엔드 모두)** |
| **D-31** | **Standings = 기록된 세션 점수 합, 우승·포디움·카운트백은 본 레이스만, 같은 주말·종류는 최신 1건, Constructors 포함** |
| **D-32** | **시즌 안의 드라이버 식별 = `player` → `driver:{id}` → `name:{이름}#{번호}`(→ `car:{SessionRef}:{carIndex}`)** |
| **D-33** | **팀 이름·색 = 백엔드의 게임별 정적 카탈로그(`TeamCatalog`)** |
| **D-34** | **남의 시즌·세션 조회 = 404(없는 것과 동일)** |
| **D-39** | **프로필·설정 = User 설정 필드 + `PUT /me/profile`·`POST /me/email`, 이름 비공개 = 랭킹 "익명 드라이버", 사진 = 팀 색 원(로고 미사용), 밝은 테마 추가** |
| **D-40** | **기본 테마 = Dark(기존·새 사용자, 로그아웃·스플래시 포함), System은 고를 때만** |
| **D-41** | **F1Game.UDP = 25.1.1(실제 F1 25 레이아웃). 해석 실패는 종류마다 1회 경고, 실제 패킷 회귀 테스트** |

**Future 결정(해당 Phase 착수 시 결정, 지금 불필요):** D-17(트레이스 저장 원칙 해석), D-18(트레이스 저장소), D-19(샘플링·채널·보존). → `docs/09`

---

## 6. 다른 환경에서 재개하는 방법

1. 리포지토리를 clone: `git clone https://github.com/stlim1025/SimHub.git`
2. .NET 10 SDK 설치: `dotnet-install.ps1 -Channel 10.0` 또는 공식 인스톨러.
3. Flutter SDK 설치 (Android/iOS/Web 타겟).
4. 새 세션에서 읽는 순서: **이 `PROGRESS.md` → `CLAUDE.md` → `docs/08`(결정) → 필요한 설계 문서.**
5. 진행 지점: **§4 "다음 할 일" = P8 세션 상세 설계 착수.** 코드 착수 전 설계안 리뷰부터. (P6·P7 브랜치 `feat/p6-personal-mode`·`feat/p7-seasons-sessions`의 머지 여부는 git으로 확인)
6. 작업 규칙(헌장): 설계 → 리뷰 → 구현 → 리뷰. 추측 금지, 불확실하면 질문. 구조 임의 변경 금지.
7. 로컬에서 직접 돌려 보려면 [TESTING-local-e2e.md](./TESTING-local-e2e.md) (가입 → 연결 코드 → `pair` → 주행).

### 개발 환경 전제(참고)
- Backend/Agent: **.NET 10 SDK** 필요. (`global.json`에 10.0.301 고정)
- Backend DB: **PostgreSQL** (EF Core Code First + Migration).
- App: **Flutter SDK** (Android/iOS/Web). 웹 실행은 `flutter run -d web-server --web-hostname localhost --web-port 5960 --dart-define=API_BASE_URL=http://localhost:5284`.
- Agent: Windows + F1 25(UDP Telemetry 활성, 기본 포트 20777). **WPF** 기반 트레이 앱. 장치 키는 DPAPI로 `%LOCALAPPDATA%\SimCenter\Agent\device.key`에 저장.
- Secrets(JWT 서명키, DB 접속)는 코드에 두지 않음(환경변수/User-Secrets). 장치 키는 서버에 해시만 저장하고 원문은 Agent PC의 DPAPI 파일에만 있다.
- 이 PC 환경 메모: `DOTNET_ROOT`는 `C:\Program Files\dotnet`, `flutter test`는 영문 `TEMP`/`TMP`(예: `C:\Temp`)가 필요하다 — [TESTING-local-e2e.md](./TESTING-local-e2e.md) §6.

---

## 7. 이 문서 갱신 규칙

- **Phase/작업이 진행될 때마다 §1(상태)·§3(완료)·§4(다음 할 일)를 갱신**한다.
- 새 결정이 생기면 `docs/08`에 추가하고 §5 요약에 반영한다.
- 이 문서가 항상 "지금 어디까지 왔고 다음에 뭘 하는지"의 단일 진실이 되도록 유지한다.
