# 03 · Entity Design — ERD · 공통 규약

> Status: **Design (미승인)** · Last Updated: 2026-10-18 (User 프로필 설정 열 반영 — D-39, 앞서 P7 시즌·세션·P6 개인 모드 반영)
> 대상: Backend (EF Core, Code First, PostgreSQL). 현재 구현 범위 Entity만 정의한다.
> P6에서 `Store`·`SimRig`·`DrivingSession`을 제거하고 `AgentDevice`·`AgentPairingCode`를 추가했다(D-25, [11](./11-personal-mode.md)).
> P7에서 `Season`·`RaceWeekend`·`GameSession`·`SessionResult`·`SessionResultTyreStint` 5종과 `laps.session_key`를 추가했다(D-28~34, [12](./12-seasons-sessions.md) §4).

---

## 1. 공통 설계 규약 (모든 Entity)

헌장 Database Rules 반영:

| 규약 | 결정(안) |
|---|---|
| Primary Key | **`Guid` (UUID v7)** — 분산 생성/외부 노출 안전. 순차성 위해 v7. (D-6 확정) |
| 멀티게임 | 모든 게임 종속 데이터는 `GameCode`를 보유. F1 전용 가정 금지(가변 섹터 등) — D-7/D-16 확정 |
| 공통 시간 | `CreatedAt` (UTC), `UpdatedAt` (UTC, nullable) 모든 Entity 포함 |
| Soft Delete | `IsDeleted` (bool) + 글로벌 쿼리 필터로 자동 제외 |
| 시간대 | **모든 시각은 UTC 저장.** 표시 변환은 App 책임 |
| Nullable | Nullable Reference Types 활성, DB 제약과 일치 |
| 명명 | Entity=PascalCase, 테이블/컬럼=snake_case (EF 규약 매핑) |
| unique index + soft delete (P7) | 시즌·세션 계열(새 엔티티 5종)의 **모든 unique index는 `is_deleted = false` 필터**(PostgreSQL 부분 인덱스)를 단다. 지워진 행 때문에 같은 키의 새 행 삽입이 매번 unique 위반으로 실패하지 않게 하기 위해서다(12 §0·§4.1) |
| 지우기 (P7) | 새 엔티티의 부모-자식 컬렉션에서 `Remove`·`Clear`를 쓰지 않는다(필수 FK + `Cascade`라 EF가 실제 삭제를 한다). 지우기는 항상 `IsDeleted = true` + `UpdatedAt` 직접 설정 |
| 키 생성 (P7) | 새 엔티티 5종의 `Id`는 `ValueGeneratedNever()`(애플리케이션이 UUID v7을 채움). 추적 중인 부모에 Id가 채워진 새 자식을 붙일 때 EF가 INSERT 대신 UPDATE를 보내지 않게 한다(12 §4.5) |

**공통 베이스 (개념)**

```
abstract Entity
    Id: Guid (PK)
    CreatedAt: DateTime (UTC)
    UpdatedAt: DateTime? (UTC)
    IsDeleted: bool = false
```

> Lap 등 **불변(immutable) 기록성 Entity**도 감사(audit) 목적상 공통 필드는 유지하되,
> 생성 후 값 변경은 하지 않는다. (무효화는 별도 플래그로)

---

## 2. ERD

```
┌──────────────┐1       *┌────────────────┐        ┌──────────────────┐
│    User      │─────────│  AgentDevice   │        │ AgentPairingCode │
│──────────────│         │────────────────│        │──────────────────│
│ Id (PK)      │         │ Id (PK)        │        │ Id (PK)          │
│ Email (uq)   │         │ UserId (FK)    │        │ UserId (FK)      │
│ PasswordHash │         │ Name           │        │ CodeHash (uq)    │
│ DisplayName  │         │ ApiKeyHash(uq) │        │ ExpiresAt (UTC)  │
│ IsDeleted    │         │ LastSeenAt     │        │ ConsumedAt (null)│
│ CreatedAt    │         │ IsDeleted      │        │ IsDeleted        │
└──────┬───────┘         └───────┬────────┘        └─────────┬────────┘
       │1                        │1                          │*
       │                         │                           └── User(1) (UserId FK)
       │*                        │*
┌──────┴─────────────────────────┴──┐        ┌──────────────┐
│               Lap                 │*      1│    Track     │
│───────────────────────────────────│────────│──────────────│
│ Id (PK)                           │        │ Id (PK)      │
│ AgentDeviceId (FK)                │        │ GameCode     │
│ UserId (FK)                       │        │ GameTrackId  │
│ TrackId (FK)                      │        │ Name         │
│ GameCode                          │        │ (uq: GameCode│
│ SessionType (enum)                │        │   +GameTrackId)│
│ LapNumber                         │        └──────────────┘
│ LapTimeMs (int)                   │
│ IsValid (bool)                    │1
│ IsInvalidatedManually (bool)      │
│ IsRankingEligible (bool)          │*
│ SetAt (UTC)                       │──┐
│ CreatedAt                         │  │ 1
└───────────────────────────────────┘  │
                                       │*
                               ┌───────┴────────┐
                               │   LapSector    │   ◄── 가변 섹터(D-7): 게임별 섹터 수 상이
                               │────────────────│
                               │ Id (PK)        │
                               │ LapId (FK)     │
                               │ SectorNumber   │  (1..N)
                               │ SectorTimeMs   │
                               │ (uq: LapId+No) │
                               └────────────────┘

(별도) ProcessedEvent(EventId PK) — 인입 멱등 원장. BaseEntity 아님.
```

**P7 시즌·세션 계층** (모두 `BaseEntity`. FK는 전부 `Restrict`, 결과·스틴트 컬렉션만 `Cascade`이며 실제 삭제는 하지 않는다)

```
User(1) ──< Season          (UserId, GameCode, SeasonLinkId)            uq (필터)
                └──< RaceWeekend   (SeasonId, WeekendLinkId, TrackId→Track)   uq (필터)

User(1) ──< GameSession     (UserId, AgentDeviceId, SessionKey, TrackId→Track,
                │            SeasonId?, RaceWeekendId?)                       uq (UserId, GameCode, SessionKey) (필터)
                └──< SessionResult            (GameSessionId, CarIndex)       uq (필터)
                        └──< SessionResultTyreStint  (SessionResultId, StintNumber)

Lap.SessionKey  ·····  GameSession.SessionKey     (값으로만 이어진다 — 연결 조회는 P8)
```

---

## 3. Entity 상세

### 3.1 User

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| Email | string(256) | Unique, NotNull | 로그인 식별자 |
| PasswordHash | string | NotNull | BCrypt |
| DisplayName | string(50) | NotNull | 랭킹 공개명 |
| ShowOnLeaderboard | bool | NotNull | false면 랭킹에 "익명 드라이버"(D-39). 기존 행 백필 true |
| AvatarTeam | string(8) | Null | 프로필 사진 팀 코드(`AvatarTeamCodes`) |
| PreferredGame | string(20) | NotNull | 기본 `F1_25`. 저장만 |
| Controller / Console / Units | string(20) | NotNull | enum 문자열(`Wheel`·`Pc`·`Metric` 기본). 저장만 |
| TimeZoneId | string(64) | NotNull | IANA, 기본 `Asia/Seoul`. 저장만(랭킹 경계는 D-27) |
| Theme | string(20) | NotNull | `Light`·`Dark`(기본, D-40)·`System`. 열 기본값 `Dark`(`DefaultThemeDark`) |
| CreatedAt / UpdatedAt / IsDeleted | 공통 | | |

내비게이션: `AgentDevices` (P6에서 `Sessions` 대체).
프로필 설정 열(`ShowOnLeaderboard`~`Theme`)은 마이그레이션 `AddUserProfileSettings`(가산적)가 추가했고, `DefaultThemeDark`가 테마 백필 값을 System → Dark로 바꿨다(D-40). DB 기본값은 백필용으로만 쓰고 모델에는 두지 않는다([14](./14-profile-settings.md) §3).

### 3.2 AgentDevice (신규 · D-25)

내 계정에 연결된 PC(Agent 1대).

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| UserId | Guid | FK→User, NotNull, `Restrict` | 장치 주인. 인덱스 `UserId` |
| Name | string(50) | NotNull | 1~50자. 기본값은 Agent가 보낸 컴퓨터 이름 |
| ApiKeyHash | string(64) | **Unique**, NotNull | 장치 키의 SHA-256 hex. 원문은 저장하지 않는다 |
| LastSeenAt | DateTime? | nullable (UTC) | 마지막 이벤트 수신 시각. 쓰기는 1분에 한 번으로 제한 |
| 공통 필드 | | | **연결 해제 = soft delete.** 전역 필터로 인증 조회에서 자동 제외 |

### 3.3 AgentPairingCode (신규 · D-26)

웹에서 발급하는 1회용 연결 코드.

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| UserId | Guid | FK→User, NotNull, `Restrict` | 코드를 발급한 사용자. 인덱스 `UserId` |
| CodeHash | string(64) | **Unique**, NotNull | 정규화(대문자, 하이픈·공백 제거)한 코드의 SHA-256 hex |
| ExpiresAt | DateTime | NotNull (UTC) | 발급 후 10분 |
| ConsumedAt | DateTime? | nullable (UTC) | 값이 있으면 재사용 불가. 소비는 조건부 UPDATE로 원자적 |
| 공통 필드 | | | 새 코드 발급 시 같은 사용자의 미사용 코드는 soft delete로 무효화 |

### 3.4 Track

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| GameCode | string(20) | NotNull | 예: `F1_25` |
| GameTrackId | int | NotNull | 게임 UDP가 주는 트랙 정수 ID |
| Name | string(80) | NotNull | 예: "Silverstone" |
| — | | Unique(GameCode, GameTrackId) | 게임별 트랙 유일성 |

> Track은 마스터 데이터. Migration Seed로 F1 트랙 목록을 미리 채운다(P6에서도 유지).

### 3.5 Lap

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| AgentDeviceId | Guid | FK→AgentDevice, NotNull, `Restrict` | 랩을 올린 장치 (P6에서 `DrivingSessionId` 대체) |
| UserId | Guid | FK→User, NotNull, `Restrict` | 장치 주인(비정규화, 조회 성능). P6부터 FK 보유 |
| TrackId | Guid | FK→Track, NotNull | |
| GameCode | string(20) | NotNull | 이벤트에서 복사(비정규화, 랭킹 필터) |
| SessionType | enum | NotNull | 이벤트에서 복사. 랭킹은 `TimeTrial`만(D-16) |
| LapNumber | int | NotNull | 게임 세션 내 랩 번호 |
| LapTimeMs | int | NotNull | 밀리초 (정수 저장 — 부동소수 오차 회피) |
| IsValid | bool | NotNull | 게임 판정(트랙 이탈 등) |
| IsInvalidatedManually | bool | default false | 수동 무효화 |
| IsRankingEligible | bool | NotNull | **파생 플래그**: IsValid && !수동무효 && SessionType=TimeTrial && !아웃/인랩 |
| SetAt | DateTime | NotNull (UTC) | 랩 완주 시각 |
| SessionKey | string(80) | **nullable** (P7) | 그 랩이 속한 게임 세션의 키(`GameSession.SessionKey`와 같은 규칙). **저장만 하고 P7은 조회에 쓰지 않는다**(인덱스도 P8에서). 기존 행은 null |
| CreatedAt | | | 서버 수신 시각 |

**설계 결정**
- **무효 랩도 저장한다(D-15).** `IsValid=false`나 아웃랩도 기록으로 보관해 개별 조회는 가능하되,
  `IsRankingEligible=false`로 랭킹 집계에서만 제외한다. (Backend가 최종 판정 — 05/06 참조)
- **섹터는 별도 `LapSector` 테이블(D-7).** F1은 3섹터지만, 추후 타 게임은 섹터 수가 다를 수 있어
  가변 구조로 정규화한다. (F1 전용 가정 제거)
- **랩타임은 `int` 밀리초** — `decimal`/`double` 대신 정수로 정밀도·정렬 안정성 확보.
- **귀속(D-25):** `UserId = device.UserId`, `AgentDeviceId = device.Id`. 인입 시점의 장치 주인으로 확정한다.
- **세션 키(P7, 12 §4.6):** `LapFinished`의 `gameMode`·링크 3개로 `SessionKeys.For(...)`를 계산해 `SessionKey`에 저장한다. 옛 Agent가 보낸 랩(필드 없음)은 `uid:{sessionRef}`.
  `sessionRef`가 비었거나 32자를 넘거나 NUL(`\0`)을 품으면 null — 열 제약 위반으로 랩 저장이 매번 실패하지 않게 한다.

**인덱스 (랭킹 쿼리 최적화)**
- `(TrackId, GameCode, SessionType, IsRankingEligible, SetAt)` — 기간별 트랙 랭킹 필터.
- `(UserId, TrackId, LapTimeMs)` — 개인 최고 기록 조회.
- `(TrackId, LapTimeMs) WHERE IsRankingEligible = true` — 랭킹 정렬.

### 3.6 LapSector (D-7)

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| LapId | Guid | FK→Lap, NotNull | |
| SectorNumber | int | NotNull | 1..N (게임별 상이) |
| SectorTimeMs | int | NotNull | 밀리초 |
| — | | Unique(LapId, SectorNumber) | 랩 내 섹터 유일 |

> 조회 최적화를 위해 랩 목록 화면에서는 `Include(LapSectors)`로 함께 로드하거나,
> 상세 조회 시에만 로드하는 정책을 유스케이스별로 선택한다.

### 3.7 ProcessedEvent

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| EventId | Guid | PK | Agent가 생성한 멱등키 |

> 인입 멱등 원장. BaseEntity가 아니며(추가 전용) Soft Delete 대상이 아니다. 상세: [10](./10-realtime-ingest.md).

### 3.8 Season (신규 · P7)

커리어·그랑프리 시즌. 게임의 `SeasonLinkIdentifier`로 묶는다(D-29).

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | `ValueGeneratedNever` |
| UserId | Guid | FK→User, NotNull, `Restrict` | 내비게이션 없음 |
| GameCode | string(20) | NotNull | 예 `F1_25` |
| SeasonLinkId | long | NotNull | 게임의 `uint` 링크 값(0 아님) |
| GameMode | enum(string, 20) | NotNull | 처음 받은 세션의 모드 |
| FirstSessionAt / LastSessionAt | DateTime | NotNull (UTC) | 받은 세션의 `ClassifiedAt` 최소·최대 |

- **Unique** `(UserId, GameCode, SeasonLinkId)` WHERE `is_deleted = false`. 목록 정렬용 인덱스 `(UserId, LastSessionAt)`.

### 3.9 RaceWeekend (신규 · P7)

시즌 안의 그랑프리 주말.

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | `ValueGeneratedNever` |
| SeasonId | Guid | FK→Season, NotNull, `Restrict` | |
| WeekendLinkId | long | NotNull | 0 아님 |
| TrackId | Guid | FK→Track, NotNull, `Restrict` | 처음 받은 세션의 트랙 |
| FirstSessionAt | DateTime | NotNull (UTC) | 라운드 순서 기준 |

- **Unique** `(SeasonId, WeekendLinkId)` WHERE `is_deleted = false`.
- **라운드 번호는 저장하지 않는다.** 시즌 안에서 `FirstSessionAt`, `Id` 순서로 조회 시 계산한다(게임 UDP에 라운드 번호가 없고, 결과가 늦게 도착하면 저장된 번호가 틀어진다).

### 3.10 GameSession (신규 · P7)

최종 순위가 확정된 게임 세션 1건. 시즌 대상이 아니면 `SeasonId`·`RaceWeekendId`가 null이다.

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | `ValueGeneratedNever` |
| UserId | Guid | FK→User, NotNull, `Restrict` | |
| AgentDeviceId | Guid | FK→AgentDevice, NotNull, `Restrict` | 마지막으로 결과를 보낸 장치. **FK만**(내비게이션 없음) — `Lap.AgentDevice`와 같은 soft-delete inner join 함정을 피한다 |
| SeasonId / RaceWeekendId | Guid? | FK `Restrict` | 시즌 대상이 아니면 null |
| GameCode | string(20) | NotNull | |
| SessionKey | string(80) | NotNull | D-29 규칙(`link:…` / `uid:…`) |
| SeasonLinkId / WeekendLinkId / SessionLinkId | long | NotNull | 원본 링크 값(0 가능) |
| SessionRef | string(32) | NotNull | 결과를 받은 게임 세션 UID |
| TrackId | Guid | FK→Track, NotNull, `Restrict` | |
| SessionType | enum(string, 20) | NotNull | 기존 5종(Practice·Qualifying·Race…) |
| SessionKind | enum(string, 30) | NotNull | 상세(Practice1, Qualifying2, SprintShootout1, Race2…) |
| GameMode | enum(string, 20) | NotNull | |
| TotalLaps / AiDifficulty | int | NotNull | |
| IsNetworkGame | bool | NotNull | |
| ClassifiedAt | DateTime | NotNull (UTC) | 이벤트 `occurredAt`(서버 시각 + 5분을 넘으면 그 값으로 자름) |

- **Unique** `(UserId, GameCode, SessionKey)` WHERE `is_deleted = false`. 인덱스: `(UserId, ClassifiedAt)`(목록), `(RaceWeekendId)`, `(SeasonId)`.
- 컬렉션 `Results`(→ `SessionResult`).

### 3.11 SessionResult (신규 · P7)

차 1대(드라이버 1명)의 최종 결과.

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | `ValueGeneratedNever` |
| GameSessionId | Guid | FK→GameSession, NotNull, `Cascade` | |
| CarIndex | int | NotNull | 0부터. 게임 순위표 배열 위치 |
| Position / GridPosition / NumLaps / Points / NumPitStops / NumPenalties | int | NotNull | |
| ResultStatus | enum(string, 20) | NotNull | Finished · DidNotFinish · Disqualified · NotClassified · Retired · Active · Unknown |
| BestLapTimeMs | int | NotNull | 0 = 기록 없음(API에서는 null) |
| TotalRaceTimeMs | int | NotNull | 패널티 제외. 0 = 없음 |
| PenaltiesTimeMs | int | NotNull | |
| DriverKey | string(80) | NotNull | D-32 규칙(`player` / `driver:{id}` / `name:{이름}#{번호}` / `car:{SessionRef}:{carIndex}`) |
| DriverName | string(64) | nullable | 참가자 정보가 없거나 비면 null(표시는 `Car {carIndex+1}`) |
| GameDriverId / TeamId / RaceNumber | int? | nullable | 사람(네트워크)이면 `GameDriverId` null. `TeamId`는 게임 팀 ID |
| IsAiControlled / IsPlayer | bool | NotNull | |

- **Unique** `(GameSessionId, CarIndex)` WHERE `is_deleted = false`. 인덱스 `(GameSessionId, DriverKey)`.
- 컬렉션 `TyreStints`(→ `SessionResultTyreStint`).

### 3.12 SessionResultTyreStint (신규 · P7)

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | `ValueGeneratedNever` |
| SessionResultId | Guid | FK→SessionResult, NotNull, `Cascade` | |
| StintNumber | int | NotNull | 1부터 |
| EndLap | int | NotNull | 그 스틴트가 끝난 랩 |
| VisualCompound | enum(string, 20) | NotNull | Soft · Medium · Hard · Intermediate · Wet · Unknown |
| ActualCompound | string(10) | nullable | 예 `C3`. 게임 중립 문자열 라벨 |

> 스틴트는 P8 화면의 재료지만 최종 순위표는 세션당 한 번만 오므로 P7에서 저장한다(지금 버리면 P7 기간의 세션은 영영 스틴트가 없다).

**재분류 병합 (12 §4.5):** 같은 `SessionKey`로 새 순위표가 오면 `GameSession.ReplaceResults`가 carIndex로 맞춰 **제자리 갱신**한다 — 같은 carIndex의 활성 행은 값을 덮어쓰고(스틴트는 soft delete 후 새로 붙임),
새 순위표에 없는 carIndex의 활성 행은 soft delete, 새 carIndex는 새 행으로 추가한다. "옛 행 soft delete + 같은 carIndex 새 행 INSERT"를 한 번의 `SaveChanges`로 보내면 EF가 INSERT를 UPDATE보다 먼저 보낼 수 있어 필터 unique index가 즉시 위반되기 때문이다.

---

## 4. Ranking — Entity 없음 (Read Model)

Ranking은 테이블을 만들지 않는다. `Lap` + `User` 조인 쿼리로 계산한다.
**기간(period)**은 파라미터로, 일/월/연을 모두 같은 쿼리 형태로 지원한다(D-8).

**TOP10 (개념 쿼리 · 기간 파라미터화)**
```sql
-- 사용자별 [기간] 최고 랭킹적격 랩 → 시간순 상위 10
SELECT u.display_name, MIN(l.lap_time_ms) AS best_ms
FROM lap l JOIN "user" u ON u.id = l.user_id
WHERE l.track_id = @trackId
  AND l.game_code = @gameCode
  AND l.is_ranking_eligible = true          -- SessionType=TimeTrial 포함(D-16), 무효랩 제외(D-15)
  AND l.set_at >= @periodStartUtc           -- daily/monthly/yearly 경계
  AND l.set_at <  @periodEndUtc
GROUP BY u.id, u.display_name
ORDER BY best_ms ASC
LIMIT 10;
```

- **기간 경계(D-8 · D-27):** 일별=설정 타임존 자정~자정, 월별=해당 월, 연도별=해당 연도.
  타임존은 서버 설정 `Ranking:TimeZoneId`(기본 `Asia/Seoul`, 시작 시 검증)로 계산 후 UTC로 변환해 `set_at` 비교.
- **실시간 랭킹(SignalR) 기본 기준 = 월별(D-8a).** 즉 `@periodStart/End`는 "이번 달"로 계산.
- **이름 비공개(D-39):** `u.show_on_leaderboard = false`인 행은 서비스가 표시 이름을 `익명 드라이버`로 바꾼다(순위·기록 그대로).
- **개별 기록 조회(D-16)**는 `is_ranking_eligible` 필터 없이 모든 세션·무효 랩까지 노출.
- **내 트랙 요약(`/me/tracks`):** 내 랩이 1개 이상 있는 트랙별 `lapCount`, `bestValidLapTimeMs`(`IsValid` 랩 중 최소, 세션 유형 무관 —
  랭킹용 PB와 다른 값), `lastSetAt`.

---

## 5. 마이그레이션 & 시드 전략

- **Code First + EF Migration.** 시작 시 자동 Migrate & Seed.
- **Seed 데이터:** Track 마스터(F1 트랙 목록)만. 매장·좌석·개발용 좌석 키 시드는 P6에서 제거됐다.
- Soft Delete 글로벌 필터, UTC 변환 규약을 `DbContext.OnModelCreating`에 일괄 적용.
- **P6 마이그레이션 2건:**
  - `AddAgentDevices` — `agent_devices`·`agent_pairing_codes` 추가(가산적).
  - `PersonalMode` — 기존 `laps`·`lap_sectors`·`processed_events` 행 삭제(귀속할 장치가 없는 로컬 개발·테스트 데이터, 사용자 승인),
    `laps.driving_session_id` 제거 + `laps.agent_device_id`·`user_id` FK 추가, `driving_sessions`·`sim_rigs`·`stores` 삭제. 회원·트랙은 유지.
  - 스펙은 1건이었으나 EF Core 9+가 태스크 사이의 pending model change를 거부해 둘로 나눴다([11](./11-personal-mode.md) §3.4).
- **P7 마이그레이션 1건:** `AddSeasonsAndSessions` — 테이블 5개(`seasons`, `race_weekends`, `game_sessions`, `session_results`, `session_result_tyre_stints`) 생성 + `laps.session_key`(nullable) 추가.
  **가산적**이라 기존 데이터를 바꾸지 않는다. 엔티티·DbSet·`Lap` 변경은 이 마이그레이션과 같은 단계에서 했다(EF Core 9+는 모델과 마이그레이션이 어긋나면 `MigrateAsync`에서 예외).

---

## 6. 확정된 결정 (반영 완료)

- **D-25 ✅** 개인 모드: `Store`·`SimRig`·`DrivingSession` 제거, `AgentDevice` 추가 (~~D-1 `StoreId`~~ 대체)
- **D-26 ✅** `AgentPairingCode` — 1회용 연결 코드
- **D-27 ✅** 랭킹 기간 경계 타임존 = 서버 설정 (~~`Store.TimeZoneId`~~ 대체)
- **D-29 ✅** 시즌·주말·세션 = 게임 링크 식별자, `GameSession.SessionKey` + `Lap.SessionKey`
- **D-30 ✅** `GameSession`은 최종 순위가 확정된 세션만, Time Trial 제외
- **D-32 ✅** `SessionResult.DriverKey` 규칙
- **D-6 ✅** PK = `Guid(UUID v7)`
- **D-7 ✅** 섹터 = 별도 `LapSector` 테이블(가변, 타 게임 대비)
- **D-8 ✅** 랭킹 기간 = 일/월/연
- **D-15 ✅** 무효 랩 저장 + `IsRankingEligible`로 랭킹 제외
- **D-16 ✅** `SessionType` 저장, 랭킹은 TimeTrial만, 타 세션 개별 조회 가능
