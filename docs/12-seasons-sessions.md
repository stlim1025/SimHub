# 12 · Seasons & Sessions (Phase 7) — 시즌·세션 결과 수집

> Status: **Implemented (2026-10-18)** · Last Updated: 2026-10-18 (설계 2026-10-17, 리뷰 + 수정본 검증 반영)
> F1 25의 커리어·그랑프리 기록을 **시즌 → 그랑프리 주말 → 세션**으로 자동으로 묶고, AI를 포함한 **모든 드라이버의 세션 결과**와
> **기록된 점수 기준 Standings**를 보여 준다. 목표 화면은 F1Laps의 Seasons(Season · Results · Standings 탭)와 Sessions 목록이다.
> 결정은 [08](./08-open-decisions.md)에 D-28~D-34로 기록한다. 로드맵 위치는 [11](./11-personal-mode.md) §0. 리뷰 반영 내역은 §13.
> 구현 중 달라진 점: 읽기 전용 저장소 포트를 쓰기 포트와 분리했고(`ISeasonQueryRepository`·`IGameSessionQueryRepository`), NUL 문자·`raceNumber` 검증·Agent 시간값 보정·빈 순위표 무시 규칙이 추가됐다.
> 실측 메시지 크기와 Flutter 이름도 설계와 조금 다르다 — §14. 게임으로 확인해야 하는 가정(§3.3)은 아직 **미확인**이다.

---

## 0. 배경

- P6까지 Agent는 **내 차의 랩만** 서버로 보낸다(`LapFinished`). 세션 단위 기록, 다른 드라이버의 결과, 시즌 묶음이 없다.
- F1 25 UDP에는 이를 위한 데이터가 이미 있다. F1Game.UDP 26.0.0에서 리플렉션으로 **필드와 타입을 직접 확인**했다(§3).
- 헌장 원칙은 그대로 지킨다: **raw 패킷을 서버로 보내지 않는다.** Agent가 세션 끝에 받은 최종 순위표를 참가자 정보와 합쳐
  **세션당 도메인 이벤트 1건**(`SessionClassified`)으로 만든다(D-28).
- **실패 원칙:** Agent는 허브 예외를 "일시 장애"로 보고 같은 Outbox 항목을 계속 재시도한다(그 뒤의 랩도 대기). 따라서 이 기능은
  **같은 입력에 항상 실패하는 서버 예외를 만들지 않도록** 설계한다 — 영구 무효는 Reject, 모르는 값은 관대하게 해석, 크기는 전송 전에 제한(§5.5, §6).

---

## 1. 범위

| 포함 (P7) | 제외 (후속 단계) |
|---|---|
| Agent: Participants(4)·Final Classification(8) 패킷 파싱, Session 패킷 필드 추가, `SessionClassified` 이벤트, `LapFinished`에 세션 맥락 필드 추가 | 랩별 랩타임·타이어 마모·패널티 상세(P8) — Session History(11)·Car Damage(10) 파싱 |
| Backend: `Season` · `RaceWeekend` · `GameSession` · `SessionResult` · `SessionResultTyreStint` 엔티티, `Lap.SessionKey`, 마이그레이션 1건 | 그랑프리 주말 상세 화면 · 세션 Details 탭(P8) |
| 인입: `SessionClassified` 저장(시즌·주말·세션 업서트, 재분류 시 병합) | 랩 ↔ 세션 연결 조회(P8). P7은 `Lap.SessionKey` 저장만 한다(§4.6) |
| 조회 API: 시즌 목록·상세(라운드·Standings·결과표), 세션 목록·상세 | 시즌 이름 변경, 시즌 삭제·숨기기 |
| Flutter: Seasons · 시즌 상세(3탭) · Sessions · 세션 결과 화면, 메뉴 추가, 페이지 바 공용화 | Dashboard의 시즌 카드, 실시간 갱신(SignalR) |
| 계약(`shared/`)·헌장·관련 문서 갱신 | Time Trial 세션 목록(Laps·Leaderboard가 담당), Agent Outbox의 독성 항목(dead-letter) 처리 |

---

## 2. 결정 ([08](./08-open-decisions.md)에 기록)

> 사용자가 자동 모드(질문 없이 진행)를 요청해, 아래는 **권장안으로 정한 기본값**이다. 바꾸려면 구현 전에 알려 주면 된다.

### D-28. 세션 결과 수집 = 세션당 최종 순위표 1건(`SessionClassified`)
- Agent가 Final Classification 패킷을 받으면, 같은 세션의 Session 맥락(모드·링크 식별자·트랙)과 Participants(이름·팀·AI 여부)를
  **차 번호(carIndex)로 합쳐** 이벤트 1건으로 보낸다. 같은 `SessionRef`로는 한 번만 보낸다.
- **검토한 대안:**
  (a) Participants·Classification을 각각 이벤트로 보내고 서버에서 합치기 — 패킷 중계에 가깝고, 두 이벤트의 순서·누락을 서버가 다뤄야 한다.
  (b) `SessionStarted`에 맥락을 싣고 `SessionClassified`에는 결과만 — 이벤트끼리 의존이 생긴다(재접속·재개 시 깨지기 쉽다).
- 채택안은 **이벤트 하나가 자기 완결적**이라 순서·재전송·중복에 강하다. 크기는 22대 기준 약 10KB다(§5.5).

### D-29. 시즌·주말·세션 식별 = 게임 링크 식별자(시즌 대상 모드에서만)
- `SeasonLinkIdentifier` · `WeekendLinkIdentifier` · `SessionLinkIdentifier`(모두 `uint`, "세이브가 바뀌어도 유지")로 묶는다.
- **시즌 대상:** 게임 모드가 커리어 4종(Driver Career · My Team · Online Career · Challenge Career) 또는 Grand Prix이고,
  시즌·주말 링크가 모두 0이 아닐 때. 그 밖의 세션(온라인 로비, 스토리 등)은 **시즌 없이** Sessions 목록에만 나온다.
- **세션 키:** 시즌 대상이고 세션 링크가 0이 아니면 `link:{season}:{weekend}:{session}`, 그 밖에는 `uid:{SessionRef}`.
  링크 값의 의미를 확인하지 못한 모드(온라인 등)에서 서로 다른 세션이 같은 키로 덮이지 않게 하기 위해서다. 사용자·게임별로 유일하다.
- **같은 키로 다시 분류되면 최신 결과로 병합한다**(세션 재시작, 세이브 불러온 뒤 다시 완주). 단, 저장된 세션과 **트랙 또는 세션 종류가 다르면**
  같은 세션이 아니라고 보고 `uid:` 키로 따로 저장한다(경고 로그). 받은 시각이 저장된 것보다 이르면 무시한다.
- 랩도 같은 규칙으로 `Lap.SessionKey`를 저장해, P8에서 같은 키로 세션과 연결한다(§4.6).

### D-30. Sessions 목록 = 최종 순위가 확정된 세션만, Time Trial 제외
- 최종 순위표를 받은 세션만 `GameSession`이 된다. 중간에 나간 세션은 목록에 없다.
- Time Trial은 Laps·Leaderboard가 담당한다. Agent는 Time Trial 세션(`SessionType.TimeTrial`)의 순위표를 보내지 않고,
  **백엔드도** `sessionType` 또는 `gameMode`가 TimeTrial이면 저장하지 않고 Ack한다(정책 최종 판정은 백엔드 — D-15와 같은 원칙).

### D-31. Standings = 기록된 세션의 점수 합(본 레이스 카운트백), Constructors 포함
- 드라이버 점수 = 그 시즌에 **기록된** 세션의 `Points` 합(스프린트 포함). 게임 안의 공식 순위표가 아니라, Agent가 받은 세션 기준이다.
  Agent 없이 한 라운드나 시뮬레이션으로 넘긴 세션의 결과를 받지 못했다면 게임과 다를 수 있다 — 화면에 "기록된 세션 기준"을 표시한다.
- **계산 대상 세션:** 같은 주말·같은 세션 종류(`SessionKind`, `Unknown` 제외)가 여러 건이면 `ClassifiedAt`이 가장 늦은 1건만 쓴다
  (링크 식별자가 바뀌어 같은 세션이 두 번 저장된 경우의 이중 집계 방지, §3.3).
- **본 레이스:** 주말마다 레이스 세션(`SessionType.Race`) 중 `ClassifiedAt`이 가장 늦은 1건. 스프린트는 점수에만 들어가고,
  우승·포디움·카운트백은 **본 레이스만** 센다(실제 F1처럼 스프린트 우승은 GP 우승이 아니다).
  레이스가 스프린트 하나만 기록된 주말은 그 스프린트가 본 레이스가 된다(기록된 레이스가 그것뿐이므로).
- **Standings 대상:** 계산 대상 세션 중 레이스 세션이거나 점수가 있는 행의 드라이버만 Standings에 오른다(연습·예선만 달린 드라이버는 없음).
  시즌 목록 카드와 시즌 상세가 **같은 대상 행**으로 계산해 순위가 서로 다르지 않다.
- 동점: 본 레이스 1위 횟수 → 2위 횟수 → … 순서로 비교(카운트백) → 표시 이름 오름차순(Ordinal) → `DriverKey` 오름차순(Ordinal, 이름이 같을 때의 최종 기준).
- Constructors = 팀별 점수 합(그 세션에서 그 드라이버가 속한 팀 기준). 우승 = 그 팀 드라이버의 본 레이스 우승 수.
  동점은 우승 수 → 팀 이름 오름차순(Ordinal) → 팀 ID 오름차순. 팀 ID가 다르면(예: 2025·2026 Red Bull) 이름이 같아도 다른 팀이다.

### D-32. 시즌 안의 드라이버 식별 = 플레이어 → 게임 드라이버 ID → 이름+차 번호
- `isPlayer`(그 PC의 플레이어 차)이면 `player`, 게임 드라이버 ID가 있으면 `driver:{id}`, 없으면(네트워크 사람 등) `name:{정규화한 이름}#{차 번호}`.
  참가자 정보를 못 받은 차는 `car:{SessionRef}:{carIndex}` — **그 세션 안에서만** 유일하다(다른 라운드의 다른 드라이버와 합쳐지지 않게).
- 이유: 커리어에서 플레이어의 드라이버 ID는 게임마다 특수값일 수 있고, 온라인 사람은 ID가 `NetworkHuman`(65535)이다.

### D-33. 팀 이름·색 = 백엔드의 게임별 정적 카탈로그
- `(gameCode, teamId)` → 표시 이름·색(hex). F1 25의 2025 팀 10개, 2024 차량 10개, 2026 시즌팩 팀 11개, My Team(104), F1 Generic(41)을 넣는다.
  없는 ID는 `Team {id}`와 기본 색. API가 `teamName`·`teamColor`를 내려 주어 앱은 매핑하지 않는다.
- 상수 표(불변)라 헌장의 "Global Static 금지"(가변 전역 상태)에 해당하지 않는다. `GameCodes`와 같은 성격이다.

### D-34. 남의 시즌·세션 조회 = 404
- 조회 API는 모두 `sub` 기준으로 내 것만 찾는다. 남의 ID는 없는 ID와 똑같이 404를 돌려준다(존재 여부를 알려 주지 않는다).
  (P6의 장치 해제는 쓰기 작업이라 403을 유지한다.)

---

## 3. F1 25 UDP 데이터 (F1Game.UDP 26.0.0에서 확인)

### 3.1 사용하는 필드

| 패킷(id) | 빈도 | 필드 → 용도 |
|---|---|---|
| Session(1) | 초당 2회 | `GameMode`(byte enum) → 모드, `SeasonLinkIdentifier`·`WeekendLinkIdentifier`·`SessionLinkIdentifier`(uint) → 묶음 키, `SessionType`(상세) → 세션 이름, `Track`, `TotalLaps`(byte), `AIDifficulty`(byte, 0~110), `IsNetworkGame`(bool) |
| Participants(4) | 5초마다 | `Participants[carIndex]`: `Name`(string, 최대 32바이트), `Driver`(ushort enum, 사람이면 `NetworkHuman`=65535), `Team`(ushort enum), `RaceNumber`(byte), `IsAiControlled`(bool) |
| Final Classification(8) | 세션 끝 | `ClassificationData[carIndex]`: `Position`·`GridPosition`·`NumLaps`·`Points`·`NumPitStops`·`NumPenalties`(byte), `ResultStatus`(byte enum), `BestLapTimeInMS`(uint), `TotalRaceTime`(**double, 초**, 패널티 제외), `PenaltiesTime`(**byte, 초**), `NumTyreStints` + `TyreStintsActual`·`TyreStintsVisual`·`TyreStintsEndLaps`(각 8칸) |
| 모든 패킷 헤더 | — | `SessionUID` → `SessionRef`(기존), `PlayerCarIndex` → `isPlayer` |

### 3.2 enum 값(라이브러리 기준)
- `GameMode`: GrandPrix23=4, TimeTrial=5, SplitScreen=6, OnlineCustom=7, OnlineWeeklyEvent=15, StoryMode=17, MyTeamCareer25=27, DriverCareer25=28, Career25Online=29, ChallengeCareer25=30, StoryModeApxGp=75, Benchmark=127
- `ResultStatus`: Invalid=0, Inactive=1, Active=2, Finished=3, DidNotFinish=4, Disqualified=5, NotClassified=6, Retired=7
- `SessionType`(상세): Practice1~3, ShortPractice, Qualifying1~3, ShortQualifying, OneShotQualifying, SprintShootout1~3, ShortSprintShootout, OneShotSprintShootout, Race, Race2, Race3, TimeTrial
- `VisualCompound`: F1Soft=16, F1Medium=17, F1Hard=18, F1Inter=7, F1Wet=8 (그 외 클래식·F2) · `ActualCompound`: F1C0~C6(21~16, C6=22), F1Inter=7, F1Wet=8
- 배열(`Array24<T>`, `Array8<T>`)은 `T[]`에서 암시 변환된다(테스트에서 패킷을 만들 때 쓴다).

### 3.3 게임에서 확인해야 할 가정

| 가정 | 틀렸을 때 | 확인 결과 |
|---|---|---|
| Final Classification이 연습·예선 세션 끝에도 온다 | 그 세션이 Sessions·시즌 라운드에 없을 뿐 오류는 없다(필터·칩이 비어 보인다) | 미확인 |
| 같은 `SessionUID`로 Final Classification이 여러 번 올 수 있다 | Agent가 `SessionRef`당 1회만 보낸다(§5.3) | 미확인 |
| 세션 재시작·세이브 재개 시 `SessionLinkIdentifier`가 유지된다 | 유지되지 않으면 같은 세션이 Sessions 목록에 두 행으로 남는다(데이터 손실 없음). 시즌 계산은 같은 주말·같은 세션 종류의 최신 1건만 써서 점수가 이중으로 더해지지 않는다(D-31) | 미확인 |
| 커리어의 다음 해(시즌)는 `SeasonLinkIdentifier`가 바뀐다 | 바뀌지 않으면 여러 해가 한 시즌으로 합쳐진다 — 확인 후 필요하면 "같은 트랙 주말이 다시 나오면 새 시즌" 규칙을 추가한다 | 미확인 |
| Grand Prix 모드의 링크 값이 주말·챔피언십 단위로 의미가 있다 | 아니면 Grand Prix를 시즌 대상 모드에서 뺀다(`SeasonPolicy` 한 줄) | 미확인 |
| F1 25의 Grand Prix 모드 값이 라이브러리의 `GrandPrix23`(4)이다(예전 연식 스펙의 3이 아니다) | 매퍼가 원시 값 3도 Grand Prix로 본다(§5.2) — 어느 쪽이어도 동작 | 미확인 |
| 스프린트 주말에서 스프린트가 `Race`, 본 레이스가 `Race2`다 | 세션 이름 표시만 다르다(§8.4 라벨만 고치면 됨). 본 레이스 판정은 시각 기준이라 영향 없음 | 미확인 |
| Participants의 레이아웃이 사용자의 게임 버전(2026 시즌팩)과 맞다 | 이름이 깨진다 — D-20의 버전 결정 문제로, 게임 업데이트로 맞춘다 | 미확인 |

> 확인 절차는 [TESTING-local-e2e.md](./TESTING-local-e2e.md) §10. 확인하면 "확인 결과" 열에 날짜와 결과(가정이 맞았는지, 틀렸다면 무엇이 달랐는지)를 적는다.

---

## 4. 도메인 · 데이터 모델

### 4.1 계층

```
User ─┬─ Season (커리어·GP 시즌)            key: (UserId, GameCode, SeasonLinkId)
      │    └─ RaceWeekend (그랑프리 주말)      key: (SeasonId, WeekendLinkId)
      │         └─ GameSession ◄──────────┐
      └──────── GameSession (시즌 없는 세션도) key: (UserId, GameCode, SessionKey)
                     └─ SessionResult (드라이버 1명의 결과, 차 1대)   key: (GameSessionId, CarIndex)
                          └─ SessionResultTyreStint (스틴트)
```

- **모든 unique index는 `is_deleted = false` 필터를 단다.** 조회는 전역 soft-delete 필터를 쓰므로, 나중에 시즌·세션 삭제가 생겨도
  삭제된 행 때문에 새 행 삽입이 매번 unique 위반으로 실패하지 않는다(§0 실패 원칙).

### 4.2 신규 엔티티 (모두 `BaseEntity`: `Id`(UUID v7) · `CreatedAt` · `UpdatedAt` · `IsDeleted`)

**`Season`**

| 필드 | 타입 | 설명 |
|---|---|---|
| `UserId` | Guid | FK → users, `Restrict` |
| `GameCode` | string(20) | 예 `F1_25` |
| `SeasonLinkId` | long | 게임의 `uint` 링크 식별자(0 아님) |
| `GameMode` | enum(string, 20) | 처음 받은 세션의 모드 |
| `FirstSessionAt` · `LastSessionAt` | DateTime (UTC) | 받은 세션의 `ClassifiedAt` 최소·최대 |

- unique `(UserId, GameCode, SeasonLinkId)`. 목록 정렬용 인덱스 `(UserId, LastSessionAt)`.

**`RaceWeekend`**

| 필드 | 타입 | 설명 |
|---|---|---|
| `SeasonId` | Guid | FK → seasons, `Restrict` |
| `WeekendLinkId` | long | 0 아님 |
| `TrackId` | Guid | FK → tracks, `Restrict`. 처음 받은 세션의 트랙 |
| `FirstSessionAt` | DateTime (UTC) | 라운드 순서 기준 |

- unique `(SeasonId, WeekendLinkId)`. **라운드 번호는 저장하지 않는다** — 시즌 안에서 `FirstSessionAt`, `Id` 순서로 조회 시 계산한다.
  게임 UDP에 라운드 번호가 없고, 결과가 늦게 도착하면 저장된 번호가 틀어지기 때문이다. 따라서 `R{n}`은 **기록된 주말 순서**이고 게임의 라운드와 다를 수 있다.

**`GameSession`**

| 필드 | 타입 | 설명 |
|---|---|---|
| `UserId` | Guid | FK → users, `Restrict` |
| `AgentDeviceId` | Guid | 마지막으로 결과를 보낸 장치. FK만(내비게이션 없음 — `Lap.AgentDevice`의 soft-delete inner join 함정을 피한다), `Restrict` |
| `SeasonId` · `RaceWeekendId` | Guid? | 시즌 대상이 아니면 null. FK `Restrict` |
| `GameCode` | string(20) | |
| `SessionKey` | string(80) | D-29 규칙. unique `(UserId, GameCode, SessionKey)` |
| `SeasonLinkId` · `WeekendLinkId` · `SessionLinkId` | long | 원본 링크 값(0 가능) |
| `SessionRef` | string(32) | 결과를 받은 게임 세션 UID(`SessionUID`) |
| `TrackId` | Guid | FK → tracks, `Restrict` |
| `SessionType` | enum(string, 20) | 기존 5종(Practice·Qualifying·Race…) |
| `SessionKind` | enum(string, 30) | 상세(Practice1, Qualifying2, SprintShootout1, Race2…) |
| `GameMode` | enum(string, 20) | |
| `TotalLaps` · `AiDifficulty` | int | |
| `IsNetworkGame` | bool | |
| `ClassifiedAt` | DateTime (UTC) | 이벤트 `occurredAt`(서버 시각 + 5분을 넘으면 그 값으로 자름, §6.2) |
| `Results` | 컬렉션 | |

- 인덱스: `(UserId, ClassifiedAt)`(목록), `(RaceWeekendId)`, `(SeasonId)`.

**`SessionResult`** — 차 1대의 최종 결과

| 필드 | 타입 | 설명 |
|---|---|---|
| `GameSessionId` | Guid | FK → game_sessions, `Cascade` |
| `CarIndex` | int | 0부터. unique `(GameSessionId, CarIndex)` (필터 적용) |
| `Position` · `GridPosition` · `NumLaps` · `Points` · `NumPitStops` · `NumPenalties` | int | |
| `ResultStatus` | enum(string, 20) | Finished · DidNotFinish · Disqualified · NotClassified · Retired · Active · Unknown |
| `BestLapTimeMs` | int | 0 = 기록 없음(API에서는 null) |
| `TotalRaceTimeMs` | int | 패널티 제외(게임 값 초 → ms 반올림). 0 = 없음 |
| `PenaltiesTimeMs` | int | |
| `DriverKey` | string(80) | D-32. 인덱스 `(GameSessionId, DriverKey)` |
| `DriverName` | string(64)? | 참가자 정보가 없으면 null(표시는 `Car {carIndex+1}`) |
| `GameDriverId` | int? | 사람(네트워크)이면 null |
| `TeamId` | int? | 게임 팀 ID |
| `RaceNumber` | int? | |
| `IsAiControlled` · `IsPlayer` | bool | |
| `TyreStints` | 컬렉션 | |

**`SessionResultTyreStint`**

| 필드 | 타입 | 설명 |
|---|---|---|
| `SessionResultId` | Guid | FK → session_results, `Cascade` |
| `StintNumber` | int | 1부터 |
| `EndLap` | int | 그 스틴트가 끝난 랩 |
| `VisualCompound` | enum(string, 20) | Soft · Medium · Hard · Intermediate · Wet · Unknown |
| `ActualCompound` | string(10)? | 예 `C3`. 게임 중립 문자열 라벨 |

> 스틴트는 P8 화면의 재료지만 **P7에서 저장한다.** 최종 순위표는 세션당 한 번만 오므로 지금 버리면 P7 기간의 세션은 영영 스틴트가 없다.
> P7 세션 결과 화면에서도 컴파운드 아이콘으로 쓴다.

### 4.3 신규 enum (Domain, 게임 중립)
- `GameMode`: `Other`(=0), `DriverCareer`, `MyTeamCareer`, `OnlineCareer`, `ChallengeCareer`, `GrandPrix`, `TimeTrial`, `Online`, `Story`
- `SessionKind`: `Unknown`(=0), `Practice1`, `Practice2`, `Practice3`, `ShortPractice`, `Qualifying1`, `Qualifying2`, `Qualifying3`, `ShortQualifying`,
  `OneShotQualifying`, `SprintShootout1`, `SprintShootout2`, `SprintShootout3`, `ShortSprintShootout`, `OneShotSprintShootout`, `Race`, `Race2`, `Race3`, `TimeTrial`
- `ResultStatus`: `Unknown`(=0), `Active`, `Finished`, `DidNotFinish`, `Disqualified`, `NotClassified`, `Retired`
- `TyreCompound`: `Unknown`(=0), `Soft`, `Medium`, `Hard`, `Intermediate`, `Wet`
- 0번 값이 "모름" 대체값이다. 인입은 모르는 문자열을 이 값으로 받아들인다(§6.2).

### 4.4 순수 도메인 규칙 (Domain, 단위 테스트 대상)
- `SeasonPolicy.BelongsToSeason(gameMode, seasonLinkId, weekendLinkId)` — D-29의 시즌 대상 판정.
- `SessionKeys.For(gameMode, seasonLinkId, weekendLinkId, sessionLinkId, sessionRef)` — D-29의 세션 키(시즌 대상이 아니면 항상 `uid:`).
  `SessionKeys.Uid(sessionRef)` — 트랙·종류 불일치 시 대체 키.
- `DriverKeys.Build(isPlayer, gameDriverId, name, raceNumber, sessionRef, carIndex)` — D-32. 이름 정규화 = 앞뒤 공백 제거 + `ToUpperInvariant`.
- `GameSession.ReplaceResults(incoming, now)` — §4.5.

### 4.5 결과 교체(재분류) — carIndex별 제자리 갱신 + soft delete
- 같은 `SessionKey`에 새 결과가 오면 `GameSession.ReplaceResults(incoming, now)`가 **carIndex로 맞춰** 병합한다:
  1. 같은 carIndex의 활성 행이 있으면 그 행의 값을 새 값으로 덮어쓰고(`UpdatedAt = now`), 그 행의 활성 스틴트는 soft delete한 뒤 새 스틴트를 붙인다.
  2. 새 순위표에 없는 carIndex의 활성 행은 soft delete(`IsDeleted = true`, `UpdatedAt = now`, 스틴트 포함).
  3. 새 carIndex는 새 행으로 추가한다.
- **이유:** "옛 행 soft delete + 같은 carIndex 새 행 INSERT"를 한 번의 `SaveChanges`로 하면, EF Core는 필터 unique index가
  soft delete로 비는 것을 모르기 때문에 INSERT를 UPDATE보다 먼저 보낼 수 있고 PostgreSQL이 즉시 unique 위반을 낸다(그러면 Agent가 같은 항목을 끝없이 재시도한다).
  제자리 갱신은 같은 carIndex에 새 행을 만들지 않아 이 문제가 없다.
- 컬렉션에 `Remove`·`Clear`를 쓰지 않는다 — 필수 FK + `Cascade` 관계라 EF가 **실제 삭제**를 한다. 지우기는 항상 `IsDeleted`로 한다.
- `UpdatedAt`은 자동으로 채워지지 않는다(인터셉터 없음). 바꾸는 코드가 직접 `now`를 넣는다.
- **새 엔티티 5종의 `Id`는 `ValueGeneratedNever()`로 매핑한다.** Guid 키의 EF 기본값은 `ValueGeneratedOnAdd`라서, 이미 추적 중인 세션의 컬렉션에
  `IIdGenerator`로 Id를 채운 새 결과·스틴트를 붙이면 EF가 "이미 있는 행"으로 보고 INSERT 대신 UPDATE를 보낸다
  → 매번 `DbUpdateConcurrencyException`(§0의 무한 재시도). 새로 만드는 세션 전체를 `AddAsync`로 넣는 경로는 영향이 없지만, 병합 경로는 이 설정이 있어야 한다.

### 4.6 `Lap.SessionKey` (P8을 위한 연결 씨앗)
- 게임 세션 하나가 여러 `SessionUID`에 걸칠 수 있다(세이브 후 재개, 재시작). `SessionRef`만 저장하면 P8에서 앞부분의 랩을 세션에 연결할 수 없다.
- 그래서 Agent의 `LapFinished`에 `gameMode`·`seasonLinkId`·`weekendLinkId`·`sessionLinkId`를 **추가 필드**로 싣고(LapAnalyzer가 이미 가진 Session 맥락),
  백엔드는 `SessionKeys.For(...)`로 계산한 값을 `Lap.SessionKey`(string(80), null 허용 — 기존 행은 null)에 **저장만** 한다.
  옛 Agent가 보낸 랩(필드 없음)은 `uid:{sessionRef}`가 된다. `sessionRef`가 비었거나 32자를 넘거나 NUL(`\0`)을 품으면 키를 만들지 않고 null로 둔다(열 길이 초과·NUL로 랩 저장이 매번 실패하지 않게).
- P8에서 `(UserId, GameCode, SessionKey)`로 내 랩을 `GameSession`과 연결한다. P7은 이 컬럼을 조회에 쓰지 않는다. 인덱스도 P8에서 만든다.

### 4.7 마이그레이션 1건: `AddSeasonsAndSessions`
- 테이블 5개 생성(`seasons`, `race_weekends`, `game_sessions`, `session_results`, `session_result_tyre_stints`), `laps.session_key` 추가.
- 기존 데이터 변경 없음(가산적).

---

## 5. Agent

### 5.1 프레임 (Agent.Core, F1Game.UDP 무의존 — D-20 유지)

| 프레임 | 변경 | 필드 |
|---|---|---|
| `SessionFrame` | 필드 추가(기본값 있는 뒤쪽 매개변수 — 기존 호출부 그대로 컴파일) | 기존 + `SessionKind`, `GameMode`, `SeasonLinkId`·`WeekendLinkId`·`SessionLinkId`(uint), `TotalLaps`, `AiDifficulty`, `IsNetworkGame` |
| `ParticipantsFrame` | 신규 | `SessionRef`, `Participants: IReadOnlyList<ParticipantInfo(CarIndex, Name, GameDriverId?, TeamId, RaceNumber, IsAiControlled)>` |
| `ClassificationFrame` | 신규 | `SessionRef`, `PlayerCarIndex`, `Rows: IReadOnlyList<ClassificationRow(CarIndex, Position, GridPosition, NumLaps, Points, NumPitStops, NumPenalties, ResultStatus, BestLapTimeMs, TotalRaceTimeMs, PenaltiesTimeMs, TyreStints)>` |

Agent.Core에도 §4.3과 같은 이름의 enum(`GameMode`, `SessionKind`, `ResultStatus`, `TyreCompound`)을 둔다(직렬화 시 문자열로 그대로 매핑 — 기존 `SessionType`과 같은 방식).

### 5.2 매퍼 (`F1PacketMapper`, Agent.Infrastructure)
- `MapSession`: 위 필드를 채운다. `GameMode` 매핑 — GrandPrix23(4)과 원시 값 3(예전 연식의 Grand Prix, 이름 붙은 상수)→GrandPrix, TimeTrial→TimeTrial, OnlineCustom·OnlineWeeklyEvent→Online,
  StoryMode·StoryModeApxGp→Story, MyTeamCareer25→MyTeamCareer, DriverCareer25→DriverCareer, Career25Online→OnlineCareer,
  ChallengeCareer25→ChallengeCareer, 그 외(SplitScreen·Benchmark·모르는 값)→Other.
- `MapParticipants`(신규): 배열 전체를 carIndex 순서로 매핑한다. `Driver == NetworkHuman`이면 `GameDriverId = null`.
  UDP 이름은 NUL로 채워진 고정 길이 문자열이라 **첫 NUL에서 잘라** 보낸다(이름이 없으면 빈 문자열 — 백엔드가 null로 바꾼다).
- `MapClassification`(신규): 배열 전체를 carIndex로 순회하고 **`ResultStatus`가 Invalid·Inactive이거나 `Position == 0`인 칸은 뺀다**(빈 그리드 칸).
  시간 변환: `TotalRaceTimeMs = round(TotalRaceTime × 1000)`, `PenaltiesTimeMs = PenaltiesTime × 1000`. 스틴트는 `NumTyreStints`개만(최대 8).
  **깨진 시간값은 보정한다**(백엔드는 음수를 영구 Reject해 세션 전체를 잃으므로): `TotalRaceTime`이 NaN·0 이하이면 0, `int.MaxValue`를 넘으면 `int.MaxValue`,
  `BestLapTimeInMS`(uint)는 `int.MaxValue`로 자른다.
  컴파운드: Visual F1Soft/Medium/Hard/Inter/Wet → Soft/Medium/Hard/Intermediate/Wet, 그 외 Unknown. Actual F1C0~C6 → `"C0"`~`"C6"`, Inter·Wet → `"Inter"`·`"Wet"`, 그 외 null.
- `Map(UnionPacket)`에 Participants·FinalClassification 분기를 추가한다. 그 밖의 패킷은 지금처럼 무시한다.

### 5.3 `SessionResultTracker` (Agent.Core/Analysis, 신규·순수·상태 저장)
- `ParticipantsFrame`·`ClassificationFrame`·`SessionFrame`만 본다. `LapAnalyzer`와 상태를 공유하지 않는다(`SessionEnded`로 리셋되지 않음).
- 상태: 최신 `SessionFrame`(맥락), 같은 `SessionRef`의 최신 참가자 목록, 마지막으로 보낸 `SessionRef`.
- 규칙:
  1. `SessionFrame` — 맥락을 바꾼다. `SessionRef`가 바뀌면 참가자 목록을 비운다.
  2. `ParticipantsFrame` — 맥락과 `SessionRef`가 같을 때만 저장한다.
  3. `ClassificationFrame` — 맥락이 없거나 `SessionRef`가 다르면 무시. 맥락의 `SessionType`이 `TimeTrial`이면 무시(D-30). 이미 보낸 `SessionRef`면 무시.
     **`Rows`가 비어 있으면(빈 순위표) 무시하고 그 `SessionRef`를 보낸 것으로 기억하지 않는다** — 백엔드는 `results` 1~32개가 아니면 항상 Reject하므로,
     보내면 영구 Reject가 되고 "세션당 1회" 슬롯만 써 버려 뒤따르는 정상 순위표를 막는다.
     아니면 참가자를 carIndex로 붙여 `SessionClassified` 1건을 만들고 그 `SessionRef`를 기억한다.
     참가자 정보가 없는 차는 `driverName`·`gameDriverId`·`teamId`·`raceNumber`를 null, `isAiControlled`를 false로 보낸다.
- 같은 세션을 다시 보내는 일(Agent 재시작 등)이 생겨도 백엔드가 같은 키로 병합하므로 결과는 같다.

### 5.4 `LapAnalyzer` 변경
- `SessionFrame`의 `GameMode`·링크 3개를 세션 상태로 보관하고 `LapFinished`에 싣는다(§4.6). 판정 로직은 바뀌지 않는다.
- `LapFinished` 레코드에 기본값 있는 뒤쪽 매개변수 4개(`GameMode = Other`, 링크 3개 = 0)를 추가한다.

### 5.5 이벤트 `SessionClassified` (shared/schema/session_classified.json)

```jsonc
{
  "sessionRef": "1844674407370955161",
  "trackId": 10,
  "sessionType": "Race",            // 기존 5종
  "sessionKind": "Race",            // 상세
  "gameMode": "DriverCareer",
  "seasonLinkId": 2847561234, "weekendLinkId": 99112233, "sessionLinkId": 44556677,
  "totalLaps": 29, "aiDifficulty": 85, "isNetworkGame": false,
  "results": [
    {
      "carIndex": 3, "isPlayer": true,
      "position": 1, "gridPosition": 2, "numLaps": 29, "points": 25,
      "numPitStops": 1, "numPenalties": 0, "resultStatus": "Finished",
      "bestLapTimeMs": 81234, "totalRaceTimeMs": 2493120, "penaltiesTimeMs": 0,
      "driverName": "S. LIM", "gameDriverId": null, "teamId": 2, "raceNumber": 26, "isAiControlled": false,
      "tyreStints": [ { "endLap": 14, "visualCompound": "Medium", "actualCompound": "C3" },
                      { "endLap": 29, "visualCompound": "Hard", "actualCompound": "C2" } ]
    }
  ]
}
```

- envelope `type = "SessionClassified"`. `TelemetryEventType`·`telemetry_envelope.json` enum에 추가한다. `lap_finished.json`에는 §4.6의 선택 필드 4개를 추가한다.
- **크기와 한도(§0 실패 원칙):**
  - 22대 × 스틴트 2~3개 ≈ 10KB. 게임이 보낼 수 있는 최대(24대 × 스틴트 8개)도 Agent 쪽 직렬화(UTF-8 바이트) 기준 23.8KB(이름 비ASCII 10자)이고, 이름이 검증 한도(비ASCII 64자)까지 길어도 31.6KB다.
    **실측(구현 후):** 검증 상한 페이로드(32대 × 8스틴트, 비ASCII 이름 64자)는 SignalR 와이어에서 약 32~34KB다 — SignalR 허브 프로토콜은 비ASCII를 `\uXXXX`로 escape하지 않아 설계 추정(약 44KB, escape를 가정)보다 작다.
    Agent의 Outbox 직렬화(`System.Text.Json` 기본값)는 비ASCII를 escape하므로 Agent 쪽 수치가 와이어보다 커서, 48KiB 검사는 보수적이다(§14).
  - 백엔드는 `TelemetryHub`의 `MaximumReceiveMessageSize`를 **이름 붙은 상수 64KiB**(`TelemetryHub.MaxMessageBytes`, `AddHubOptions<TelemetryHub>`)로 명시한다(기본 32KB에 기대지 않는다). 한도를 넘는 메시지는
    Reject가 아니라 연결 종료라 Agent가 같은 항목을 끝없이 재시도하게 되기 때문이다.
  - Agent는 Outbox에 넣기 전에 직렬화 크기(UTF-8 바이트)를 잰다(`OutboxTelemetrySink.MaxEnvelopeBytes = 48KiB`). 넘으면 스틴트를 빼고 다시 재고 경고 로그, 그래도 넘으면 버리고 오류 로그를 남긴다.
- **배선:** `TelemetryPipeline`이 분석기 목록(`ITelemetryAnalyzer`: `LapAnalyzer`, `SessionResultTracker`)을 차례로 돌린다. 두 분석기는 `SessionFrame`을 함께 보지만
  **상태를 공유하지 않으므로 순서에 의존하지 않는다.** 분석기마다 try/catch로 감싸 한쪽의 예외가 다른 쪽을 막지 않게 한다. Outbox·업로드·재전송은 바뀌지 않는다.
- **호환:** 옛 백엔드는 모르는 이벤트를 Ack하고 버린다(데이터 손실). **배포 순서는 백엔드 → Agent.** 옛 Agent는 이 이벤트와 랩의 추가 필드를 보내지 않을 뿐이다.

---

## 6. Backend 인입

### 6.1 배선
- `TelemetryIngestService.IngestAsync`의 1~3단계(멱등 → 장치 확인 → `LastSeenAt`)는 그대로다.
- 4단계를 유형별 분기로 바꾼다: `LapFinished` → 기존 경로(+ `Lap.SessionKey` 저장), `SessionClassified` → 신규 `ISessionClassificationIngestor`,
  그 밖 → Ack(기존). 신규 처리기는 변경을 추적만 하고, `ProcessedEvent` 추가와 **커밋 1회**는 `TelemetryIngestService`가 한다
  (랩 경로와 같은 원자성: 결과 저장과 멱등 기록이 한 트랜잭션).
- 처리기의 결과는 3가지다: **Stored**(저장할 변경 있음) · **Ignored**(변경 없음 — Time Trial, 늦게 온 옛 결과) · **Rejected(사유)**.
  Stored·Ignored는 Ack + 멱등 기록 + 커밋, Rejected는 Reject(기존 `FinishWithoutLapAsync` — LastSeen만 저장).
- 이유: 인입 서비스가 이미 260줄이라 결과 처리까지 넣으면 커진다. 유형별 처리기를 분리하되, 공통 단계는 한곳에 둔다.

### 6.2 `SessionClassificationIngestor` 처리 순서 (Application/Seasons)
> **불변식:** 1~7단계는 아무것도 추가·수정하지 않는다. Reject는 1·2·4단계에서만 나온다. 그래서 Reject 경로의 `SaveChanges`(LastSeen)가 반쯤 만든 그래프를 저장하는 일이 없다.

1. **파싱(구조만):** payload → `SessionClassifiedPayloadDto`. enum 필드(`sessionType`·`sessionKind`·`gameMode`·`resultStatus`·`visualCompound`)는 **문자열로 받아**
   대소문자 무시로 해석하고, 모르는 값은 0번 대체값(§4.3)으로 바꾼다 — 게임 업데이트로 새 값이 생겨도 세션당 한 번뿐인 이벤트를 잃지 않는다.
   JSON 구조가 깨졌으면 Reject("SessionClassified payload 파싱 실패"), 비었으면 Reject("SessionClassified payload가 비어 있습니다.").
2. **검증(영구 무효 → Reject "SessionClassified 검증 실패: {상세}"):** DB 열 제약에 걸릴 수 있는 값은 **모두 여기서** 거른다(저장 시 예외 = 무한 재시도).
   - `sessionRef`: 비어 있지 않고 32자 이하이며 **NUL(`\0`)을 품지 않는다**(PostgreSQL 텍스트는 NUL을 저장하지 못하고, `SessionRef`·`SessionKey`·`DriverKey`로 흘러간다).
   - `results`: null 아님, 1~`MaxClassificationEntries`(32)개, null 원소 없음. `isPlayer`는 0~1개.
   - 행마다: `carIndex` 0~31·중복 없음, `position` 1~32, `gridPosition`·`numLaps`·`points`·`numPitStops`·`numPenalties`·`bestLapTimeMs`·`totalRaceTimeMs`·`penaltiesTimeMs` ≥ 0,
     `driverName` ≤ 64자, `raceNumber`(있다면) ≥ 0(이름 키 `name:{NAME}#{raceNumber}`가 `DriverKey` 열 길이 80자를 넘지 않게),
     `tyreStints`는 null(빈 목록으로 봄) 또는 ≤ `MaxTyreStints`(8)개·null 원소 없음.
   - 스틴트마다: `endLap` ≥ 0, `actualCompound` ≤ 10자.
   - (한도는 게임이 실제로 보낼 수 있는 값보다 약간 넉넉하게 — F1 25는 최대 24대·8스틴트)
   - 정규화(거부하지 않음): `driverName`·`actualCompound`는 **첫 NUL에서 잘라 내고**(UDP 이름은 NUL로 채워진 고정 길이 문자열이 정상 형태) 앞뒤 공백을 지운 뒤 비면 null.
     길이 검사는 자르기 전의 원본 길이에 한다.
3. **Time Trial:** `sessionType` 또는 `gameMode`가 TimeTrial이면 **Ignored**(D-30).
4. **트랙 매핑:** `(gameCode, trackId)` → `Track`. 없으면 Reject(`트랙 매핑 없음(gameCode=…, trackId=…)` — 랩과 같은 문구).
5. **분류 시각:** `ClassifiedAt = min(occurredAt, now + MaxClockSkew(5분))`. Agent 시계가 앞서 있어도 이후 재분류가 막히지 않게 한다.
6. **세션 찾기:** `SessionKeys.For(...)`로 키를 만들어 찾는다. 찾은 세션의 `TrackId` 또는 `SessionKind`가 다르면 경고 로그를 남기고
   키를 `SessionKeys.Uid(sessionRef)`로 바꿔 다시 찾으며, **이 세션은 시즌·주말에 넣지 않는다**(같은 주말에 다른 트랙 세션이 섞이거나
   원래 세션과 중복 제거되는 일을 막는다, D-29).
7. **늦은 결과:** 찾은 세션이 있고 `ClassifiedAt < 저장된 ClassifiedAt`이면 **Ignored**.
8. **시즌·주말 업서트:** `SeasonPolicy`가 참이고 6단계의 대체가 없었으면 `Season`을 `(UserId, GameCode, SeasonLinkId)`로 찾거나 만들고(`GameMode`, 첫·마지막 시각),
   이어서 `RaceWeekend`를 `(SeasonId, WeekendLinkId)`로 찾거나 만든다(트랙, 첫 시각). 이미 있으면 `Touch(classifiedAt, now)`로 첫·마지막 시각만 넓힌다.
9. **세션 생성·갱신:** 없으면 `GameSession` + 결과 + 스틴트 생성. 있으면 세션 필드(`SessionRef`, `AgentDeviceId`, `ClassifiedAt`, 모드·랩 수·AI 난이도 등, `UpdatedAt`)를
   갱신하고 `ReplaceResults`로 결과를 병합한다(§4.5). 결과 행마다 `DriverKeys.Build`. `UserId = device.UserId`, `AgentDeviceId = device.Id`. → **Stored**.

### 6.3 동시성
- 같은 사용자의 두 PC가 같은 시즌의 첫 결과를 동시에 보내면 unique 위반이 날 수 있다. 예외는 허브 오류로 Agent에 돌아가고,
  Agent는 그 항목을 Outbox에 두고 재시도한다. 재시도 때는 행이 있으므로 성공한다(**일시** 장애라 무한 재시도가 아니다). 별도 잠금은 두지 않는다.
- 같은 입력에 항상 실패하는 경로는 설계에서 없앴다: 결과 교체(§4.5), unique index와 soft delete(§4.1), 모르는 enum(§6.2-1), 메시지 크기(§5.5).
  그래도 남는 일반적인 위험(구현 버그로 특정 항목이 매번 실패)은 기존 Agent에도 있는 문제라 **후속 작업(Outbox 독성 항목 처리)** 으로 분리한다(§12).

### 6.4 로그
- 저장 시 `Information`: device, user, sessionKey, track, 결과 행 수, Stored(신규·병합)/Ignored(사유). 키 불일치 대체는 `Warning`.

---

## 7. 조회 API · 계산

### 7.1 엔드포인트 (`/api/v1`, JWT, 응답 camelCase, 남의 것·없는 것 = 404)

| Method · Path | 요청 | 응답 |
|---|---|---|
| `GET /me/seasons` | `page`(1), `pageSize`(20, **최대 20**) | `PagedResult<SeasonSummaryDto>` — `LastSessionAt` 내림차순, 같으면 Id 내림차순 |
| `GET /me/seasons/{seasonId:guid}` | — | `SeasonDetailDto` — 헤더 + 라운드 + Standings(결과표 칸 포함). 세 탭이 같은 스냅샷을 쓰므로 한 번에 |
| `GET /me/sessions` | `sessionType`(선택: `Practice`·`Qualifying`·`Race`만), `page`(1), `pageSize`(20, 최대 100) | `PagedResult<SessionSummaryDto>` — `ClassifiedAt` 내림차순, 같으면 Id 내림차순 |
| `GET /me/sessions/{sessionId:guid}` | — | `SessionDetailDto` — 헤더 + 결과(`Position` 오름차순, 같으면 `CarIndex`) |

- 기본 페이지 크기는 서버 공통 규칙([04](./04-api-design.md) §5: 기본 20)을 따르고, 앱이 Sessions에서 `pageSize=15`를 보낸다(Laps와 같은 방식).
  시즌 목록 최대 20은 목록 한 번에 그 시즌들의 결과 행을 읽어 순위를 계산하기 때문이다(§7.3).
- 페이지 보정은 기존 `RankingService.GetMyLapsAsync`와 같다(page < 1 → 1, pageSize ≤ 0 → 기본값, 최대 초과 → 최대).
- `sessionType`은 문자열로 받아 **명시적 이름 목록** `Practice`·`Qualifying`·`Race`(대소문자 무시)만 허용한다. 그 밖의 값(`TimeTrial`, 숫자 `4`, 오타)은
  `ValidationException("sessionType", …)` → 표준 400. (`RankingsController.ParsePeriod`처럼 컨트롤러에서 거르되, `Enum.TryParse`는 숫자를 받아들이므로 쓰지 않는다.)
- Id가 GUID가 아니면 라우트가 맞지 않아 404, 토큰이 없으면 401(기존 규칙).

### 7.2 DTO

```jsonc
// SeasonSummaryDto
{ "seasonId": "…", "gameCode": "F1_25", "gameMode": "DriverCareer",
  "firstSessionAt": "…", "lastSessionAt": "…", "roundCount": 6,
  "myPosition": 3, "myPoints": 87,                 // 내가 결과에 없으면 null
  "leaderName": "VERSTAPPEN", "leaderPoints": 120 } // 결과가 없으면 null

// SeasonDetailDto
{ "season": { ...SeasonSummaryDto },
  "rounds": [ { "round": 1, "weekendId": "…", "trackName": "Bahrain", "firstSessionAt": "…",
                "winnerName": "NORRIS",              // 본 레이스 1위. 본 레이스가 없으면 null
                "myPoints": 12,                      // 그 주말 내 점수 합(계산 대상 세션만). 내 결과가 없으면 null
                "sessions": [ { "sessionId": "…", "sessionType": "Race", "sessionKind": "Race",
                                "myPosition": 4, "myResultStatus": "Finished" } ] } ],   // ClassifiedAt 오름차순, 저장된 모든 세션
  "standings": {
    "drivers": [ { "position": 1, "driverKey": "driver:9", "name": "VERSTAPPEN", "teamName": "Red Bull Racing", "teamColor": "#3671C6",
                   "isPlayer": false, "isAiControlled": true, "points": 120, "wins": 3, "podiums": 5,
                   "cells": [ { "round": 1, "position": 1, "resultStatus": "Finished", "points": 25 } ] } ],
    "constructors": [ { "position": 1, "teamId": 2, "teamName": "Red Bull Racing", "teamColor": "#3671C6", "points": 190, "wins": 3 } ] } }

// SessionSummaryDto
{ "sessionId": "…", "classifiedAt": "…", "trackName": "Spa", "sessionType": "Race", "sessionKind": "Race",
  "gameMode": "DriverCareer", "seasonId": null,
  "carCount": 22, "myPosition": 4, "myGridPosition": 6, "myResultStatus": "Finished",
  "myBestLapTimeMs": 105321, "myPoints": 12 }

// SessionDetailDto
{ "session": { ...SessionSummaryDto, "totalLaps": 15, "aiDifficulty": 85, "isNetworkGame": false, "round": 7 },
  "results": [ { "position": 1, "carIndex": 0, "name": "NORRIS", "teamId": 8, "teamName": "McLaren", "teamColor": "#FF8000",
                 "raceNumber": 4, "isAiControlled": true, "isPlayer": false,
                 "gridPosition": 1, "numLaps": 15, "bestLapTimeMs": 104987, "isFastestLap": true,
                 "totalRaceTimeMs": 1598765, "penaltiesTimeMs": 0, "numPenalties": 0, "numPitStops": 1,
                 "points": 25, "resultStatus": "Finished",
                 "tyreStints": [ { "endLap": 7, "visualCompound": "Medium", "actualCompound": "C3" } ] } ] }
```

- **null 규칙(0을 "값 없음"으로 내보내지 않는다 — 기존 `bestValidLapTimeMs`와 같은 방식):**
  `bestLapTimeMs`·`totalRaceTimeMs`·`myBestLapTimeMs`는 0이면 null. 내 차 결과가 없으면 `my*` 전부 null. 시즌이 없으면 `seasonId`·`round` null.
  `teamId`·`raceNumber`는 참가자 정보가 없으면 null. `cell.position`·`cell.resultStatus`는 그 라운드에 본 레이스 기록이 없으면 null.
- `standings.drivers[].cells`는 **그 드라이버가 결과를 가진 라운드만** 담는다(라운드 목록은 `rounds[].round`). 결과표 탭은 `rounds` × `standings.drivers`로 그린다.
- `name`: `DriverName`이 null이면 `Car {carIndex+1}`. `isFastestLap`: `bestLapTimeMs`가 null이 아닌 행 중 최소값(같으면 모두 true).
- `carCount`: 활성 결과 행 수. 시즌 표시 이름은 따로 저장하지 않는다. 앱이 `gameMode` 라벨 + 시작 날짜로 만든다(§8.3).
- 세션 상세의 `round`는 시즌 상세의 라운드 번호와 같은 계산(§7.3)을 쓴다.

### 7.3 계산 (Application, 순수 함수 — 단위 테스트)
- **입력:** 시즌의 활성 결과 행 프로젝션(`SeasonResultRow`: 세션 Id·`SessionType`·`SessionKind`·`ClassifiedAt`·주말 Id, `DriverKey`·이름·carIndex·팀·`IsPlayer`·`IsAi`·순위·상태·점수).
  - 시즌 상세: 그 시즌의 모든 세션 행(주말 7세션 × 22대 × 24라운드 ≈ 3.7천 행, 한 번의 쿼리). Season 탭의 세션 칩은 전체 행을, Standings는 아래 "대상 행"만 쓴다.
  - 시즌 목록: 페이지의 시즌들(최대 20)에서 **대상 행(레이스 세션이거나 점수가 있는 행)만** 한 번의 쿼리로(시즌마다 따로 읽지 않는다 — N+1 금지).
  - 별도 집계 테이블은 두지 않는다(D-24의 "쿼리 온디맨드"와 같은 방식).
  - **포트 분리(CQRS 식):** 읽기는 `ISeasonQueryRepository`·`IGameSessionQueryRepository`(Application, 모두 no tracking) ←
    `SeasonQueryRepository`·`GameSessionQueryRepository`(Infrastructure)가 맡고, 인입용 `ISeasonRepository`·`IGameSessionRepository`(tracked)는 쓰기 경로 전용이다.
    조회 서비스(`SeasonQueryService`·`SessionQueryService`)는 읽기 포트만 쓴다.
- **`SeasonSessionSelector`:** (1) 같은 `(WeekendId, SessionKind)`(Unknown 제외)에서 `ClassifiedAt`이 가장 늦은 세션만 남긴다(D-31 이중 집계 방지).
  (2) 주말별 본 레이스 = 남은 세션 중 `SessionType.Race`이고 `ClassifiedAt`이 가장 늦은 것. 아래 두 계산기가 이 결과를 공유한다.
- **`StandingsCalculator`:** 대상 행에서 드라이버별 점수 합 → D-31 순서로 정렬, `wins`(본 레이스 1위 수), `podiums`(본 레이스 3위 이내 수).
  표시 이름·팀·AI 여부는 그 드라이버의 **가장 최근 세션** 값(이름이 null이면 `Car {carIndex+1}`). Constructors는 팀별 합, 팀이 null인 행은 제외.
  팀 이름 정렬에 쓰도록 `gameCode`를 받아 `TeamCatalog`로 이름을 푼다.
- **우승자 이름(`rounds[].winnerName`):** 본 레이스 1위 행의 표시 이름(그 행의 `DriverName`, null이면 `Car {carIndex+1}`).
- **결과표 칸(`cells`):** 드라이버·라운드마다 순위·상태 = 본 레이스 결과(없으면 null), 점수 = 그 주말 계산 대상 세션의 점수 합(스프린트 포함).
- **`RoundNumbering`:** 시즌 안의 주말을 `FirstSessionAt`, `Id` 순서로 1부터 번호를 매긴다.
- `SeasonSummaryDto`의 `myPosition`·`leader*`도 같은 계산기를 쓴다.

### 7.4 팀 카탈로그 (Application/Seasons/TeamCatalog)
- `Resolve(gameCode, teamId?) → (name, colorHex)`. F1 25: 0 Mercedes · 1 Ferrari · 2 Red Bull Racing · 3 Williams · 4 Aston Martin · 5 Alpine ·
  6 Racing Bulls · 7 Haas · 8 McLaren · 9 Sauber · 41 F1 Generic · 104 My Team · 185~194(2024 차량, 0~9와 같은 이름·색) ·
  476~484(2026, 0~8과 같은 이름·색) · 485 Audi · 486 Cadillac. 색 값은 구현 계획에 둔다.
  없는 ID → `Team {id}` + 중립 회색, `teamId == null` → `Unknown Team` + 중립 회색. 모든 색은 `#RRGGBB`.

---

## 8. App (Flutter)

### 8.1 메뉴 · 경로
- 사이드바 순서: **Dashboard · Seasons · Sessions · Laps · Leaderboard · Telemetry App**(F1Laps 순서를 따른다). `/seasons/:id`·`/sessions/:id`에서도 해당 메뉴가 선택 상태다(기존 `isNavItemSelected`).

| 경로 | 화면 | API |
|---|---|---|
| `/seasons` | 시즌 목록 | `GET /me/seasons` |
| `/seasons/:seasonId?tab=season\|results\|standings` | 시즌 상세(3탭) | `GET /me/seasons/{id}` |
| `/sessions?type=all\|race\|qualifying\|practice` | 세션 목록 | `GET /me/sessions?sessionType=&pageSize=15` |
| `/sessions/:sessionId` | 세션 결과 | `GET /me/sessions/{id}` |

- **쿼리 규칙:** 모르는 `tab` → `season`, 모르는 `type` → `all`. 탭·필터를 바꿀 때는 `Router.neglect`로 감싼 `context.go`로 쿼리만 바꾼다(브라우저 기록에 탭 클릭마다 항목이 쌓이지 않게).
- **페이지 번호는 URL이 아니라 화면 상태**로 둔다(기존 Laps와 같다). 필터를 바꾸면 1페이지로 돌아간다.

### 8.2 기능 폴더 (Feature First, 기존 구조와 같음)
- `features/seasons/{data,domain,application,presentation}`, `features/sessions/{…}`.
- 공통 표시 규칙은 `features/sessions/domain/session_display.dart`의 순수 함수로 두고 시즌 화면도 쓴다: 세션 라벨, 결과 상태 라벨, 시간·gap 형식, 게임 모드 라벨, 패널티 표시.
- **공용 위젯 추출(기존 코드 개선):** `track_laps_page.dart`의 비공개 `_PaginationBar`를 `core/widgets/pagination_bar.dart`의
  `PaginationBar(page, pageSize, total, onPageChanged)`로 옮기고 Laps도 이것을 쓴다. 팀 색 hex 파서는 `core/util/hex_color.dart`의
  `Color parseHexColor(String? hex, {required Color fallback})`(잘못된 값이면 `fallback` — 팀 색은 `AppColors.textMuted`를 넘긴다).
  404 상태 위젯 `NotFoundState`도 Seasons·Sessions가 함께 쓰므로 `core/widgets/not_found_state.dart`에 둔다.
  구현하면서 두 기능이 함께 쓰는 위젯이 더 나와 같은 폴더(`app/lib/core/widgets`)에 두었다: `Stat`, `TeamColorBar`, `AiBadge`, `EmptyStateCard`(§14).
- **목록 모델·화면 이름:** 페이지 응답 모델은 `SessionSummaryPage`·`SeasonSummaryPage`, 화면 위젯은 `SessionsPage`·`SeasonsPage`다(§14).

### 8.3 화면

**Seasons (`/seasons`)** — 카드 목록(20개씩, `PaginationBar`): 게임 모드 배지, `"{모드 라벨} · {시작 yyyy.MM.dd}"`, 기간, `{N} rounds`,
내 순위·점수(`P3 · 87 pts`, 없으면 `-`), 선두(`VERSTAPPEN 120`). 카드 → `/seasons/:id`.
빈 상태: "커리어나 그랑프리 모드에서 세션을 결과 화면까지 마치면 시즌이 기록됩니다." + Telemetry App 링크.

**시즌 상세 (`/seasons/:id`)** — 헤더(모드, 기간, 내 순위·점수) + 탭 3개.
- **Season:** 라운드 목록. 행 = `R{n} · {트랙} · {날짜}` + 우승자 + 내 주말 점수 + 세션 칩(§8.4 라벨, 칩마다 내 순위). 칩 → `/sessions/:id`.
- **Results:** 드라이버 × 라운드 표. **이름 열은 고정**하고 나머지는 가로 스크롤한다(이름 `Column`과 스크롤되는 본문 `Column`을 같은 행 높이 상수로 맞춘다 — 새 패키지 없음).
  칸 = 순위(1·2·3위 금·은·동, DNF·DSQ·NC·RET는 `textMuted` 글자, 기록 없음 `-`), 마지막 열 = 점수. 내 행 강조, 이름 왼쪽에 팀 색 막대.
- **Standings:** Drivers 표(Pos · Driver(AI 배지) · Team · Wins · Podiums · Pts)와 Constructors 표(Pos · Team · Wins · Pts).
  아래 안내: "기록된 세션 기준입니다. 라운드 번호는 기록된 주말 순서라 게임과 다를 수 있습니다."(D-31, §4.2)

**Sessions (`/sessions`)** — 필터 칩(All · Race · Qualifying · Practice) + 표 15개씩(`PaginationBar`).
열: 날짜 · 트랙 · 세션 · 모드 · 결과(`P4 / 22` + 출발 `P6`) · 베스트 랩 · 점수. 행 → `/sessions/:id`.
빈 상태: 필터 없음 → "결과 화면까지 마친 세션이 여기에 기록됩니다." + Telemetry App 링크, 필터 있음 → "이 조건에 맞는 세션이 없습니다."

**세션 결과 (`/sessions/:id`)** — 헤더(트랙, 세션 라벨, 모드, 날짜, AI 난이도, 시즌이면 `R{n}` → `/seasons/{seasonId}?tab=season`) + 결과 표:
Pos · Driver(팀 색 막대, AI 배지, 내 행 강조) · Team · Grid · Laps · Time/Gap · Best(최고 랩은 `fastestLap` 색) · Tyres(컴파운드 원) · Pits · Pen · Pts.

**상태 처리(모든 화면):** 로딩 → 기존 진행 표시, 오류 → 기존 `ErrorRetry`, **404 → "찾을 수 없는 시즌/세션입니다." + 목록으로 가는 링크**(다시 시도는 의미가 없다).

### 8.4 표시 규칙 (순수 함수 — 단위 테스트)
- **세션 라벨:** Practice1~3 → `P1`~`P3`, ShortPractice → `P`, Qualifying1~3 → `Q1`~`Q3`, ShortQualifying → `Q`, OneShotQualifying → `OSQ`,
  SprintShootout1~3 → `SQ1`~`SQ3`, ShortSprintShootout → `SQ`, OneShotSprintShootout → `OSSQ`, Race → `R`, Race2 → `R2`, Race3 → `R3`, TimeTrial → `TT`, Unknown → `-`.
  (스프린트 이름은 §3.3 확인 후 정한다. 그 전까지 번호 그대로 보여 준다.)
- **상태 라벨:** DidNotFinish → `DNF`, Disqualified → `DSQ`, NotClassified → `NC`, Retired → `RET`, Unknown → `-`. Finished·Active는 라벨 없이 시간을 보여 준다.
- **시간:** `formatRaceTime(ms)` = 1시간 미만 `m:ss.SSS`, 이상 `h:mm:ss.SSS`. **gap:** 60초 미만 `+s.SSS`, 이상 `+m:ss.SSS`. 계산이 음수면 `+0.000`.
- **Time/Gap (레이스, `SessionType.Race`):** 기준 행 = 순위가 가장 앞이면서 Finished·Active인 행.
  - 행 상태가 Finished·Active가 아니면 상태 라벨.
  - 기준 행이 없으면 나머지 행은 `-`.
  - 기준 행 자신은 `formatRaceTime(total + penalties)`(total이 null이면 `-`).
  - 그 외: 랩 수가 기준보다 적으면 `+1 Lap` / `+N Laps`(N = 기준 numLaps − 행 numLaps). 같으면 `(행 total + 행 penalties) − (기준 total + 기준 penalties)`의 gap,
    행 또는 기준의 `totalRaceTimeMs`가 null이면 `-`.
- **Time/Gap (연습·예선 등):** 기준 = 베스트 랩이 있는 행 중 가장 빠른 행(상태 무관).
  - 행에 베스트 랩이 없으면 Finished·Active가 아닐 때 상태 라벨, 그 외 `-`.
  - 기준 행 자신은 베스트 랩(`formatRaceTime`), 나머지는 베스트 랩 차 gap. (베스트 랩이 있는 행이 하나도 없으면 첫 규칙만 적용된다)
- **Pen:** `numPenalties == 0`이면 `-`, 패널티 시간이 있으면 `+{초}s ({개수})`, 시간이 0이면 `({개수})`.
- **반응형:** 너비 판정은 `LayoutBuilder`의 **콘텐츠 영역 폭**(사이드바 220px 제외)으로 한다. 세션 결과 표는 `kSessionTableCompactWidth = 600` 미만에서
  Grid · Tyres · Pits · Pen 열을 숨기고, 그래도 넘치면 가로 스크롤한다. Sessions 표·Standings 표도 좁으면 Laps처럼 가로 스크롤한다.

### 8.5 색
- 팀 색은 API 값(`parseHexColor`). `AppColors`에 토큰 추가: `podiumGold`, `podiumSilver`, `podiumBronze`,
  `fastestLap`(`accent` 인디고와 뚜렷이 다른 자홍색 `#D946EF`), `tyreSoft`(빨강), `tyreMedium`(노랑), `tyreHard`(흰색), `tyreIntermediate`(초록), `tyreWet`(파랑).

---

## 9. 오류 처리

| 상황 | 처리 |
|---|---|
| `SessionClassified` JSON 구조 오류·빈 페이로드·검증 실패 | `IngestResult.Reject(사유)` → Agent는 Outbox에서 지운다(영구 무효, 기존 규칙) |
| 모르는 enum 문자열(게임 업데이트) | 0번 대체값으로 저장(Reject하지 않음) |
| `sessionRef`에 NUL 문자 · `raceNumber` 음수 | Reject(검증 실패). `driverName`·`actualCompound`의 NUL은 Reject하지 않고 첫 NUL에서 잘라 저장 |
| 트랙 매핑 없음 | Reject(랩과 같은 문구 형식) |
| Time Trial 순위표 · 늦게 도착한 옛 결과 | 변경 없이 Ack + 멱등 기록(Ignored) |
| 같은 키인데 트랙·세션 종류가 다름 | `uid:` 키로 따로 저장 + 경고 로그 |
| 해제된 장치 | 기존 Reject("연결이 해제된 장치입니다.") — 유형 분기 전에 걸러진다 |
| 동시 업서트 unique 위반 | 허브 오류 → Agent 재시도(일시 장애, §6.3) |
| Agent: 직렬화 크기 48KiB 초과 | 스틴트를 빼고 재시도 + 경고, 그래도 크면 버림 + 오류 로그 |
| Agent가 맥락 없는 순위표를 받음(세션 도중 Agent 시작 등) | 보내지 않는다(데이터 1건 손실) |
| 분석기 하나의 예외 | 그 분석기만 건너뛰고 오류 로그(다른 분석기는 계속) |
| 남의·없는·GUID 아닌 시즌/세션 | 404 ProblemDetails(앱은 "찾을 수 없음" 상태) |
| 잘못된 `sessionType` | 400(Validation, 표준 형식) |
| 앱: 그 밖의 조회 실패 | 기존 `ErrorRetry` 위젯 |

---

## 10. 테스트 (TDD, 커버리지 80% 목표)

**Agent — Core.Tests**
- `SessionResultTracker`: 맥락·참가자·순위표가 있으면 1건 생성(carIndex로 합침, `isPlayer`), 같은 `SessionRef` 두 번째 순위표 무시,
  다른 `SessionRef` 순위표 무시, 맥락 없음 무시, Time Trial 무시, 참가자 없는 차는 null 필드·`isAiControlled` false, `SessionRef`가 바뀌면 참가자 초기화,
  `SessionEnded` 뒤에 온 같은 세션 순위표도 1건.
- `LapAnalyzer`: `LapFinished`에 모드·링크 3개가 실린다. 기존 테스트는 수정 없이 통과(기본값 매개변수).

**Agent — Infrastructure.Tests**
- `F1PacketMapper`·`F1EnumMaps`: 세션 신규 필드·`GameMode` 매핑 표, 참가자(`NetworkHuman` → null), 순위표(빈 칸 제외, 시간 단위 변환, 스틴트 개수, 컴파운드 매핑).
- 파이프라인: 분석기 하나가 예외를 던져도 다른 분석기의 이벤트는 Outbox에 들어간다. DI가 두 분석기를 등록한다.
- 직렬화·크기: `SessionClassified` wire JSON(camelCase, enum 문자열), 게임 최대 페이로드(24대 × 8스틴트, 비ASCII 이름 10자 = UTF-8 30바이트) ≤ 48KiB,
  48KiB를 넘는 가짜 페이로드는 스틴트 없이 들어가고, 그래도 넘으면 적재되지 않는다.

**Backend — Domain.Tests**
- `SeasonPolicy`(모드별·링크 0), `SessionKeys.For`(시즌 대상 + 링크 → link, 시즌 대상 아님 → uid, 세션 링크 0 → uid), `DriverKeys`(player·driver·name·car, 이름 정규화),
  `ReplaceResults`(같은 carIndex 제자리 갱신·스틴트 교체, 없는 차 soft delete, 새 차 추가, 이미 삭제된 행 무시), `Season`·`RaceWeekend.Touch`, 새 엔티티 기본값.

**Backend — Application.Tests**
- 인입: 신규 생성(시즌·주말·세션·결과·스틴트), 시즌 대상 아님 → 세션만·uid 키, 같은 키 재분류 → 병합, 옛 결과 → Ignored(시즌 시각도 불변),
  Time Trial → Ignored, 트랙·종류 불일치 → uid 키로 새 세션, 미래 시각 → 서버 시각 + 5분으로 자름, 모르는 enum → 대체값,
  구조 오류·검증 실패 → Reject(아무것도 추적 안 됨), 트랙 없음 → Reject, `ProcessedEvent`와 한 번에 커밋, `LapFinished`가 `SessionKey` 저장(옛 페이로드 → uid).
- `SeasonSessionSelector`: 같은 주말·종류 중복 → 최신 1건, Unknown은 중복 제거 안 함, 본 레이스 = 가장 늦은 레이스.
- `StandingsCalculator`: 점수 합, 중복 세션 이중 집계 없음, soft delete된 행 미포함(입력에 없음), 카운트백(본 레이스만, 스프린트 우승 제외), 이름 정렬,
  최근 이름·팀, Constructors 합·우승·팀 없음 제외·동점 정렬.
- 결과표 칸: 본 레이스 순위, 주말 점수 합(스프린트 포함), 레이스 없는 주말 null.
- 조회 서비스: 내 것만·남의 것 404, 페이지 보정, 시즌 목록이 한 번의 결과 행 조회로 여러 시즌을 계산(저장소 호출 수 검증), 플레이어 없음·선두 없음 → null,
  `sessionType` 필터, `isFastestLap`, 0 → null, `name` 대체값, 세션 상세 `round` = 시즌 라운드.
- `TeamCatalog`: 알려진 ID, 없는 ID, null, 모든 색이 `#RRGGBB`.

**Backend — Api.IntegrationTests (PostgreSQL)**
- 연결 → 허브로 `SessionClassified` 22대(2라운드 × 예선·레이스) 전송 → `/me/seasons`·`/me/seasons/{id}`·`/me/sessions`·`/me/sessions/{id}` 확인.
- 같은 세션 키 재전송(차 수를 줄임, 다른 eventId) → 활성 행 수 = 새 차 수, `game_sessions` 1개 유지.
- 검증 상한 페이로드(32대 × 8스틴트, 비ASCII 이름 64자 — 와이어 실측 약 32~34KB, 기본 32KB 한도를 넘고 64KiB 이하임을 단언)가 허브를 통과한다(명시한 64KiB 한도 회귀).
  같은 키·주말에 트랙이 다른 순위표 → 시즌 없는 별도 세션. 병합 경로에서 새 행이 INSERT된다(`ValueGeneratedNever` 회귀). `LapFinished`의 `session_key` 저장.
- 새 사용자 빈 페이지, 다른 사용자 토큰 → 404, GUID 아님 → 404, 토큰 없음 → 401, `sessionType=TimeTrial`·`4`·오타 → 400 표준 형식.

**App (flutter test)**
- 모델 `fromJson`, 표시 규칙(§8.4의 모든 경우: 라벨 전체, 상태 7종, 시간 1시간 경계, gap 60초 경계·음수·랩 차이·기준 행 DNF·null 시간, 예선 기준 없음, Pen 3종), `parseHexColor` 대체값.
- 저장소: 필터 → `sessionType` 매핑, `pageSize=15`(기존 `devices_repository_test` 방식).
- 화면: Seasons 빈 상태·목록·페이지, 시즌 상세 탭 쿼리(모르는 값 → season), Results 고정 열 + 좁은 폭에서 넘침 없음, Standings 안내 문구,
  Sessions 필터(1페이지로 초기화)·필터 결과 없음 문구·플레이어 없음 `-`, 세션 결과 좁은 화면 열 숨김, 404 상태, 다시 시도, 라우터 경로·메뉴 순서·상세 경로에서 메뉴 선택, Laps가 공용 `PaginationBar`로 동작.

---

## 11. 문서 · 계약 갱신 (구현과 함께)

- **CLAUDE.md:** Agent Rules의 도메인 이벤트 목록에 `SessionClassified`(세션당 최종 순위표 1건) 추가, Confirmed Decisions에 시즌 묶음(D-29)·Standings(D-31) 한 줄.
- **docs/08:** D-28~D-34 추가, 요약표 갱신. **docs/11 §0:** P7 행에 이 문서 링크.
- **docs/02 · 03 · 04 · 05 · 06:** 도메인(시즌 계층), 엔티티, API, 허브 이벤트 유형·메시지 한도, 파싱 패킷 목록(Participants·Final Classification 추가).
- **shared/schema:** `session_classified.json` 신규, `telemetry_envelope.json`의 `type` enum, `lap_finished.json`에 선택 필드 4개.
- **shared/samples:** `telemetry_session_classified_envelope.json`(22대 예시). **shared/openapi/openapi.yaml:** §7 경로·스키마.
- **docs/PROGRESS.md · TESTING-local-e2e.md:** P7 진행 상황, 게임으로 확인하는 절차(§3.3 가정 확인 체크리스트).

---

## 12. P7에서 하지 않는 것

- 세션 Details(랩별 랩타임 · 스틴트별 마모·랩타임 · 패널티 내역), 그랑프리 주말 상세 화면 — P8
- 랩 ↔ 세션 연결 조회(`Lap.SessionKey` 저장만 한다), Time Trial 세션 목록
- 시즌 이름 변경·삭제·숨기기, 게임 공식 순위표와의 동기화, 라운드 일정(앞으로 남은 레이스)
- Dashboard 시즌 카드, Seasons·Sessions 실시간 갱신(SignalR), Agent Tray의 결과 전송 표시
- **Agent Outbox 독성 항목 처리**(같은 항목이 허브 예외로 N번 연속 실패하면 dead-letter로 옮겨 뒤의 항목을 막지 않기) — 기존부터 있던 일반 위험이라 별도 작업으로 한다

---

## 13. 리뷰 반영 내역 (2026-10-17)

설계 초안을 두 관점(아키텍처·도메인 / API·앱·테스트)으로 리뷰해 아래를 바꿨다.

| 지적 | 반영 |
|---|---|
| 허브 예외는 Agent가 무한 재시도 → 같은 입력에 항상 실패하는 예외가 있으면 업로드 전체가 멈춘다 | §0 실패 원칙 추가. 결과 교체를 carIndex 제자리 갱신으로(§4.5), 모든 unique index에 soft-delete 필터(§4.1), 모르는 enum 관대 처리(§6.2), 허브 한도 64KiB 명시 + Agent 48KiB 사전 검사(§5.5), 검증 한도를 게임 실제 값에 맞춤(32대·8스틴트) |
| 한 번의 SaveChanges에서 soft delete + 같은 키 INSERT는 unique 위반 가능, `Remove`는 실제 삭제 | §4.5 제자리 갱신, `Remove`·`Clear` 금지, `UpdatedAt` 직접 설정 |
| 링크 ID가 바뀌면 같은 주말에 레이스 2건 → Standings 이중 집계 | D-31·§7.3 `SeasonSessionSelector`(같은 주말·종류 최신 1건) |
| 스프린트가 우승·카운트백에 섞임, Constructors 우승·동점 미정의 | D-31 본 레이스 기준으로 통일, Constructors 규칙 정의 |
| 링크 값 의미가 불확실한 모드에서 다른 세션이 덮일 수 있음 | D-29 link 키는 시즌 대상 모드만, 트랙·종류 불일치 시 uid 키 |
| 처리 순서 모순(옛 결과 판정 전에 시즌 시각을 넓힘), Reject 시 반쯤 만든 그래프 저장 위험 | §6.2 순서 재배열 + 불변식, Stored/Ignored/Rejected 결과 정의 |
| Time Trial을 Agent만 거름(D-15 위반) | D-30 백엔드도 Ignored |
| 초안의 `Lap.SessionRef` 저장만으로는 여러 UID에 걸친 세션의 랩을 못 찾음 | §4.6 `LapFinished`에 맥락 필드 추가 + `Lap.SessionKey` |
| `car:{carIndex}` 키가 다른 라운드의 다른 드라이버를 합침 | D-32 `car:{SessionRef}:{carIndex}` |
| `RaceWeekend`의 중복 열, Agent 시계가 앞선 경우 | `(SeasonId, WeekendLinkId)` 키, `ClassifiedAt` 상한(서버 + 5분) |
| 분석기 순서 의존 문서화, 한 분석기의 예외가 다른 분석기를 막음 | §5.5 순서 무관 명시 + 분석기별 try/catch |
| 시즌 상세 DTO의 중복 배열, 쓰지 않는 필드, 0을 "없음"으로 사용 | §7.2 `standings.drivers[].cells`로 합침, 미사용 필드 제거, 0 → null |
| `sessionType` 열거형 바인딩은 TimeTrial·숫자를 받고 표준 400 형식이 아님, 기본 페이지 크기 불일치 | §7.1 문자열 파싱 + `ValidationException`, 서버 기본 20·앱이 15 전송, `:guid` 제약 |
| gap·시간 표시 규칙 모호, 상태·라벨 일부 누락 | §8.4 전면 정의 |
| 공용 페이지 컴포넌트가 실제로는 비공개, URL 페이지 처리 미정의, 고정 열 구현 수단, 빈·404 상태 | §8.2 `PaginationBar` 추출, §8.1 페이지는 화면 상태·탭은 `Router.neglect`, §8.3 고정 열 방식·상태 처리 |
| 시즌 목록 쿼리 크기 | §7.1 최대 20, §7.3 필요한 행만 한 번에 |

**2차 확인(수정본 검증)에서 추가로 바꾼 것**

| 지적 | 반영 |
|---|---|
| Guid 키 기본값(`ValueGeneratedOnAdd`) 때문에 병합 시 새 행이 UPDATE로 나가 매번 실패 | §4.5 새 엔티티 `ValueGeneratedNever()` |
| 열 길이·null 원소 등 DB에서만 걸리는 값이 검증에 빠짐 | §6.2-2 필드별 규칙 전부 나열, 이름 공백 → null 정규화, §4.6 긴 `sessionRef`는 키 없음 |
| 트랙이 달라 `uid:`로 저장한 세션이 원래 주말에 섞임 | §6.2-6·8 대체된 세션은 시즌·주말에 넣지 않음 |
| 목록 카드와 상세의 Standings 대상이 달라 순위가 어긋날 수 있음, 이름이 같을 때 최종 기준 없음 | D-31 대상 행을 한 가지로 정의, `DriverKey`·팀 ID 최종 기준 |
| 허브 한도 회귀 테스트가 기본 32KB 아래 크기라 검증이 안 됨 | §10 약 44KB 페이로드로 시험(구현 후 실측은 약 32~34KB — §14) |
| 그 밖: 숫자 `sessionType` 거부 방식, 분석기 순서 근거, Grand Prix 원시 값 3, 스프린트만 있는 주말, 우승자 이름 출처, `NotFoundState` 위치, 예선 기준 행 규칙 | 각 절에 반영 |

---

## 14. 구현 중 달라진 점 (2026-10-18)

구현하면서 설계와 달라지거나 설계에 없던 것을 모았다. 해당 절에도 같은 내용을 반영했다.

| 항목 | 설계 | 구현 | 이유 |
|---|---|---|---|
| 읽기 포트 | 인입 저장소(`ISeasonRepository`·`IGameSessionRepository`)에 조회 메서드 추가 | 읽기 전용 포트를 따로 둔다: `ISeasonQueryRepository`·`IGameSessionQueryRepository`(Application) ← `SeasonQueryRepository`·`GameSessionQueryRepository`(Infrastructure). 쓰기 포트는 인입 전용 | 조회 서비스 태스크가 저장소 구현보다 앞서 끝나므로, 쓰기 포트에 메서드를 더하면 Infrastructure가 컴파일되지 않는다. 읽기(no tracking)와 쓰기(tracked)를 나누는 CQRS 식 분리로 매 단계를 초록으로 유지했다 |
| NUL 문자 | 언급 없음 | `sessionRef`에 NUL이 있으면 검증 Reject. `driverName`·`actualCompound`는 첫 NUL에서 잘라 저장(자른 뒤 앞뒤 공백 제거, 비면 null). `Lap.SessionKey`는 `sessionRef`가 비었거나 32자 초과이거나 NUL을 품으면 null. Agent 매퍼도 이름을 NUL에서 자른다 | PostgreSQL 텍스트 열은 NUL을 저장하지 못해 저장 시 예외 → 같은 항목 무한 재시도(§0). UDP 이름은 NUL로 채워진 고정 길이 문자열이 정상 형태라 이름은 Reject가 아니라 잘라낸다 |
| `raceNumber` 검증 | 언급 없음 | `raceNumber`(있다면) ≥ 0 | 음수면 `name:{NAME}#{raceNumber}` 키가 길어져 `DriverKey`(80자)를 넘을 수 있다 |
| Agent 시간값 보정 | 단위 변환만 | `TotalRaceTime`이 NaN·0 이하이면 0, `int.MaxValue` 이상이면 `int.MaxValue`. `BestLapTimeInMS`(uint)는 `int.MaxValue`로 자른다 | 백엔드는 음수를 영구 Reject하므로 깨진 값 하나로 세션 전체가 사라지지 않게 한다 |
| 빈 순위표 | §5.3에 없음 | 트래커가 무시하고 `SessionRef`를 보낸 것으로 기억하지 않는다(§5.3 규칙 3) | 백엔드는 `results` 1~32개가 아니면 항상 Reject — 보내면 영구 Reject가 되고 "세션당 1회" 슬롯만 소모한다 |
| 메시지 크기 실측 | 게임 최대 약 30KB, 검증 상한 페이로드 약 44KB(추정) | Agent 쪽 직렬화(UTF-8 바이트): 24대 × 8스틴트 × 비ASCII 이름 10자 = 23,778 B, 이름 64자 = 31,554 B. 백엔드 통합 테스트의 검증 상한 페이로드(32대 × 8스틴트 × 이름 64자)는 SignalR 와이어에서 약 32~34KB(허브 프로토콜은 비ASCII를 escape하지 않아 설계 추정 약 44KB보다 작다. Agent Outbox 직렬화는 `System.Text.Json` 기본값이라 escape하므로 Agent 쪽 수치가 더 크고 48KiB 검사는 보수적이다). 한도는 그대로: Agent 48KiB, 허브 64KiB | 추정치를 실측으로 교체. 검증 상한 페이로드가 기본 한도(32KB)를 넘으면서 64KiB 아래라 한도 명시 회귀 테스트가 성립한다 |
| 점수 합계 | 언급 없음 | `StandingsCalculator`가 점수를 `long`으로 합산하고 표시 값만 `int` 상한으로 자른다 | 검증이 점수를 `int.MaxValue`까지 허용해, `int` 합산이면 시즌 조회가 `OverflowException`으로 매번 실패할 수 있다 |
| 목록 vs 상세 칸 | 같은 대상 행 | 시즌 목록은 대상 행(레이스이거나 점수 있는 행)만 읽고 상세는 전체 행을 읽는다. 순위·점수·우승·포디움·Constructors는 같고, 예선·연습만 있는 주말의 빈 칸(`-`, 0점)만 상세에서만 보인다 | 목록 쿼리 크기를 줄이기 위함(§7.3). 목록은 칸을 쓰지 않아 화면에 영향 없음 |
| Flutter 모델·위젯 이름 | 구현 계획에서 응답 모델과 화면 위젯이 같은 이름(`SessionsPage`·`SeasonsPage`) | 페이지 응답 모델 `SessionSummaryPage`·`SeasonSummaryPage`, 화면 위젯 `SessionsPage`·`SeasonsPage` | 모델과 위젯 이름 충돌 해소 |
| Flutter 공용 위젯 | `PaginationBar`·`NotFoundState` | `PaginationBar`·`NotFoundState`에 더해 `Stat`·`TeamColorBar`·`AiBadge`·`EmptyStateCard`도 `app/lib/core/widgets`에 둔다 | Seasons·Sessions·Laps가 같은 조각을 쓰게 되어 |

**남은 사항**
- §3.3의 가정 8개는 게임으로 확인하지 못했다. 절차: [TESTING-local-e2e.md](./TESTING-local-e2e.md) §10.
- `TelemetryHub.MaxMessageBytes`의 주석은 가장 큰 `SessionClassified`를 "약 30KB"로 적고 있다. 실측(위)과 조금 다르며 한도 판단(64KiB)에는 영향이 없다.
