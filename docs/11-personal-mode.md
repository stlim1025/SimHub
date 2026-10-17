# 11 · Personal Mode (Phase 6) — 개인 모드 전환 + 웹 셸

> Status: **Implemented (2026-10-17)** · Last Updated: 2026-10-17
> 카페 모델(매장·좌석·체크인)을 **개인 모델(내 PC의 Agent를 내 계정에 연결)** 로 전환하고,
> F1Laps를 참고한 **사이드바 웹 셸**을 만들었다. 결정은 [08](./08-open-decisions.md)에 D-25~27로 기록했다.
> 구현 중 달라진 점: 마이그레이션이 1건이 아니라 **2건**(`AddAgentDevices` + `PersonalMode`)이다 — §3.4.

---

## 0. 배경과 로드맵 위치

MVP(P0~P5)가 끝났다. 이제 제품 방향을 **개인용 F1 기록 플랫폼**으로 바꾼다(D-25).
F1Laps와 비슷한 구성(Dashboard · Seasons · Sessions · Laps · Analytics · Telemetry App)을 목표로 하며,
범위가 커서 아래 단계로 나눈다. **각 단계는 따로 설계 → 계획 → 구현 → 리뷰를 거친다.**

| 단계 | 내용 | 결과물 |
|---|---|---|
| **P6** | 개인 모드 전환 + 웹 셸 (**이 문서**) | 내 PC의 Agent로 내 랩이 쌓이고, 새 레이아웃이 보인다 |
| P7 | 시즌·세션 수집. `SeasonLinkIdentifier` / `WeekendLinkIdentifier` / `SessionLinkIdentifier`로 시즌 → 그랑프리 → 세션을 묶고, `FinalClassification`·`Participants`로 AI 포함 전 드라이버 결과를 저장하며 Standings를 계산한다 | Seasons(Season/Results/Standings) · Sessions 화면 |
| P8 | 세션 상세: 랩별 랩타임, 타이어 스틴트별 마모·랩타임, 패널티 | 그랑프리 상세 · 세션 Details 화면 |
| P9 | 랩 상세 + 텔레메트리 트레이스([09](./09-lap-telemetry-trace.md), D-17~19). 섹터 비교(내 최고 기록 대비), 스로틀·브레이크·스티어링 | 랩 상세(Telemetry 탭 포함) |
| P10 | Analytics(트랙별 AI 난이도 등) | Analytics 화면 |
| P11 | Agent 배포: 설치 파일, 자동 업데이트, 다운로드 링크 | Telemetry App 페이지의 다운로드 영역 완성 |

> P7에 필요한 세 링크 식별자가 F1Game.UDP 26.0.0의 `SessionDataPacket`에 있는 것은 확인했다("세이브가 바뀌어도 유지").

---

## 1. 범위

| 포함 (P6) | 제외 (후속 단계) |
|---|---|
| `AgentDevice` · `AgentPairingCode` 엔티티, 매장·좌석·체크인 제거, 마이그레이션 | Seasons · Sessions · Analytics (P7·P10) |
| 1회용 코드 → 장치 키 연결 API, 장치 목록·해제 API | 세션 상세 · 스틴트 · 패널티 (P8) |
| 인입 귀속 변경(장치 주인), 체크인 없는 랩 Drop 규칙(D-22) 제거 | 랩 상세 · 텔레메트리 트레이스 (P9) |
| 랭킹 타임존을 서버 설정으로 이동 | Agent 설치 파일 · 자동 업데이트 (P11) |
| Agent: `ServerBaseUrl`, DPAPI 키 저장, Cli `pair`, Tray 연결 UI, 401 처리 | 계정 설정(이름·비밀번호 변경) 화면 |
| Flutter 사이드바 셸 + Dashboard · Laps · Leaderboard · Telemetry App | Refresh Token (D-9 유지) |
| 헌장(CLAUDE.md) · 결정(08) · 관련 문서 · `shared/` 계약 갱신 | 장치 수 제한 |

---

## 2. 결정 ([08](./08-open-decisions.md)에 기록됨)

### D-25. 제품 방향 = 개인 모드로 전환
- 카페 운영 모델(매장·좌석·체크인)을 쓰지 않는다. 사용자가 **자기 PC에 Agent를 설치하고 자기 계정에 연결**한다.
- **대체되는 결정:** D-1(멀티스토어 `StoreId`), D-2(랩 귀속 = 체크인 세션), D-10(중복 세션 정책),
  D-12·D-21(좌석별 API Key), D-22(활성 세션 없는 랩 Drop), D-24 중 **타임존 출처**(`Store.TimeZoneId`).
- **유지되는 결정:** D-6(UUID v7), D-7(가변 섹터), D-8·D-8a(일/월/연 랭킹, 기본 월별), D-13, D-14(F1 25),
  D-15·D-16(무효 랩 저장, 랭킹 = Time Trial만), D-20(F1Game.UDP), D-23(Hub 요청/응답 Ack), D-24 중 경계 규칙과 브로드캐스트 규칙.

### D-26. Agent 계정 연결 = 1회용 연결 코드 → 장치별 키
- 웹에서 10분짜리 1회용 코드를 발급하고, Agent가 그 코드를 장치별 장기 키로 교환한다.
- 이후 인증은 기존 `X-Agent-Key` 메커니즘(SHA-256 해시 저장)을 그대로 쓰되, 키가 **AgentDevice**를 가리킨다.
- 검토한 대안: 계정 고정 코드(F1Laps 방식, 노출 시 도용·일괄 재발급 필요), Agent에서 이메일·비밀번호 로그인(Refresh Token 필요, 트레이 앱이 비밀번호를 다룸).

### D-27. 랭킹 기간 경계 타임존 = 서버 설정 `Ranking:TimeZoneId`
- 기본값 `Asia/Seoul`(IANA). 서버 시작 시 검증하고, 잘못되면 시작을 실패시킨다(fail fast).
- 경계 계산(`RankingPeriodRange`)은 그대로다. 타임존을 어디서 읽는지만 바뀐다.

---

## 3. 도메인 · 데이터 모델

### 3.1 신규 엔티티 (모두 `BaseEntity`: `Id`(UUID v7) · `CreatedAt` · `UpdatedAt` · `IsDeleted`)

**`AgentDevice`** — 내 계정에 연결된 PC

| 필드 | 타입 | 제약 / 설명 |
|---|---|---|
| `UserId` | Guid | FK → users, `Restrict` |
| `Name` | string | 1~50자. 기본값은 Agent가 보낸 컴퓨터 이름 |
| `ApiKeyHash` | string | SHA-256 hex(64자), unique |
| `LastSeenAt` | DateTime? (UTC) | 마지막 이벤트 수신 시각 |

- **연결 해제 = soft delete(`IsDeleted = true`).** 전역 soft-delete 필터 때문에 인증 조회에서 자동으로 빠진다.
- 인덱스: `UserId`.

**`AgentPairingCode`** — 1회용 연결 코드

| 필드 | 타입 | 제약 / 설명 |
|---|---|---|
| `UserId` | Guid | FK → users, `Restrict` |
| `CodeHash` | string | 정규화한 코드의 SHA-256 hex, unique |
| `ExpiresAt` | DateTime (UTC) | 발급 후 10분 |
| `ConsumedAt` | DateTime? (UTC) | 사용 시각. 값이 있으면 재사용 불가 |

- 새 코드를 발급하면 같은 사용자의 **미사용 코드를 모두 무효화**(soft delete)한다.
- `CodeHash` unique 충돌(이전 코드와 우연히 같은 값)이 나면 코드를 다시 만든다(최대 3회, 이름 붙은 상수). 그래도 실패하면 500.
- 인덱스: `UserId`.

### 3.2 변경

**`Lap`**
- `DrivingSessionId`(FK) **제거**, `AgentDeviceId`(Guid, 필수, FK → agent_devices, `Restrict`) **추가**.
- `UserId`에 users FK(`Restrict`)를 건다. 지금은 FK 없이 값만 저장한다.
- 나머지 필드와 인덱스는 그대로다.

**`User`**
- `Sessions` 내비게이션 제거, `AgentDevices` 내비게이션 추가.

### 3.3 제거

- 엔티티: `Store`, `SimRig`, `DrivingSession`, enum `SessionStatus`
- 저장소·포트: `IStoreRepository`, `ISimRigRepository`, `IDrivingSessionRepository`와 구현체
- 서비스·DTO·컨트롤러: `SessionService`, `SessionDtos`, `SessionsController`
- 시드: 매장, 좌석 A-01~A-04, 개발용 좌석 키(`dev-agent-key-A-0x`). **트랙 시드는 유지.**

### 3.4 마이그레이션 2건: `AddAgentDevices` + `PersonalMode`

> **구현 메모:** 설계는 1건이었으나, EF Core 9+가 태스크 사이의 pending model change를 거부해 가산적인 `AddAgentDevices`(4번)와
> `PersonalMode`(1~3번)로 **나눴다.** 최종 스키마는 설계와 같다.

1. (`PersonalMode`) `laps`, `lap_sectors`, `processed_events`의 **기존 행을 삭제**한다.
   - 이유: 현재 랩은 모두 로컬 개발·테스트 데이터이고, 귀속할 장치가 없다. `AgentDeviceId`를 영구히 null 허용으로 두는 것보다 깔끔하다(사용자 승인 2026-10-17).
   - 회원(`users`)과 트랙(`tracks`)은 그대로 둔다.
2. `laps.driving_session_id` 컬럼·FK·인덱스 삭제, `laps.agent_device_id` 추가(FK), `laps.user_id` FK 추가.
3. `driving_sessions`, `sim_rigs`, `stores` 테이블 삭제.
4. (`AddAgentDevices`) `agent_devices`, `agent_pairing_codes` 테이블 생성.

---

## 4. 계정 연결 흐름

```
[Web: Telemetry App]                [Backend]                          [Agent (Cli/Tray)]
  "연결 코드 발급" ──POST /me/agent-pairing-codes──►  코드 생성(해시 저장, 10분)
  ◄── { code: "K7F2-9QXM", expiresAt } ──────────
  사용자가 코드를 Agent에 입력 ─────────────────────────────────────────────►
                                     ◄── POST /agent/pair { code, deviceName } ──
                                     코드 원자적 소비 + AgentDevice 생성
                                     ── { deviceId, deviceKey } (1회만) ──────►  DPAPI로 암호화 저장
                                     ◄── SignalR /hubs/telemetry (X-Agent-Key) ──  이후 모든 업로드
```

### 4.1 연결 코드

- **문자 집합:** `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`(32자 — `0`·`O`·`1`·`I` 제외). **길이 8**(약 40비트). `RandomNumberGenerator`로 생성.
- **표시:** `XXXX-XXXX`. **입력 정규화:** 대문자로 바꾸고 하이픈·공백을 제거한 뒤 해시한다.
- **유효 기간:** 10분(이름 붙은 상수). **1회용.**

### 4.2 장치 키

- 32바이트 난수를 base64url(패딩 없음, 43자)로 인코딩한다.
- `POST /agent/pair` 응답에서 **딱 한 번** 내려가고, 서버에는 SHA-256 해시만 남는다(`IApiKeyHasher` 재사용).

### 4.3 연결 처리 (`POST /api/v1/agent/pair`)

1. `deviceName` 검증: 앞뒤 공백 제거, 1~50자. 비어 있으면 `"Windows PC"`.
2. 코드를 정규화·해시해 `IsDeleted = false`, `ConsumedAt IS NULL`, `ExpiresAt > now`인 코드를 찾는다.
3. **조건부 UPDATE로 원자적으로 소비한다**(`consumed_at IS NULL`일 때만 갱신, 영향 행 1개일 때만 진행). 동시에 같은 코드로 두 번 연결해도 하나만 성공한다.
4. 같은 트랜잭션에서 `AgentDevice`(코드 주인 `UserId`)를 만들고 커밋한다.
5. 코드가 없음·만료·사용됨·무효화됨이면 **모두 같은 400**("유효하지 않거나 만료된 코드입니다.")을 돌려준다. 어느 경우인지 구분해 주면 추측 공격에 힌트가 된다.

### 4.4 요청 제한

- `POST /agent/pair`: **IP당 분당 10회**(고정 창). ASP.NET Core 내장 Rate Limiting을 쓴다(새 패키지 없음). 초과 시 429.
- 코드 발급(`POST /me/agent-pairing-codes`): 사용자당 분당 10회.

---

## 5. 인입 (TelemetryHub · TelemetryIngestService)

- **`AgentApiKey` 인증 핸들러:** 키 해시로 `AgentDevice`를 찾는다. 클레임은 `deviceId`(AgentDevice.Id)와 `sub`(UserId)다. `rigCode` 클레임은 없어진다.
  키는 지금처럼 `X-Agent-Key` 헤더(대체 수단으로 `access_token` 쿼리)로 받는다.
- **`TelemetryHub.SubmitEvent`:** `deviceId` 클레임을 읽어 `IngestAsync(envelope, deviceId)`를 호출한다.
- **`TelemetryIngestService.IngestAsync` 순서:**
  1. 멱등: `ProcessedEvent(eventId)`가 있으면 Ack (기존과 같음).
  2. **장치 확인:** `deviceId`로 장치를 다시 조회한다. 없거나 연결 해제됐으면 **Reject**("연결이 해제된 장치입니다.").
     연결을 해제해도 이미 열린 SignalR 연결로 계속 보내는 것을 막기 위해서다.
  3. **`LastSeenAt` 갱신:** null이거나 1분 이상 지났을 때만 쓴다(상수 `LastSeenWriteInterval = 1분`). 모든 이벤트 유형에 적용한다.
  4. LapFinished가 아니면 Ack (기존과 같음).
  5. 페이로드 파싱 실패 → Reject (기존과 같음).
  6. 트랙 매핑, 랭킹 적격 판정(`IsValid && !IsOutOrInLap && TimeTrial`), PB 판정, 저장, 커밋 후 브로드캐스트 — **기존과 같음.**
     단, `UserId = device.UserId`, `AgentDeviceId = device.Id`.
- **삭제:** 활성 체크인 세션 조회와 "활성 세션 없음 → Drop + Ack"(D-22).
- **envelope `rigCode` 필드 삭제:** `TelemetryEnvelopeDto`, `shared/schema/telemetry_envelope.json`, 샘플, Agent 모두에서 뺀다.

---

## 6. Agent (Cli · Tray)

### 6.1 설정 (`AgentOptions`)

| 변경 | 내용 |
|---|---|
| 제거 | `RigCode`, `AgentCredential` |
| `BackendUrl` → `ServerBaseUrl` | 예: `http://localhost:5284`. 연결 API는 `{ServerBaseUrl}/api/v1/agent/pair`, 허브는 `{ServerBaseUrl}/hubs/telemetry`로 만든다 |
| 기본값 | Cli·Tray 모두 `http://localhost:5284`(개발용). 비우면 업로드 비활성(기존 의미 유지) |

### 6.2 장치 키 저장소 (`IDeviceCredentialStore`, Agent.Infrastructure)

- 위치: `%LOCALAPPDATA%\SimCenter\Agent\device.key`
- **Windows DPAPI(`DataProtectionScope.CurrentUser`)** 로 암호화한다. 키가 평문 파일이나 `appsettings.json`에 남지 않는다.
- 라이브러리 추가: **`System.Security.Cryptography.ProtectedData`**(Microsoft 공식, 사용자 승인 2026-10-17).
- 연산: `Load()`(없으면 null), `Save(key)`, `Clear()`, 키가 바뀌면 알리는 이벤트(`Changed`).
- 파일이 손상돼 복호화에 실패하면 **미연결로 보고 오류 로그**를 남긴다.

### 6.3 연결 방법

- **Cli:** `SimCenter.Agent.Cli pair <코드>` (`dotnet run -- pair K7F2-9QXM`)
  - 서버에 `{ code, deviceName = Environment.MachineName }`을 보내고, 받은 키를 저장한 뒤 종료한다. 성공 0, 실패 1을 반환한다.
  - 평소 실행 시 키가 없으면 경고 "계정 미연결 — `pair <코드>`로 연결하세요"를 남긴다. 업로드는 멈추지만 UDP 수신과 Outbox 적재는 계속한다.
- **Tray:** 창에 **"계정 연결"** 영역을 추가한다.
  - 코드 입력칸 + [연결] 버튼
  - 상태: `미연결` / `연결됨 · {PC 이름}` / `다시 연결 필요`
  - [이 PC 연결 끊기]: 로컬 키 삭제(`Clear()`). 서버 쪽 해제는 웹에서 한다.
  - Tray 안에서 연결에 성공하면 `Changed` 이벤트로 업로드를 바로 시작한다(재시작 불필요).

### 6.4 업로드 (`TelemetryUploadService`)

- 키가 없으면 업로드 루프는 대기하고, `Changed` 이벤트가 오면 다시 시작한다.
- 허브 연결이 **401**로 실패하면 무한 재시도를 멈추고 상태를 `다시 연결 필요`로 바꾼다. 새 키가 저장될 때까지 업로드하지 않는다.
  (현재 코드는 401도 일반 오류처럼 계속 재시도한다.)
- 그 밖의 네트워크 오류는 지금처럼 지수 백오프(최대 30초)로 재시도한다.
- **연결 전에 쌓인 이벤트**는 연결 후 업로드되어 연결한 계정에 귀속된다(그 PC 주인의 기록으로 본다).

### 6.5 이벤트 봉투

- `TelemetryEnvelope`과 wire JSON에서 `RigCode`를 뺀다. `AgentIdentity`는 `GameCode`만 갖는다.
- UDP 수신, 랩 분석, Outbox, 재전송 구조는 바뀌지 않는다.

---

## 7. App (Flutter)

### 7.1 원칙

- 기술 스택 유지: Flutter · Riverpod · GoRouter · Material3(헌장). 한 코드베이스로 웹과 모바일을 지원한다.
- 테마: 어두운 남색 배경 + 보라(인디고) 강조색. F1Laps 스크린샷의 분위기를 따른다. 색은 `app_theme.dart`의 토큰으로만 정의한다.

### 7.2 셸

- GoRouter `ShellRoute`로 셸을 구성한다.
- 너비가 **900px 이상**이면 왼쪽 **고정 사이드바**(폭 220px), 미만이면 상단 바 + **서랍 메뉴**. 두 값 모두 이름 붙은 상수.
- 사이드바 맨 아래: 사용자 이름 + 로그아웃.
- **P6 메뉴:** Dashboard · Laps · Leaderboard · Telemetry App. (Seasons·Sessions는 P7, Analytics는 P10에서 추가. "준비 중" 같은 빈 메뉴는 두지 않는다.)
- 인증 리다이렉트 가드는 기존 그대로.

### 7.3 경로와 화면

| 경로 | 화면 | 내용 | API |
|---|---|---|---|
| `/` | Dashboard | "Welcome {이름}!", 연결 상태 카드(장치가 없으면 Telemetry App으로 안내), 최근 랩 5개, "View all lap times" → `/laps` | `GET /me/laps?pageSize=5`, `GET /me/agent-devices` |
| `/laps` | Laps | 내 기록이 있는 트랙 목록: 트랙명, 최고 유효 랩, 랩 수, 마지막 주행일 | `GET /me/tracks` |
| `/laps/tracks/:trackId` | 트랙별 랩 | Recent/Fastest 전환. 열: 랩타임(유효 ✓), S1·S2·S3, 세션 유형, 날짜. 15개씩 페이지("Showing 1 to 15 of 76"). 랩 상세 진입은 P9 | `GET /me/laps?trackId&sort&page&pageSize=15` |
| `/leaderboard` | Leaderboard | 기존 실시간 랭킹을 셸 안으로 이동. 트랙 선택(`?trackId=`), 일·월·연, TOP10, RankingHub 실시간 갱신 | 기존 `GET /tracks`, `GET /rankings`, `/hubs/ranking` |
| `/telemetry-app` | Telemetry App | ① 다운로드(P11 전까지 "설치 파일 준비 중" + 개발용 실행 안내) ② 연결 코드 발급(남은 시간, 복사 버튼) ③ F1 25 UDP 설정 안내(On · 2025 · 20777 · Agent PC IP) ④ 연결된 PC 목록과 [연결 해제] ⑤ Connection Status | `POST /me/agent-pairing-codes`, `GET`·`DELETE /me/agent-devices` |
| `/login`, `/splash` | 로그인 · 스플래시 | 기존 유지(새 테마만 적용) | 기존 |

**Connection Status 규칙**(클라이언트에서 장치들의 가장 최근 `lastSeenAt`으로 계산, 임계값은 이름 붙은 상수):
- 5분 이내 → `데이터 수신 중`
- 그보다 오래됨 → `최근 데이터 없음 · 마지막 수신 N일 전`(분·시간·일 단위)
- 한 번도 없음 → `아직 받은 데이터가 없습니다`
- 장치 없음 → `연결된 PC가 없습니다` + 연결 안내

### 7.4 제거

- `features/session` 전체, 체크인 카드가 있던 `home_page.dart`, `/rankings/:trackId` 경로(→ `/leaderboard?trackId=`), `/home` 경로(→ `/`).

---

## 8. API 변경 요약 (`/api/v1`, 응답 필드 camelCase)

| 구분 | Method · Path | 인증 | 요청 | 응답 |
|---|---|---|---|---|
| 신규 | `POST /me/agent-pairing-codes` | JWT | — | 201 `{ code, expiresAt }` |
| 신규 | `POST /agent/pair` | 없음(요청 제한) | `{ code, deviceName }` | 200 `{ deviceId, deviceKey }` |
| 신규 | `GET /me/agent-devices` | JWT | — | 200 `{ items: [{ deviceId, name, lastSeenAt, createdAt }] }` |
| 신규 | `DELETE /me/agent-devices/{deviceId}` | JWT | — | 204 |
| 신규 | `GET /me/tracks` | JWT | — | 200 `{ items: [{ trackId, trackName, gameCode, lapCount, bestValidLapTimeMs, lastSetAt }] }` |
| 변경 | `GET /me/laps` | JWT | `sort=recent\|fastest` 추가(기본 recent) | 기존과 같음 |
| 제거 | `POST /sessions/check-in`, `POST /sessions/{id}/check-out`, `GET /sessions/active` | — | — | — |
| 유지 | `GET /tracks`, `GET /rankings`, `GET /me`, `POST /auth/register`, `POST /auth/login`, `/hubs/ranking` | — | — | 기존과 같음 |

- **`sort=fastest`:** 유효 랩 먼저, 랩타임 오름차순, 동률이면 `SetAt` 오름차순. **`sort=recent`:** `SetAt` 내림차순.
- **`bestValidLapTimeMs`:** 그 트랙에서 `IsValid`인 랩 중 최소 랩타임(세션 유형 무관). 랭킹용 PB(Time Trial 적격 랩)와는 다른 값이라 이름을 구분한다. 유효 랩이 없으면 null.
- `GET /me/tracks`는 내 랩이 1개 이상 있는 트랙만, 마지막 주행일 내림차순으로 돌려준다.

---

## 9. 오류 처리

| 상황 | 처리 |
|---|---|
| 연결 코드가 틀림·만료·사용됨·무효화됨 | 400 ProblemDetails(RFC 7807), 같은 메시지 |
| `POST /agent/pair` 분당 10회 초과(IP) | 429 |
| `deviceName` 50자 초과 | 400(Validation) |
| 연결 해제된 장치로 허브 연결 | 401 → Agent는 `다시 연결 필요`로 멈춤 |
| 연결 해제된 장치가 열린 연결로 이벤트 전송 | `IngestResult.Reject("연결이 해제된 장치입니다.")` |
| 남의 장치 해제 시도 | 403. 없는 장치는 404 |
| `Ranking:TimeZoneId`가 잘못됨 | 서버 시작 실패(options `ValidateOnStart`) |
| Agent의 DPAPI 복호화 실패 | 미연결로 처리 + 오류 로그 |
| Agent 연결 중 네트워크 오류 | Cli: 오류 메시지 + 종료 코드 1. Tray: 상태 영역에 오류 표시 |

모든 오류는 Serilog로 기록한다. 연결 코드·장치 키 원문은 **로그에 남기지 않는다.**

---

## 10. 테스트 (TDD, 커버리지 80% 목표)

**Backend — 단위 (Application.Tests · Domain.Tests)**
- 연결 코드: 발급 시 코드 형식(8자, 허용 문자), 이전 미사용 코드 무효화, 해시로만 저장, 10분 만료.
- 연결: 정상 연결 시 장치 생성·키 1회 반환·키 해시 저장, 만료·사용됨·무효화·없음이 모두 같은 오류, 입력 정규화(소문자·하이픈·공백), `deviceName` 기본값과 길이 검증.
- 장치: 내 장치 목록만 반환, 해제 = soft delete, 남의 장치 403, 없는 장치 404.
- 인입: 장치 주인에게 귀속(`UserId`·`AgentDeviceId`), 해제된 장치 Reject, `LastSeenAt` 1분 제한, 멱등, 랭킹 적격·PB·브로드캐스트 회귀.
- 랭킹: 설정 타임존으로 기간 계산(기존 `RankingPeriodRangeTests` 유지).
- 내 트랙·정렬: `bestValidLapTimeMs` 계산, `sort=fastest` 정렬 규칙.

**Backend — 실 DB 통합 (Api.IntegrationTests, PostgreSQL)**
- 가입 → 로그인 → 코드 발급 → `POST /agent/pair` → 장치 키로 허브 연결 → `SubmitEvent`(LapFinished)
  → `/me/laps`·`/me/tracks`·`/rankings` 확인 → `DELETE /me/agent-devices/{id}` → 다음 `SubmitEvent`가 Reject.
- 같은 코드로 연결 두 번 → 두 번째는 400.

**Agent (Core.Tests · Infrastructure.Tests)**
- `IDeviceCredentialStore`: DPAPI 저장·복원 왕복, 파일 없음 → null, 손상 파일 → null + 로그, `Clear()`.
- `pair` 명령: 성공 시 키 저장·종료 코드 0, 400·네트워크 오류 시 종료 코드 1.
- 업로드: 키 없음 → 대기, 키 저장 → 시작, 401 → 중단·상태 전환.
- 봉투·wire JSON에 `rigCode`가 없음(기존 테스트 기대값 수정).

**App (flutter test)**
- 셸: 900px 이상 사이드바, 미만 서랍 메뉴.
- 모델 `fromJson`: 장치 목록, 연결 코드, 내 트랙.
- 연결 코드 남은 시간 표시, Connection Status 문구 계산.

**제거·수정되는 기존 테스트:** `SessionServiceTests`(전체 삭제), `TelemetryIngestServiceTests`(좌석·세션 대신 장치로),
`RankingServiceTests`(가짜 매장 저장소 대신 옵션), `TelemetryIngestE2ETests`(체크인 대신 연결 흐름),
`EntityDefaultsTests`(DrivingSession 기본값 삭제), Agent `DomainEventFactoryTests`·`TelemetryOutboxTests`(rigCode 기대값 삭제).

---

## 11. 문서 · 계약 갱신 목록 (구현과 함께)

- **CLAUDE.md:** Overview(개인 F1 기록·시즌·텔레메트리 플랫폼), Agent Rules(계정 연결 장치 키 인증),
  Confirmed Decisions("랩 귀속 = 계정에 연결된 Agent 장치"), Roadmap(P6~P11).
- **docs/08:** D-25~27 추가, 대체된 결정(D-1·D-2·D-10·D-12·D-21·D-22·D-24 일부)에 "D-25로 대체" 표기, 요약표 갱신.
- **docs/00 · 02 · 03 · 04 · 05 · 06 · 07 · 10, TESTING-local-e2e.md, PROGRESS.md:** 매장·좌석·체크인 서술을 개인 모드로 고친다.
  로컬 E2E 가이드는 "Swagger 체크인" 대신 "Telemetry App에서 코드 발급 → Agent `pair`"로 바꾼다.
- **shared/openapi/openapi.yaml:** 제목, 세션 경로·스키마 제거, §8의 신규·변경 API 추가.
- **shared/schema/telemetry_envelope.json, shared/samples/:** `rigCode` 제거.

---

## 12. P6에서 하지 않는 것

- Seasons · Sessions · Analytics 화면과 그 데이터 수집(P7 · P10)
- 세션 상세 · 타이어 스틴트 · 패널티(P8), 랩 상세 · 텔레메트리 트레이스(P9)
- Agent 설치 파일 · 자동 업데이트 · 실제 다운로드 링크(P11)
- 계정 설정 화면, Refresh Token, 장치 수 제한, 장치 이름 변경
