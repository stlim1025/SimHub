# PROGRESS — 진행 상황 / 인수인계

> Last Updated: 2026-07-07
> **이 문서 목적:** 다른 PC·다른 세션에서도 작업을 그대로 이어가기 위한 단일 상태 파일.
> 새 세션은 이 파일 → `CLAUDE.md` → `docs/00~09` 순으로 읽으면 맥락이 복원된다.
> (주의: AI 메모리는 머신 로컬(`~/.claude`)이라 이동하지 않는다. **진행 상태의 진실 원천은 이 문서**다.)

---

## 1. 한 줄 상태

**Phase 1(Backend 데이터/인증 코어) 완료 — 빌드/단위테스트(17) 통과(경고 0),
실 PostgreSQL 마이그레이션 적용 + 시드 + register/login/me E2E 검증 완료. 다음 단계 = Phase 2(Agent Core).**

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

---

## 4. 다음 할 일 (미완료) ⬜

**Phase 1 완료 → Phase 2 착수.**

### 4-A. Phase 1 실 DB 검증 (완료 ✅)
- 로컬 개발 환경(이 PC) User-Secrets 주입 완료:
  `ConnectionStrings:Postgres = Host=localhost;Port=5432;Database=simcenter;Username=postgres;Password=1234`,
  `Jwt:Key = (dev 전용)`. **다른 PC/환경에서는 각자 User-Secrets 재주입 필요**(시크릿은 리포에 없음).
- `dotnet ef database update` → `simcenter` DB 생성 + `InitialCreate` 적용 성공.
- API 시작 시 시드 적용: Store 1 / SimRig 4(A-01~04) / Track 27(F1_25). 재기동 시 멱등.
- E2E 검증: register **201**, login **200(JWT)**, GET /me(Bearer) **200**, 잘못된 비번 **401**,
  중복 가입 **409**, 토큰 없음 **401** — 모두 RFC7807 ProblemDetails.
- PK는 UUID v7 확인(`019f3ac0-...`).

### 4-B. 범위 결정 반영 (이번 세션 확정)
- **Phase 1 범위 = Auth만**(로드맵 07 준수). 세션 **체크인/체크아웃 유스케이스·컨트롤러는 P3로 연기**.
  단, DrivingSession/Lap/LapSector **엔티티 스키마는 InitialCreate에 선반영**(마이그레이션 난개발 회피).

### 4-C. 다음 단계 = Phase 2 — Telemetry Agent (Core)
- **파싱 = F1Game.UDP(26.0.0) 채택(D-20).** 오프셋 수제 파싱 금지.
  - `Agent.Infrastructure`: UDP 소켓 수신 + F1Game.UDP로 파싱 → **게임중립 입력 모델(예: LapSnapshot)로 매핑**.
  - `Agent.Core`: 매핑된 모델을 받아 LapAnalyzer(세션/랩/섹터/완주 판정) + 도메인 이벤트 생성.
    **F1Game.UDP 무의존 유지**(순수 로직·단위테스트·타 게임 확장). 고정 샘플로 LapFinished 판정 검증.
  - 런타임 `m_packetFormat` 검증(불일치 경고/스킵).
- 착수 시 헌장대로 설계안 리뷰부터. 이후 순서: P3 실시간 인입 → P4 랭킹·브로드캐스트 → P5 Flutter MVP. (상세 `docs/07-roadmap.md`)

### 4-D. 확인 필요 (문서 정합성)
- `shared/telemetry/f1_25_udp_spec.md` §m_trackId 예시가 "2: Silverstone"으로 기재됨(예시·"등").
  Codemasters 표준은 **2=Shanghai, 7=Silverstone**. `DbSeeder`는 표준 매핑으로 시드했으므로,
  스펙 문서의 예시 수정 여부를 확인할 것.
  - 참고: `m_trackId` 정수→트랙 매핑은 F1Game.UDP가 파싱해줘도 **DB Track 마스터 시드는 우리 책임**.
    권위 있는 대조 소스: [hotlaps/f1-game-udp-specs](https://github.com/hotlaps/f1-game-udp-specs) (EA/Codemasters UDP 스펙).

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
