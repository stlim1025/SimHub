# 05 · SignalR Event Design

> Status: **Design (미승인)** · Last Updated: 2026-10-18 (P7 `SessionClassified` 반영, 앞서 P6 개인 모드 반영)
> 계약 원본: `shared/schema/*.json`. 두 개의 Hub로 **인입(Ingest)**과 **브로드캐스트(Broadcast)**를 분리한다.
> P6에서 Agent 인증이 좌석 키에서 **장치 키**로 바뀌었고 envelope의 `rigCode`가 사라졌다(D-25·D-26, [11](./11-personal-mode.md) §5).
> P7에서 이벤트 유형 `SessionClassified`(세션당 최종 순위표 1건)와 인입 메시지 한도(`TelemetryHub.MaxMessageBytes` 64KiB)가 추가됐다(D-28, [12](./12-seasons-sessions.md) §5.5·§6).

---

## 1. 설계 원칙

- **REST = 조회/명령, SignalR = 실시간 이벤트.** (헌장 SignalR Rules)
- **관심사에 따라 Hub 2개로 분리:**
  1. `TelemetryHub` — Agent → Backend (신뢰된 이벤트 인입)
  2. `RankingHub` — Backend → App (읽기 전용 브로드캐스트)
- 두 Hub는 **인증 주체와 신뢰 수준이 다르므로** 반드시 분리한다. (보안·SRP)
- 모든 payload는 camelCase, 시간은 ISO-8601 UTC.

```
[Agent] ──TelemetryHub(invoke)──► [Backend] ──처리/영속화──► [RankingHub(broadcast)] ──► [App]
```

---

## 2. TelemetryHub — Agent → Backend (Ingest)

### 2.1 연결/인증

- Endpoint: `/hubs/telemetry`
- 인증: **장치 키**(`AgentDevice`별 장기 키). 헤더 `X-Agent-Key`(대체 수단으로 `access_token` 쿼리), 서버는 SHA-256 해시로 장치를 특정한다.
  사용자 JWT와 완전히 분리된 `AgentApiKey` 스킴이다. → D-26 (연결 코드를 장치 키로 교환하는 흐름은 [11](./11-personal-mode.md) §4)
- 연결에 귀속되는 클레임: `deviceId`(AgentDevice.Id), `sub`(장치 주인 UserId). `rigCode` 클레임은 없다.
- **연결 해제된 장치의 키로 새로 연결하면 401.** Agent는 재시도를 멈추고 `다시 연결 필요` 상태가 된다.
- 그룹: 사용하지 않는다(좌석 그룹 폐지).

### 2.2 Client → Server (Agent가 호출)

| 메서드 | Payload | 설명 |
|---|---|---|
| `SubmitEvent` | `TelemetryEnvelope` | 모든 도메인 이벤트를 단일 진입점으로 전송 |

> **단일 메서드 + Envelope 패턴** 채택 이유: 이벤트 종류가 늘어도 Hub 시그니처가 안 바뀜(OCP).
> Agent의 Outbox flush 로직도 단순해진다.

### 2.3 `TelemetryEnvelope` 계약

```jsonc
{
  "eventId": "guid",              // Agent 생성, 멱등키 (중복 재전송 대비)
  "gameCode": "F1_25",
  "occurredAt": "2026-07-06T09:00:00Z",  // 게임 이벤트 발생 시각(Agent 로컬→UTC)
  "type": "LapFinished",          // 이벤트 타입 (아래 표)
  "payload": { /* type별 상이 */ }
}
```

### 2.4 이벤트 타입별 payload

| type | payload 핵심 필드 |
|---|---|
| `SessionStarted` | `{ sessionRef, trackId, sessionType }` — sessionType 필수(D-16) |
| `LapStarted` | `{ sessionRef, lapNumber }` |
| `SectorCompleted` | `{ sessionRef, lapNumber, sectorNumber, sectorTimeMs }` |
| `LapFinished` | `{ sessionRef, lapNumber, lapTimeMs, sectors[], isValid, trackId }` — sectors는 가변 배열(D-7) |
| `SessionEnded` | `{ sessionRef }` |
| `SessionClassified` (P7) | `{ sessionRef, trackId, sessionType, sessionKind, gameMode, seasonLinkId, weekendLinkId, sessionLinkId, totalLaps, aiDifficulty, isNetworkGame, results[] }` — 세션당 최종 순위표 1건(D-28) |

`sectors[]` = `[{ sectorNumber, sectorTimeMs }, ...]` (게임별 개수 상이).
`sessionType` = 게임 세션 모드. 랭킹 적격 판정은 Backend가 수행(D-15/D-16).

- `sessionRef` = Agent 로컬 게임세션 식별자(`m_sessionUID`). P7부터 서버가 `GameSession.SessionRef`로 저장한다.
- **`LapFinished` 선택 필드(P7):** `gameMode`, `seasonLinkId`, `weekendLinkId`, `sessionLinkId`. 서버가 `Lap.SessionKey`를 계산해 저장한다(조회는 P8). 옛 Agent는 보내지 않으며 이때 키는 `uid:{sessionRef}`다.
- `trackId` = 게임 UDP의 트랙 정수 ID → Backend가 Track 마스터로 변환.
- **귀속:** 서버는 envelope이 아니라 **인증된 장치**를 신뢰한다. `Lap.UserId = device.UserId`, `Lap.AgentDeviceId = device.Id`.

**`SessionClassified` payload (P7 · D-28)** — 계약 원본 `shared/schema/session_classified.json`, 예시 `shared/samples/telemetry_session_classified_envelope.json`(22대)
```jsonc
{
  "sessionRef": "1844674407370955161", "trackId": 10,
  "sessionType": "Race", "sessionKind": "Race", "gameMode": "DriverCareer",       // enum은 문자열
  "seasonLinkId": 2847561234, "weekendLinkId": 99112233, "sessionLinkId": 44556677,
  "totalLaps": 29, "aiDifficulty": 85, "isNetworkGame": false,
  "results": [ {
      "carIndex": 3, "isPlayer": true,
      "position": 1, "gridPosition": 2, "numLaps": 29, "points": 25,
      "numPitStops": 1, "numPenalties": 0, "resultStatus": "Finished",
      "bestLapTimeMs": 81234, "totalRaceTimeMs": 2493120, "penaltiesTimeMs": 0,
      "driverName": "S. LIM", "gameDriverId": null, "teamId": 2, "raceNumber": 26, "isAiControlled": false,
      "tyreStints": [ { "endLap": 14, "visualCompound": "Medium", "actualCompound": "C3" },
                      { "endLap": 29, "visualCompound": "Hard", "actualCompound": "C2" } ] } ]
}
```
- Agent가 Final Classification 패킷과 같은 세션의 Session·Participants 정보를 `carIndex`로 합쳐 만든다. **같은 `sessionRef`로는 한 번만** 보낸다(raw 패킷은 보내지 않는다).
- 참가자 정보가 없는 차는 `driverName`·`gameDriverId`·`teamId`·`raceNumber`가 null, `isAiControlled`가 false다.
- enum 문자열(`sessionType`·`sessionKind`·`gameMode`·`resultStatus`·`visualCompound`)은 대소문자를 무시하고 해석하며, **모르는 값은 0번 대체값**(`Other`/`Unknown`)으로 받는다(게임 업데이트로 값이 늘어도 세션당 한 번뿐인 이벤트를 잃지 않는다).
- `Time Trial` 순위표는 저장하지 않고 Ack한다(D-30). 같은 세션 키로 다시 오면 최신 결과로 병합한다(D-29).

### 2.5 서버 응답 (Ack / Reject)

D-23 정련: `SubmitEvent`는 별도 S→C 메서드 대신 **반환값 `IngestResult{acknowledged, rejectReason}`** 으로 응답한다(요청/응답).

| 응답 | 용도 |
|---|---|
| Ack | 수신·처리 확인 → Agent가 Outbox에서 flush |
| Reject(reason) | 영구 무효(파싱 실패·트랙 매핑 없음·검증 실패). Agent는 Outbox에서 폐기, 서버는 로깅 |
| Reject("연결이 해제된 장치입니다.") | **예외:** 이벤트가 아니라 장치 키가 무효. Agent는 그 항목을 **Outbox에 남기고** 업로드를 멈춘 뒤 `다시 연결 필요`로 바뀐다(401과 같은 처리) |

> **멱등성:** Backend는 `eventId`로 중복을 걸러낸다(재전송 안전). Agent는 응답을 받을 때까지 Outbox 보관(무응답만 재전송).
> **해제된 장치:** 이미 열린 연결로 이벤트를 보내도 인입 시 장치를 다시 확인해 Reject("연결이 해제된 장치입니다.")한다.
> Agent는 이 사유 문구를 **정확히 비교해** 일반 Reject와 구분한다(서버 `TelemetryIngestService.RevokedDeviceReason` =
> Agent `TelemetryUploadService.RevokedDeviceRejectReason`, 바꿀 때 함께 바꾼다). 세션을 닫고 다른 키가 저장될 때까지 기다리며,
> 같은 키로 새로 연결하면 401이다. 새 코드로 다시 연결하면 남겨 둔 항목부터 올라간다([11](./11-personal-mode.md) §6.4).
> `AgentDevice.LastSeenAt`은 모든 이벤트 유형에서 갱신하되 1분에 한 번만 쓴다.

**`SessionClassified`의 응답 (P7)**

| 결과 | 조건 | 응답 |
|---|---|---|
| Stored | 새 세션 저장 또는 같은 세션 키 병합 | Ack + 멱등 기록 |
| Ignored | Time Trial(`sessionType`/`gameMode`), 이미 저장된 것보다 이른 옛 결과 | Ack + 멱등 기록(변경 없음) |
| Rejected | 아래 사유 | Reject(reason) — 영구 무효 |

Reject 사유(고정 문구): `"SessionClassified payload 파싱 실패"`, `"SessionClassified payload가 비어 있습니다."`, `"SessionClassified 검증 실패: {상세}"`,
트랙 없음은 랩과 같은 `"트랙 매핑 없음(gameCode=…, trackId=…)"`. 검증은 DB 열 제약에 걸릴 값(길이·NUL·음수 등)을 모두 여기서 거른다 — 저장 시점 예외는 허브 오류로 Agent에 돌아가 같은 항목이 끝없이 재시도되기 때문이다.

### 2.6 메시지 크기 한도 (P7)

- 허브가 받는 메시지의 최대 크기는 **`TelemetryHub.MaxMessageBytes` = 64KiB**(`AddHubOptions<TelemetryHub>`로 명시, SignalR 기본 32KB에 기대지 않는다).
  한도를 넘는 메시지는 Reject가 아니라 **연결 종료**라 Agent가 같은 Outbox 항목을 끝없이 재시도하게 되므로, 서버가 한도를 정하고 Agent가 먼저 지킨다.
- Agent는 Outbox에 넣기 전에 직렬화 크기(UTF-8 바이트)를 재서 **48KiB**(`OutboxTelemetrySink.MaxEnvelopeBytes`)를 넘으면 `SessionClassified`의 타이어 스틴트를 빼고 다시 잰다(경고 로그).
  그래도 넘거나 다른 유형이면 적재하지 않고 오류 로그를 남긴다.
- 실측: 검증 상한 `SessionClassified`(32대 × 8스틴트, 비ASCII 이름 64자)는 SignalR 와이어에서 약 32~34KB다. SignalR 허브 프로토콜은 비ASCII를 `\uXXXX`로 escape하지 않아 와이어 크기가 설계 추정(약 44KB, escape를 가정)보다 작다. 반면 Agent의 Outbox 직렬화(`System.Text.Json` 기본값)는 비ASCII를 escape하므로 Agent 쪽 수치가 와이어보다 크고, 그래서 48KiB 검사는 보수적이다. 게임 최대(24대 × 8스틴트)는 Agent 쪽 직렬화 기준 약 24KB(이름이 검증 한도인 비ASCII 64자까지 길어도 약 32KB). 22대 × 스틴트 2~3개는 약 10KB로 추정한다(측정하지 않음).
- 배포 순서: **백엔드 → Agent**. 옛 백엔드는 모르는 이벤트 유형을 Ack하고 버리므로(데이터 손실) 새 Agent를 먼저 배포하면 안 된다.

---

## 3. RankingHub — Backend → App (Broadcast)

### 3.1 연결/인증

- Endpoint: `/hubs/ranking`
- 인증: 사용자 JWT.
- 그룹: `track:{trackId}` (관심 트랙 랭킹 구독), `user:{userId}`(개인 알림).

### 3.2 Server → Client (App이 수신)

| 이벤트(메서드명) | Payload | 설명 |
|---|---|---|
| `RankingUpdated` | `RankingSnapshot` | 특정 트랙 TOP10 갱신 |
| `LapRecorded` | `LapRecordedNotice` | 새 랩 저장됨(무효 랩 포함) — **그 랩 주인에게만**(`Clients.User`, JWT `sub`). 앱은 알림을 띄우고 랩 목록을 다시 불러온다(D-50, [15](./15-lap-detail-telemetry.md) §9) |
| `PersonalBestAchieved` | `PersonalBestNotice` | 내 개인 최고 갱신 |

### 3.3 Client → Server (App이 호출)

| 메서드 | 용도 |
|---|---|
| `SubscribeTrack(trackId)` | 해당 트랙 랭킹 그룹 가입 |
| `UnsubscribeTrack(trackId)` | 그룹 탈퇴 |

### 3.4 payload 계약

```jsonc
// RankingUpdated  (실시간 랭킹은 Time Trial · monthly 기준으로 브로드캐스트, D-8a)
{
  "trackId": "guid",
  "gameCode": "F1_25",
  "period": "monthly",
  "periodKey": "2026-07",
  "entries": [
    { "rank": 1, "displayName": "홍길동", "bestLapTimeMs": 83452, "setAt": "..." }
  ]
}

// ↑ entries[].displayName: 랭킹 이름 비공개 사용자(showOnLeaderboard=false)는 "익명 드라이버"(D-39, 14 §6). REST /rankings와 같다.

// LapRecorded (D-50) — GET /me/laps의 랩 한 건(LapDto)과 같은 모양 + trackId. userId는 없다(받는 사람이 주인뿐).
{ "lapId": "guid", "trackId": "guid", "trackName": "Jeddah", "gameCode": "F1_25", "sessionType": "TimeTrial",
  "lapTimeMs": 98448, "sectors": [ … ], "isValid": true, "isRankingEligible": true, "setAt": "...",
  "lapNumber": 6, "gameMode": "TimeTrial", "team": { "name": "Ferrari", "color": "#E8002D" }, "weather": "Clear", "hasTrace": true }

// PersonalBestAchieved
{ "userId": "guid", "trackId": "guid", "lapTimeMs": 83452, "previousBestMs": 84120 }
```

> App은 SignalR로 갱신 신호를 받고, 필요 시 REST로 최신 전체 데이터를 재조회하거나
> payload를 직접 반영한다. (MVP: TOP10은 payload를 직접 반영해 즉시 갱신)

---

## 4. 전체 시퀀스 (LapFinished → TOP10 갱신)

```
Agent                TelemetryHub          Backend App-Service        RankingHub          App
  │  SubmitEvent(env)     │                      │                        │                │
  ├──────────────────────►│  검증/멱등체크        │                        │                │
  │                       ├─► 장치확인·Lap저장 ──►│                        │                │
  │                       │                      ├─ 랭킹 재계산            │                │
  │       Ack(eventId)    │◄─────────────────────┤                        │                │
  │◄──────────────────────┤                      ├─ RankingUpdated ──────►│  broadcast ───►│
  │  (Outbox flush)       │                      ├─ (PB면)PersonalBest ──►│  (user group)─►│
```

---

## 5. 연결 복원력 (App / Agent 공통)

- **Agent:** 자동 재접속(지수 백오프). 끊김 중 이벤트는 SQLite Outbox에 적재, 복구 시 순차 재전송.
- **App:** 재접속 시 그룹 재구독 + REST로 현재 상태 1회 재동기화(놓친 이벤트 보정).

---

## 6. 결정 반영/기본값

- **D-26 ✅** Agent 인증 = 장치별 키(1회용 연결 코드로 교환, SHA-256 해시 저장) (~~D-12/D-21 좌석 API Key~~ 대체)
- **D-28 ✅** 세션 결과 = 이벤트 유형 `SessionClassified`(세션당 최종 순위표 1건). 허브 메시지 한도 64KiB 명시
- **D-13** 이벤트 순서 보장 = 세션 단위 (기본값)
- **D-7 ✅** LapFinished 섹터 = 가변 배열
- **D-16 ✅** SessionStarted에 sessionType 포함, 실시간 랭킹은 Time Trial만 브로드캐스트
- **D-8a ✅** 실시간 랭킹 기본 기준 = **월별(monthly)**
