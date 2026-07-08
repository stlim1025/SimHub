# PROGRESS — 진행 상황 / 인수인계

> Last Updated: 2026-07-08
> **이 문서 목적:** 다른 PC·다른 세션에서도 작업을 그대로 이어가기 위한 단일 상태 파일.
> 새 세션은 이 파일 → `CLAUDE.md` → `docs/00~09` 순으로 읽으면 맥락이 복원된다.
> (주의: AI 메모리는 머신 로컬(`~/.claude`)이라 이동하지 않는다. **진행 상태의 진실 원천은 이 문서**다.)

---

## 1. 한 줄 상태

**Phase 4(랭킹 계산 REST + RankingHub 브로드캐스트) 완료 — 백엔드 빌드 경고0/테스트 54
(Domain 3 + Application 49 + E2E 2), 실 PostgreSQL에서 마이그레이션(`AddStoreTimeZone`)·시더 백필·
`/rankings`·`/me/laps` E2E 통과. 다음 단계 = Phase 5(Flutter MVP 앱).**

(이전) Phase 3(실시간 인입: Agent Outbox+SignalR → TelemetryHub → DB) 완료 — E2E 통합테스트
(회원가입→로그인→체크인→Hub→DB Lap 귀속)를 실 PostgreSQL에서 통과.

(이전) Phase 2 + Tray GUI(연결 상태 신호등) 완료 — Cli/Tray UDP 20777 바인딩 + 수신 스모크, Tray 실행 확인.

(이전) Phase 1(Backend 데이터/인증 코어) 완료 — 실 PostgreSQL 마이그레이션+시드+register/login/me E2E 검증.

---

## 2. 리포지토리 현재 상태

- 위치(개발 PC 기준): `D:\Project\SimHub` (경로는 환경마다 다를 수 있음)
- 형상: **Phase 0 완료.** 계약 스펙 + 3개 솔루션 뼈대가 생성됨. 빌드 통과 확인.
  ```
  CLAUDE.md                        # 프로젝트 헌장(압축본, 71줄)
  docs/00~09 + PROGRESS.md         # 설계 문서 + 진행 상황
  global.json                      # .NET 9 SDK 버전 고정
  shared/                          # 계약(Contract) — OpenAPI, JSON Schema, Telemetry Spec, Samples
  backend/                         # ASP.NET Core 9 Clean Architecture (빌드 ✅)
  agent/                           # .NET 9 Agent — WPF Tray + Core + Infrastructure (빌드 ✅)
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
2. **핵심 결정 D-1~D-16 + D-8a 전부 확정** (§5 참조), 각 문서 반영 완료.
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

---

## 4. 다음 할 일 (미완료) ⬜

**Phase 4 완료 → Phase 5(Flutter MVP 앱) 착수.**

### 4-A. 다음 단계 = Phase 5 — Flutter MVP 앱
로드맵 07 기준. 착수 시 헌장대로 설계안 리뷰부터.
- **App:** Splash → Login → Home → Today's Ranking(실시간) → My Lap Record.
  Riverpod + GoRouter + `dio`(REST: `/auth`·`/rankings`·`/tracks`·`/me/laps`) + `signalr_netcore`(RankingHub 구독:
  `RankingUpdated`/`LapRecorded`/`PersonalBestAchieved`, `SubscribeTrack`). 재접속 시 그룹 재구독 + REST 재동기화.
- **잔여(P3/P4에서 이월):** Agent **자동실행(Windows 시작 등록)**. 실 F1 라이브 검증(§4-B).
- **산출물(MVP 완료):** 앱에서 로그인·체크인·실시간 TOP10·내 기록 확인.

### 4-B. 라이브 검증(하드웨어 의존, 보류 항목)
- Agent Cli/Tray를 실 F1 25(UDP 20777)로 지향해 SessionStarted→LapStarted→SectorCompleted→LapFinished 로그 관찰.
  현재는 게임/장비 없어 단위테스트 + 스모크(바인딩/무크래시)까지만 검증됨.

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
| D-1 | 멀티스토어 `StoreId` 선반영 |
| D-2 | 랩-사용자 귀속 = 앱 체크인 세션(Agent 무상태·무인증) |
| D-3 | 유스케이스 = 얇은 Service + 인터페이스 (MediatR 보류) |
| D-4 | App = `dio` + `signalr_netcore` (잠정) |
| D-5 | Car/차량 개념 MVP 제외 |
| D-6 | PK = `Guid(UUID v7)` |
| D-7 | 섹터 = 가변 `LapSector` 테이블 (타 게임 대비) |
| D-8 | 랭킹 = 일/월/연 지원, 일별 경계 = 매장 로컬 자정 |
| **D-8a** | **실시간 랭킹 기본 기준 = 월별(monthly)** |
| D-9 | Refresh Token MVP 제외 |
| D-10 | 중복 활성 세션 = 사용자 본인 이전 세션 자동 종료 |
| D-11 | 회원가입 = 앱 직접 가입(self-signup) |
| D-12 | Agent 인증 = 장비별 API Key |
| D-13 | 이벤트 순서 = 세션 단위 |
| D-14 | 대상 게임 = F1 25(`F1_25`), 도메인은 게임 중립 |
| D-15 | 무효 랩 저장 + 랭킹 제외(개별 조회 가능) |
| D-16 | SessionType 구분, 실시간 랭킹 = Time Trial만, 타 세션 개별 조회 |
| **D-20** | **F1 UDP 파싱 = F1Game.UDP(26.0.0) 채택, Infra에서 게임중립 모델로 매핑(Core 무의존)** |
| D-21 | Agent 인증 = SimRig별 API Key(SHA-256 해시 저장, `X-Agent-Key`, 연결에 rigCode 귀속) |
| D-22 | 활성 세션 없는 랩 = Drop+Ack. 영구 무효 = Reject. 무응답만 재전송 |
| D-23 | P3 = 인입·저장·체크인(브로드캐스트 P4). TelemetryHub는 요청/응답(반환값 Ack) |
| **D-24** | **랭킹 기간 경계 타임존 = `Store.TimeZoneId`(IANA). 랭킹 = 쿼리 온디맨드. 브로드캐스트 = 커밋 후 best-effort(`IRankingNotifier`)** |

**Future 결정(해당 Phase 착수 시 결정, 지금 불필요):** D-17(트레이스 저장 원칙 해석), D-18(트레이스 저장소), D-19(샘플링·채널·보존). → `docs/09`

---

## 6. 다른 환경에서 재개하는 방법

1. 리포지토리를 clone: `git clone https://github.com/stlim1025/SimHub.git`
2. .NET 9 SDK 설치: `dotnet-install.ps1 -Channel 9.0` 또는 공식 인스톨러.
3. Flutter SDK 설치 (Android/iOS/Web 타겟).
4. 새 세션에서 읽는 순서: **이 `PROGRESS.md` → `CLAUDE.md` → `docs/08`(결정) → 필요한 설계 문서.**
5. 진행 지점: **§4 "다음 할 일" = Phase 1 상세 설계 착수.** 코드 착수 전 설계안 리뷰부터.
6. 작업 규칙(헌장): 설계 → 리뷰 → 구현 → 리뷰. 추측 금지, 불확실하면 질문. 구조 임의 변경 금지.

### 개발 환경 전제(참고)
- Backend/Agent: **.NET 9 SDK** 필요. (`global.json`에 9.0.315 고정)
- Backend DB: **PostgreSQL** (EF Core Code First + Migration).
- App: **Flutter SDK** (Android/iOS/Web).
- Agent: Windows + F1 25(UDP Telemetry 활성, 기본 포트 20777). **WPF** 기반 트레이 앱.
- Secrets(JWT 서명키, 장비 API Key, DB 접속)는 코드에 두지 않음(환경변수/User-Secrets).

---

## 7. 이 문서 갱신 규칙

- **Phase/작업이 진행될 때마다 §1(상태)·§3(완료)·§4(다음 할 일)를 갱신**한다.
- 새 결정이 생기면 `docs/08`에 추가하고 §5 요약에 반영한다.
- 이 문서가 항상 "지금 어디까지 왔고 다음에 뭘 하는지"의 단일 진실이 되도록 유지한다.
