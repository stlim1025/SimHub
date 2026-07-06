# 02 · Domain Design — Bounded Context

> Status: **Design (미승인)** · Last Updated: 2026-07-06

---

## 1. 목적

플랫폼 전체의 **Bounded Context 지도**를 그리고, 그중 **MVP 범위 도메인**을 상세화한다.
장기 확장을 고려해 경계를 미리 나누되, MVP에서는 소수 컨텍스트만 구현한다. (설계는 확장 대비, 구현은 YAGNI)

---

## 2. 전체 Bounded Context 지도

```
┌───────────────────────────────────────────────────────────────────────┐
│                          SimCenter Platform                            │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │  Identity    │   │  Facility    │   │  Telemetry   │  ◄── MVP 핵심   │
│  │  & Access    │   │ (Store/Rig)  │   │ (Session/Lap)│                │
│  └──────────────┘   └──────────────┘   └──────────────┘                │
│         MVP              MVP (최소)            MVP                       │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │  Ranking     │   │ Reservation  │   │ Competition  │                │
│  │ (Read Model) │   │   (예약)      │   │  (대회/리그)  │                │
│  └──────────────┘   └──────────────┘   └──────────────┘                │
│      MVP(조회)          Future             Future                       │
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
| **Identity & Access** | 사용자, 인증(JWT), Driver Profile 기초 | ✅ (최소) |
| **Facility** | 매장(Store), 시뮬레이터 좌석(SimRig), 게임/트랙 카탈로그 | ✅ (최소) |
| **Telemetry** | 주행 세션(DrivingSession), 랩(Lap), 섹터(Sector) 기록 | ✅ |
| **Ranking** | 랩 기록의 조회 모델(TOP10, 개인 기록) — 읽기 전용 투영 | ✅ (조회) |
| Reservation | 예약, 좌석 스케줄 | ❌ Future |
| Competition | 대회/리그/시즌 | ❌ Future |
| Community | 게시글, 피드 | ❌ Future |
| Membership | 등급, XP, Badge, Achievement | ❌ Future |
| Analytics | 매장 운영 통계 | ❌ Future |
| **Lap Telemetry Trace** | 상세 텔레메트리(스로틀/브레이크/스티어/타이어 마모·온도) 랩 단위 조회 | ❌ Future ([09](./09-lap-telemetry-trace.md)) |

---

## 3. MVP 도메인 상세

### 3.1 Identity & Access

**핵심 개념**

- `User` — 앱에 로그인하는 사람. 랩 기록의 귀속 대상.
  - 속성: 식별자, Email, PasswordHash, DisplayName(랭킹 표시명)
  - MVP 인증: Email + Password → JWT 발급 (소셜 로그인 등은 Future)

**불변식**
- DisplayName은 랭킹에 공개되므로 필수. Email은 로그인 식별자로 유일.

> **미결정 D-2 연관:** "누가 운전했는가"를 랩에 연결하는 방식은 이 컨텍스트와 Telemetry의 접점이다. → 3.3 참조.

### 3.2 Facility

**핵심 개념**

- `Store` — 물리 매장. (MVP는 단일 매장이나 Entity에 `StoreId` 선반영 권장 → D-1)
- `SimRig` — 매장 내 개별 시뮬레이터 좌석. Agent 1대 = SimRig 1개에 대응.
  - Agent는 자신이 어떤 SimRig인지 설정(config)으로 안다. (`RigCode`)
- `Track` — 게임 내 트랙 카탈로그. 랩 기록의 비교 기준.
  - 속성: GameCode(예: `F1_24`), TrackId(게임 내부 코드), Name
- `Car` — (선택) F1은 팀/차량 개념. **MVP는 Track 단위 랭킹만** 하므로 Car는 Future로 보류. → D-5

**불변식**
- 랩은 반드시 하나의 `Track`을 참조한다. (동일 트랙끼리만 순위 비교 가능)
- `SimRig`는 정확히 하나의 `Store`에 속한다.

### 3.3 Telemetry (MVP 핵심)

**핵심 개념**

- `DrivingSession` — "특정 사용자가 특정 SimRig에서 주행을 시작~종료한 구간".
  - **랩-사용자 귀속의 핵심 장치.** Agent 텔레메트리는 SimRig 기준으로 들어오고,
    이 세션이 `UserId ↔ SimRig` 를 시간 구간으로 연결한다.
  - `SessionType`(TimeTrial/Practice/Qualifying/Race/…)을 보유한다. 랭킹 집계 대상 구분에 사용(D-16).
  - 상태: `Active` → `Ended`
- `Lap` — 완주한 한 바퀴의 기록.
  - 속성: LapTime(ms), IsValid, IsRankingEligible, SessionType, LapNumber, 소속 Session/User/Track
  - **무효 랩도 보존**한다(D-15). 랭킹에서만 제외하고 개별 조회는 허용.
- `LapSector` — 랩을 구간으로 나눈 기록. **게임별 섹터 수가 다를 수 있어 가변 자식 엔티티**로 둔다(D-7).

**랩-사용자 귀속 흐름 (권장안, D-2)**

```
① 사용자가 앱에서 SimRig 체크인 (QR/좌석코드 입력)
        │  POST /sessions/check-in { rigCode }
        ▼
② Backend가 DrivingSession(Active) 생성 (UserId ↔ SimRigId 바인딩)
        ▼
③ Agent가 해당 SimRig에서 LapFinished 이벤트 전송 (RigCode 포함, UserId 모름)
        ▼
④ Backend가 "그 시각 그 Rig의 Active 세션"을 찾아 Lap.UserId 결정
        ▼
⑤ 세션 종료(체크아웃 or 타임아웃) → DrivingSession = Ended
```

> 이 방식의 장점: Agent는 사용자를 전혀 몰라도 되어 **관심사 분리**가 유지된다.
> Agent 재설치·교체 시에도 인증 정보가 필요 없다. **단, 이 설계는 승인 필요(D-2).**

**불변식**
- 하나의 SimRig에는 동시에 **최대 1개**의 `Active` DrivingSession만 존재한다.
- `Lap`은 생성 후 불변(immutable). 정정이 필요하면 무효화(soft) 처리.
- `IsValid=false`(트랙 이탈 등)인 랩은 랭킹 집계에서 제외한다.

### 3.4 Ranking (읽기 전용 투영)

**성격:** Ranking은 자체 쓰기 모델을 갖지 않는다. **Lap 데이터에 대한 조회/투영(Read Model)**이다.

- `RankingTop10` — 특정 Track·기간에서 `IsRankingEligible=true`(= 유효 + **Time Trial** + 정상 랩)인
  랩 중 **사용자별 최고 기록**을 시간 오름차순 정렬한 상위 10.
- **기간(period)**: 일별 / 월별 / 연도별 지원(D-8). **실시간 랭킹(SignalR)의 기본 기준은 월별**(D-8a).
  기간 경계는 매장 로컬 타임존 기준(일별=자정, 월별=매월 1일, 연도별=1월 1일).
- `MyLapRecord` — 특정 사용자의 랩 기록. **모든 세션·무효 랩까지** 조회 가능(개인 최고 + 최근 기록).

> MVP는 실시간 쿼리로 충분. 성능 이슈 시 캐시/materialized view/Redis 도입은 Future(헌장 성능 규칙 준수).

---

## 4. 컨텍스트 간 관계 (MVP)

```
Identity(User) ─────┐
                    │ owns
Facility(Store) ──► SimRig ──► [DrivingSession] ◄── binds ── User
   │                              │
   │ catalog                      │ produces
   ▼                              ▼
 Track ◄──────────────────────── Lap ──► LapSector (가변 · D-7)
                                  │
                                  ▼
                          Ranking (Lap 투영 · TimeTrial·기간별)
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

Backend 내부 도메인 이벤트(영속화 후 발생, App 브로드캐스트 트리거):

| 이벤트 | 트리거 |
|---|---|
| `LapRecorded` | 유효 랩이 DB에 저장됨 |
| `RankingChanged` | 저장 결과 TOP10 순위 변동 |
| `PersonalBestAchieved` | 해당 사용자 개인 최고 갱신 |

> 이벤트 payload 계약은 [05-signalr-design.md](./05-signalr-design.md) 및 [06-telemetry-design.md](./06-telemetry-design.md)에서 정의.

---

## 6. 확정된 결정 (반영 완료)

- **D-1 ✅** 멀티스토어 `StoreId` 선반영
- **D-2 ✅** 랩-사용자 귀속 = 체크인 세션 방식
- **D-5 ✅** Car/차량 개념 MVP 제외 (Track 단위 랭킹)
- **D-7 ✅** 섹터 = 가변 `LapSector`
- **D-8 ✅** 랭킹 = 일/월/연 기간
- **D-15 ✅** 무효 랩 보존 + 랭킹 제외
- **D-16 ✅** SessionType 구분, 랭킹 = Time Trial만
