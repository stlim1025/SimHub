# 05 · SignalR Event Design

> Status: **Design (미승인)** · Last Updated: 2026-07-06
> 계약 원본: `shared/schema/*.json`. 두 개의 Hub로 **인입(Ingest)**과 **브로드캐스트(Broadcast)**를 분리한다.

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
- 인증: **Agent 전용 자격**(장비 토큰/API Key). 사용자 JWT와 분리. → D-12
- 그룹: 연결 시 `RigCode` 기준으로 그룹 배정(운영 모니터링용, MVP 선택).

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
  "rigCode": "A-01",              // 어느 좌석에서 발생했는가
  "gameCode": "F1_24",
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

`sectors[]` = `[{ sectorNumber, sectorTimeMs }, ...]` (게임별 개수 상이).
`sessionType` = 게임 세션 모드. 랭킹 적격 판정은 Backend가 수행(D-15/D-16).

- `sessionRef` = Agent 로컬 게임세션 식별자(Backend DrivingSession과 다름). Backend가 rig+시간으로 매핑.
- `trackId` = 게임 UDP의 트랙 정수 ID → Backend가 Track 마스터로 변환.

### 2.5 Server → Client (Backend가 Agent에 응답)

| 메서드 | 용도 |
|---|---|
| `Ack(eventId)` | 수신·처리 확인 → Agent가 Outbox에서 flush |
| `Reject(eventId, reason)` | 검증 실패(무시하되 로깅) |

> **멱등성:** Backend는 `eventId`로 중복을 걸러낸다(재전송 안전). Agent는 Ack 받을 때까지 Outbox 보관.

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
| `LapRecorded` | `LapRecordedNotice` | 새 유효 랩 저장됨(내 랩 목록 갱신 트리거) |
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

// LapRecorded
{ "lapId": "guid", "userId": "guid", "trackId": "guid", "sessionType": "TimeTrial",
  "lapTimeMs": 83452, "isValid": true, "isRankingEligible": true }

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
  │                       ├─► 세션매칭·Lap저장 ──►│                        │                │
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

- **D-12** Agent 인증 = 장비별 API Key (권장 기본값, 추후 강화)
- **D-13** 이벤트 순서 보장 = 세션 단위 (기본값)
- **D-7 ✅** LapFinished 섹터 = 가변 배열
- **D-16 ✅** SessionStarted에 sessionType 포함, 실시간 랭킹은 Time Trial만 브로드캐스트
- **D-8a ✅** 실시간 랭킹 기본 기준 = **월별(monthly)**
