# 02 · Domain Design — Bounded Context

> Status: **Design (미승인)** · Last Updated: 2026-10-18 (P7 시즌·세션 반영, 앞서 P6 개인 모드 반영)
> P6에서 매장(Store)·좌석(SimRig)·주행 세션(DrivingSession)을 제거하고 **Agent 장치(AgentDevice)** 로 랩을 귀속한다(D-25). 상세: [11](./11-personal-mode.md)
> P7에서 시즌 → 그랑프리 주말 → 게임 세션 → 드라이버별 결과 계층을 추가했다(D-28~34, §3.5). 상세: [12](./12-seasons-sessions.md)

---

## 1. 목적

플랫폼 전체의 **Bounded Context 지도**를 그리고, 그중 **현재 구현 범위(MVP + P6 + P7) 도메인**을 상세화한다.
장기 확장을 고려해 경계를 미리 나누되, 소수 컨텍스트만 구현한다. (설계는 확장 대비, 구현은 YAGNI)

---

## 2. 전체 Bounded Context 지도

```
┌───────────────────────────────────────────────────────────────────────┐
│                          SimCenter Platform                            │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │  Identity    │   │   Catalog    │   │  Telemetry   │  ◄── MVP 핵심   │
│  │ & Access(+장치)│   │   (Track)    │   │  (Lap/Sector)│                │
│  └──────────────┘   └──────────────┘   └──────────────┘                │
│       MVP + P6          MVP (최소)            MVP                       │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │  Ranking     │   │  Season /    │   │ Competition  │                │
│  │ (Read Model) │   │ Session(P7~) │   │  (대회/리그)  │                │
│  └──────────────┘   └──────────────┘   └──────────────┘                │
│      MVP(조회)          P7·P8              Future                       │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │  Community    │   │  Membership  │   │  Analytics   │                │
│  │  (커뮤니티)    │   │ (멤버십/XP)   │   │  (통계)       │                │
│  └──────────────┘   └──────────────┘   └──────────────┘                │
│      Future             Future             Future                       │
└───────────────────────────────────────────────────────────────────────┘

범례:  MVP = 이번 구현 대상   Future = 경계만 정의, 구현 보류
```

### 컨텍스트 요약

| Context | 책임 | MVP |
|---|---|---|
| **Identity & Access** | 사용자, 인증(JWT), **내 계정에 연결된 PC(AgentDevice)·1회용 연결 코드(AgentPairingCode)** | ✅ |
| **Catalog** | 게임/트랙 카탈로그(Track) | ✅ (최소) |
| **Telemetry** | 랩(Lap), 섹터(Sector) 기록. 랩은 장치 주인에게 귀속 | ✅ |
| **Ranking** | 랩 기록의 조회 모델(TOP10, 개인 기록) — 읽기 전용 투영 | ✅ (조회) |
| **Season / Session** | 시즌 → 그랑프리 주말 → 세션, 전 드라이버 결과·Standings (P7), 세션 상세(P8) | ✅ P7 ([12](./12-seasons-sessions.md)) · ❌ 세션 상세 P8 |
| Competition | 대회/리그 | ❌ Future |
| Community | 게시글, 피드 | ❌ Future |
| Membership | 등급, XP, Badge, Achievement | ❌ Future |
| Analytics | 트랙별 AI 난이도 등 개인 통계 | ❌ P10 |
| ~~Facility / Reservation~~ | 매장·좌석·예약 — 개인 모드(D-25)에서 제외 | ⛔ 폐기 |
| **Lap Telemetry Trace** | 상세 텔레메트리(스로틀/브레이크/스티어/타이어 마모·온도) 랩 단위 조회 | ❌ P9 ([09](./09-lap-telemetry-trace.md)) |

---

## 3. MVP 도메인 상세

### 3.1 Identity & Access

**핵심 개념**

- `User` — 앱에 로그인하는 사람. 랩 기록의 귀속 대상.
  - 속성: 식별자, Email, PasswordHash, DisplayName(랭킹 표시명)
  - 인증: Email + Password → JWT 발급 (소셜 로그인 등은 Future)
- `AgentDevice` — 내 계정에 연결된 PC(Agent 1대). **랩-사용자 귀속의 핵심 장치(D-25).**
  - 속성: UserId(주인), Name(기본 = 컴퓨터 이름), ApiKeyHash(SHA-256), LastSeenAt(마지막 이벤트 수신 시각)
  - 연결 해제 = soft delete. 해제된 장치의 키는 인증에서 자동 제외되고, 열린 연결의 이벤트도 인입 시 Reject한다.
- `AgentPairingCode` — 웹에서 발급하는 10분짜리 **1회용 연결 코드**(해시만 저장). Agent가 코드를 장치 키로 교환하면 소비된다(D-26).

**불변식**
- DisplayName은 랭킹에 공개되므로 필수. Email은 로그인 식별자로 유일.
- 장치 키 원문은 연결 응답에서 **한 번만** 내려간다. 서버에는 해시만 남는다.
- 새 연결 코드를 발급하면 같은 사용자의 미사용 코드는 모두 무효화된다.

### 3.2 Catalog

**핵심 개념**

- `Track` — 게임 내 트랙 카탈로그. 랩 기록의 비교 기준.
  - 속성: GameCode(예: `F1_25`), TrackId(게임 내부 코드), Name
- `Car` — (선택) F1은 팀/차량 개념. **현재는 Track 단위 랭킹만** 하므로 Car는 Future로 보류. → D-5

**불변식**
- 랩은 반드시 하나의 `Track`을 참조한다. (동일 트랙끼리만 순위 비교 가능)

> 매장(`Store`)·좌석(`SimRig`)은 개인 모드(D-25)에서 제거되었다.

### 3.3 Telemetry (MVP 핵심)

**핵심 개념**

- `Lap` — 완주한 한 바퀴의 기록.
  - 속성: LapTime(ms), IsValid, IsRankingEligible, **SessionType**(TimeTrial/Practice/Qualifying/Race/…, 랭킹 집계 대상 구분에 사용 — D-16), LapNumber, 소속 **AgentDevice**/User/Track
  - **무효 랩도 보존**한다(D-15). 랭킹에서만 제외하고 개별 조회는 허용.
- `LapSector` — 랩을 구간으로 나눈 기록. **게임별 섹터 수가 다를 수 있어 가변 자식 엔티티**로 둔다(D-7).

> 주행 세션(`DrivingSession`)·체크인은 제거되었다. 게임 세션 단위의 묶음(시즌 → 그랑프리 → 세션)은 P7에서 게임이 주는 링크 식별자로 도입했다(§3.5, [12](./12-seasons-sessions.md)).
> `Lap`에는 그 세션과 이어 줄 `SessionKey`(P7은 저장만)가 추가됐다.

**랩-사용자 귀속 흐름 (D-25 · D-26)**

```
① 웹 Telemetry App에서 연결 코드 발급 (POST /me/agent-pairing-codes, 10분·1회용)
        ▼
② Agent에 코드 입력 → POST /agent/pair { code, deviceName } → AgentDevice 생성, 장치 키 1회 반환 → Agent가 DPAPI로 저장
        ▼
③ Agent가 장치 키(X-Agent-Key)로 TelemetryHub에 연결해 LapFinished 전송 (사용자 식별 정보 없음)
        ▼
④ Backend가 키로 AgentDevice를 특정 → Lap.UserId = device.UserId, Lap.AgentDeviceId = device.Id
```

> 이 방식의 장점: Agent는 사용자 비밀번호를 다루지 않고(관심사 분리), 장치를 웹에서 개별로 해제할 수 있다.
> 검토한 대안(계정 고정 코드, Agent 이메일·비밀번호 로그인)은 [08](./08-open-decisions.md) D-26 참조.

**불변식**
- `Lap`은 반드시 하나의 `AgentDevice`를 참조하고, `Lap.UserId`는 그 장치의 주인이다.
- `Lap`은 생성 후 불변(immutable). 정정이 필요하면 무효화(soft) 처리.
- `IsValid=false`(트랙 이탈 등)인 랩은 랭킹 집계에서 제외한다.

### 3.4 Ranking (읽기 전용 투영)

**성격:** Ranking은 자체 쓰기 모델을 갖지 않는다. **Lap 데이터에 대한 조회/투영(Read Model)**이다.

- `RankingTop10` — 특정 Track·기간에서 `IsRankingEligible=true`(= 유효 + **Time Trial** + 정상 랩)인
  랩 중 **사용자별 최고 기록**을 시간 오름차순 정렬한 상위 10.
- **기간(period)**: 일별 / 월별 / 연도별 지원(D-8). **실시간 랭킹(SignalR)의 기본 기준은 월별**(D-8a).
  기간 경계는 서버 설정 타임존 `Ranking:TimeZoneId`(기본 `Asia/Seoul`) 기준(일별=자정, 월별=매월 1일, 연도별=1월 1일) — D-27.
- `MyLapRecord` — 특정 사용자의 랩 기록. **모든 세션·무효 랩까지** 조회 가능(개인 최고 + 최근 기록).
  트랙별 요약(`/me/tracks`: 랩 수·최고 유효 랩·마지막 주행일)과 정렬(`recent`/`fastest`)을 지원한다.

> MVP는 실시간 쿼리로 충분. 성능 이슈 시 캐시/materialized view/Redis 도입은 Future(헌장 성능 규칙 준수).

### 3.5 Season / Session (P7 · D-28~34)

F1 25의 커리어·그랑프리 기록을 **시즌 → 그랑프리 주말 → 세션**으로 자동으로 묶고, AI를 포함한 **모든 드라이버의 세션 결과**와 **기록된 점수 기준 Standings**를 보여 준다.
상세 설계: [12](./12-seasons-sessions.md).

**핵심 개념**

- `Season` — 커리어·GP 시즌. 키 `(UserId, GameCode, SeasonLinkId)`. 게임이 주는 `SeasonLinkIdentifier`로 묶는다(D-29).
- `RaceWeekend` — 시즌 안의 그랑프리 주말. 키 `(SeasonId, WeekendLinkId)`. **라운드 번호는 저장하지 않고** 조회 시 `FirstSessionAt` 순서로 계산한다(기록된 주말 순서라 게임의 라운드와 다를 수 있다).
- `GameSession` — 최종 순위가 확정된 게임 세션 1건(연습·예선·레이스 등). 키 `(UserId, GameCode, SessionKey)`. 시즌 대상이 아닌 세션(온라인 로비, 스토리 등)은 시즌 없이 존재한다.
- `SessionResult` — 차 1대(드라이버 1명)의 최종 결과. 키 `(GameSessionId, CarIndex)`. `SessionResultTyreStint`(스틴트)를 가진다.

**규칙(순수 도메인 로직)**

- **시즌 대상(`SeasonPolicy`):** 게임 모드가 커리어 4종 또는 Grand Prix이고 시즌·주말 링크가 모두 0이 아닐 때만 시즌에 속한다.
- **세션 키(`SessionKeys`):** 시즌 대상이고 세션 링크가 0이 아니면 `link:{season}:{weekend}:{session}`, 그 밖에는 `uid:{SessionRef}`.
- **드라이버 키(`DriverKeys`, D-32):** `player` → `driver:{게임 드라이버 ID}` → `name:{이름}#{차 번호}` → (참가자 정보 없음) `car:{SessionRef}:{carIndex}`.
- **재분류 병합(`GameSession.ReplaceResults`):** 같은 세션 키로 다시 분류되면 최신 결과로 carIndex별 제자리 갱신하고, 새 순위표에 없는 차는 soft delete한다.

**불변식**

- 최종 순위표를 받은 세션만 `GameSession`이 된다(D-30). Time Trial은 저장하지 않는다(Laps·Leaderboard가 담당).
- 시즌 Standings는 **기록된 세션의 `Points` 합**이다. 같은 주말·같은 세션 종류는 가장 늦게 분류된 1건만 계산하고, 우승·포디움·카운트백은 본 레이스만 센다(D-31).
- 시즌·세션 조회는 항상 내 것만 대상이다. 남의 ID는 없는 ID와 같다(D-34).

> 팀 이름·색은 저장하지 않고 백엔드의 게임별 정적 카탈로그(`TeamCatalog`)에서 풀어 API에 싣는다(D-33).

---

## 4. 컨텍스트 간 관계

```
Identity(User) ──owns──► AgentDevice ◄── pairs ── AgentPairingCode(1회용)
   │                        │
   │ owns                   │ produces (장치 주인에게 귀속)
   ▼                        ▼
 Track (catalog) ◄──────── Lap ──► LapSector (가변 · D-7)
                            │
                            ▼
                    Ranking (Lap 투영 · TimeTrial·기간별)
```

P7 시즌·세션 계층(User와 Track을 참조하고, `Lap`과는 `SessionKey` 값으로만 이어진다 — 연결 조회는 P8):

```
User ─┬─ Season ──► RaceWeekend ──┐
      │                           ▼  (시즌 대상일 때만 SeasonId·RaceWeekendId)
      └──────────────────────► GameSession ──► SessionResult ──► SessionResultTyreStint
                                    │
                                    └─► Track (catalog)
```

---

## 5. 도메인 이벤트 (Domain Events)

Telemetry 컨텍스트에서 발생하는 도메인 이벤트 (Agent가 생성 → Backend가 소비):

| 이벤트 | 의미 | MVP |
|---|---|---|
| `SessionStarted` | 게임 세션(주행 시작) 감지 | ✅ |
| `LapStarted` | 새 랩 시작 | ✅ |
| `SectorCompleted` | 섹터 통과 | ✅ (선택 전송) |
| `LapFinished` | 랩 완주 (랩타임·섹터·유효성 확정) — **핵심** | ✅ |
| `SessionEnded` | 게임 세션 종료 | ✅ |
| `SessionClassified` | 게임 세션의 **최종 순위표 1건**(전 드라이버 결과 + 세션 맥락, D-28). 세션당 한 번만 보낸다 | ✅ (P7) |

Backend 내부 도메인 이벤트(영속화 후 발생, App 브로드캐스트 트리거):

| 이벤트 | 트리거 |
|---|---|
| `LapRecorded` | 유효 랩이 DB에 저장됨 |
| `RankingChanged` | 저장 결과 TOP10 순위 변동 |
| `PersonalBestAchieved` | 해당 사용자 개인 최고 갱신 |

> 이벤트 payload 계약은 [05-signalr-design.md](./05-signalr-design.md) 및 [06-telemetry-design.md](./06-telemetry-design.md)에서 정의.

---

## 6. 확정된 결정 (반영 완료)

- **D-25 ✅** 개인 모드: 랩 귀속 = 계정에 연결된 Agent 장치의 주인 (~~D-1 멀티스토어, D-2 체크인 세션~~ 대체)
- **D-26 ✅** Agent 계정 연결 = 1회용 연결 코드 → 장치별 키
- **D-28 ✅** 세션 결과 수집 = 세션당 최종 순위표 1건(`SessionClassified`)
- **D-29 ✅** 시즌·주말·세션 식별 = 게임 링크 식별자(시즌 대상 모드만), 세션 키 `link:`/`uid:`
- **D-30 ✅** Sessions = 최종 순위가 확정된 세션만, Time Trial 제외
- **D-31 ✅** Standings = 기록된 세션 점수 합, 우승·카운트백은 본 레이스만
- **D-32 ✅** 시즌 안의 드라이버 식별 = `player` → `driver:{id}` → `name:{이름}#{번호}`
- **D-33 ✅** 팀 이름·색 = 백엔드 정적 카탈로그
- **D-34 ✅** 남의 시즌·세션 조회 = 404
- **D-5 ✅** Car/차량 개념 MVP 제외 (Track 단위 랭킹)
- **D-7 ✅** 섹터 = 가변 `LapSector`
- **D-8 ✅** 랭킹 = 일/월/연 기간 (경계 타임존 = D-27 서버 설정)
- **D-15 ✅** 무효 랩 보존 + 랭킹 제외
- **D-16 ✅** SessionType 구분, 랭킹 = Time Trial만
