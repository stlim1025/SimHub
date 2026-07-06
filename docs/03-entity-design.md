# 03 · Entity Design — ERD · 공통 규약

> Status: **Design (미승인)** · Last Updated: 2026-07-06
> 대상: Backend (EF Core, Code First, PostgreSQL). MVP 범위 Entity만 정의한다.

---

## 1. 공통 설계 규약 (모든 Entity)

헌장 Database Rules 반영:

| 규약 | 결정(안) |
|---|---|
| Primary Key | **`Guid` (UUID v7)** — 분산 생성/멀티스토어/외부 노출 안전. 순차성 위해 v7. (D-6 확정) |
| 멀티게임 | 모든 게임 종속 데이터는 `GameCode`를 보유. F1 전용 가정 금지(가변 섹터 등) — D-7/D-16 확정 |
| 공통 시간 | `CreatedAt` (UTC), `UpdatedAt` (UTC, nullable) 모든 Entity 포함 |
| Soft Delete | `IsDeleted` (bool) + 글로벌 쿼리 필터로 자동 제외 |
| 시간대 | **모든 시각은 UTC 저장.** 표시 변환은 App 책임 |
| Nullable | Nullable Reference Types 활성, DB 제약과 일치 |
| 명명 | Entity=PascalCase, 테이블/컬럼=snake_case (EF 규약 매핑) |

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

## 2. MVP ERD

```
┌──────────────┐         ┌──────────────┐
│    Store     │1       *│   SimRig     │
│──────────────│─────────│──────────────│
│ Id (PK)      │         │ Id (PK)      │
│ Name         │         │ StoreId (FK) │
│ IsDeleted    │         │ RigCode (uq) │  ◄── Agent config가 참조
│ CreatedAt    │         │ DisplayName  │
└──────────────┘         │ IsDeleted    │
                         └──────┬───────┘
                                │1
                                │
                                │*
┌──────────────┐         ┌──────┴────────────┐        ┌──────────────┐
│    User      │1       *│  DrivingSession   │*      1│    (User)    │
│──────────────│─────────│───────────────────│────────│  (binding)   │
│ Id (PK)      │         │ Id (PK)           │        └──────────────┘
│ Email (uq)   │         │ UserId (FK)       │
│ PasswordHash │         │ SimRigId (FK)     │
│ DisplayName  │         │ StoreId (FK)      │
│ IsDeleted    │         │ GameCode          │
│ CreatedAt    │         │ Status(Active/End)│
└──────┬───────┘         │ StartedAt        │
       │1                │ EndedAt (null)   │
       │                 └─────────┬─────────┘
       │*                          │1
       │              ┌────────────┘*
       │              │
┌──────┴──────────────┴──────┐        ┌──────────────┐
│           Lap              │*      1│    Track     │
│────────────────────────────│────────│──────────────│
│ Id (PK)                    │        │ Id (PK)      │
│ DrivingSessionId (FK)      │        │ GameCode     │
│ UserId (FK)                │        │ GameTrackId  │
│ TrackId (FK)               │        │ Name         │
│ GameCode                   │        │ (uq: GameCode│
│ SessionType (enum)         │        │   +GameTrackId)│
│ LapNumber                  │        └──────────────┘
│ LapTimeMs (int)            │
│ IsValid (bool)             │1
│ IsInvalidatedManually(bool)│
│ IsRankingEligible (bool)   │*
│ SetAt (UTC)                │──┐
│ CreatedAt                  │  │ 1
└────────────────────────────┘  │
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
```

---

## 3. Entity 상세

### 3.1 User

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| Email | string(256) | Unique, NotNull | 로그인 식별자 |
| PasswordHash | string | NotNull | ASP.NET Identity Hasher 또는 BCrypt |
| DisplayName | string(50) | NotNull | 랭킹 공개명 |
| CreatedAt / UpdatedAt / IsDeleted | 공통 | | |

### 3.2 Store

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| Name | string(100) | NotNull | |
| 공통 필드 | | | MVP는 시드로 단일 매장 1개 |

### 3.3 SimRig

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| StoreId | Guid | FK→Store, NotNull | |
| RigCode | string(30) | **Unique** | Agent config·체크인 QR이 참조하는 코드 (예: `A-01`) |
| DisplayName | string(50) | NotNull | UI 표시 (예: "1번 좌석") |
| 공통 필드 | | | |

### 3.4 Track

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| GameCode | string(20) | NotNull | 예: `F1_24` |
| GameTrackId | int | NotNull | 게임 UDP가 주는 트랙 정수 ID |
| Name | string(80) | NotNull | 예: "Silverstone" |
| — | | Unique(GameCode, GameTrackId) | 게임별 트랙 유일성 |

> Track은 마스터 데이터. Migration Seed로 F1 트랙 목록을 미리 채운다.

### 3.5 DrivingSession

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| UserId | Guid | FK→User, NotNull | 체크인한 사용자 |
| SimRigId | Guid | FK→SimRig, NotNull | |
| StoreId | Guid | FK→Store, NotNull | 조회 편의(비정규화) |
| GameCode | string(20) | NotNull | 예: `F1_25` (D-14) |
| SessionType | enum | NotNull | 게임 세션 모드(D-16). F1: TimeTrial/Practice/Qualifying/Race/Unknown |
| Status | enum(Active/Ended) | NotNull | |
| StartedAt | DateTime | NotNull (UTC) | |
| EndedAt | DateTime? | nullable | |
| 공통 필드 | | | |

**제약/인덱스**
- **부분 유니크 인덱스:** `(SimRigId) WHERE Status = Active` → Rig당 활성 세션 1개 보장.
- 인덱스: `(SimRigId, Status, StartedAt)` — Agent 이벤트의 세션 매칭 조회용.

### 3.6 Lap

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| DrivingSessionId | Guid | FK→DrivingSession, NotNull | |
| UserId | Guid | FK→User, NotNull | 세션에서 확정(비정규화, 조회 성능) |
| TrackId | Guid | FK→Track, NotNull | |
| GameCode | string(20) | NotNull | 세션에서 복사(비정규화, 랭킹 필터) |
| SessionType | enum | NotNull | 세션에서 복사(비정규화). 랭킹은 `TimeTrial`만(D-16) |
| LapNumber | int | NotNull | 세션 내 랩 번호 |
| LapTimeMs | int | NotNull | 밀리초 (정수 저장 — 부동소수 오차 회피) |
| IsValid | bool | NotNull | 게임 판정(트랙 이탈 등) |
| IsInvalidatedManually | bool | default false | 운영자 수동 무효화 |
| IsRankingEligible | bool | NotNull | **파생 플래그**: IsValid && !수동무효 && SessionType=TimeTrial && !아웃/인랩 |
| SetAt | DateTime | NotNull (UTC) | 랩 완주 시각 |
| CreatedAt | | | 서버 수신 시각 |

**설계 결정**
- **무효 랩도 저장한다(D-15).** `IsValid=false`나 아웃랩도 기록으로 보관해 개별 조회는 가능하되,
  `IsRankingEligible=false`로 랭킹 집계에서만 제외한다. (Backend가 최종 판정 — 05/06 참조)
- **섹터는 별도 `LapSector` 테이블(D-7).** F1은 3섹터지만, 추후 타 게임은 섹터 수가 다를 수 있어
  가변 구조로 정규화한다. (F1 전용 가정 제거)
- **랩타임은 `int` 밀리초** — `decimal`/`double` 대신 정수로 정밀도·정렬 안정성 확보.

**인덱스 (랭킹 쿼리 최적화)**
- `(TrackId, GameCode, SessionType, IsRankingEligible, SetAt)` — 기간별 트랙 랭킹 필터.
- `(UserId, TrackId, LapTimeMs)` — 개인 최고 기록 조회.
- `(TrackId, LapTimeMs) WHERE IsRankingEligible = true` — 랭킹 정렬.

### 3.7 LapSector (신규 · D-7)

| 컬럼 | 타입 | 제약 | 비고 |
|---|---|---|---|
| Id | Guid | PK | |
| LapId | Guid | FK→Lap, NotNull | |
| SectorNumber | int | NotNull | 1..N (게임별 상이) |
| SectorTimeMs | int | NotNull | 밀리초 |
| — | | Unique(LapId, SectorNumber) | 랩 내 섹터 유일 |

> 조회 최적화를 위해 랩 목록 화면에서는 `Include(LapSectors)`로 함께 로드하거나,
> 상세 조회 시에만 로드하는 정책을 유스케이스별로 선택한다.

---

## 4. Ranking — Entity 없음 (Read Model)

Ranking은 테이블을 만들지 않는다. `Lap` + `User` 조인 쿼리로 계산한다.
**기간(period)**은 파라미터로, MVP는 daily. 월별/연도별도 동일 쿼리 형태로 확장한다(D-8).

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

- **기간 경계(D-8):** 일별=매장 로컬 타임존 자정~자정, 월별=해당 월, 연도별=해당 연도.
  경계는 매장 로컬 타임존으로 계산 후 UTC로 변환해 `set_at` 비교.
- **실시간 랭킹(SignalR) 기본 기준 = 월별(D-8a).** 즉 `@periodStart/End`는 "이번 달"로 계산.
- **개별 기록 조회(D-16)**는 `is_ranking_eligible` 필터 없이 모든 세션·무효 랩까지 노출.

---

## 5. 마이그레이션 & 시드 전략

- **Code First + EF Migration.** 초기 마이그레이션에 스키마 생성.
- **Seed 데이터:** Store 1개, SimRig N개, Track 마스터(F1 트랙 목록). 별도 Seeder로 관리.
- Soft Delete 글로벌 필터, UTC 변환 규약을 `DbContext.OnModelCreating`에 일괄 적용.

---

## 6. 확정된 결정 (반영 완료)

- **D-1 ✅** 멀티스토어 `StoreId` 선반영 (이 ERD 반영됨)
- **D-6 ✅** PK = `Guid(UUID v7)`
- **D-7 ✅** 섹터 = 별도 `LapSector` 테이블(가변, 타 게임 대비)
- **D-8 ✅** 랭킹 기간 = 일/월/연, 일별 경계 = 매장 로컬 자정
- **D-15 ✅** 무효 랩 저장 + `IsRankingEligible`로 랭킹 제외
- **D-16 ✅** `SessionType` 저장, 랭킹은 TimeTrial만, 타 세션 개별 조회 가능
