# 06 · Telemetry Event Design (F1 UDP)

> Status: **Design (미승인)** · Last Updated: 2026-07-06
> 계약 원본: `shared/telemetry/`. Agent(`Agent.Core`)의 파싱·판정 규칙을 정의한다.
> **대상:** F1 25 (`GameCode = F1_25`, D-14 확정). 추후 타 게임 지원 대비해 파서를 게임별로
> 교체 가능하게 설계하고, 도메인 이벤트는 게임 중립적으로 유지한다(가변 섹터·세션타입).

---

## 1. 파이프라인 (헌장 Telemetry Rules 준수)

```
UDP 20777
   │  Raw Datagram
   ▼
PacketParser        ── PacketHeader 읽어 packetId 분기, 버전(m_packetFormat) 검증
   │  구조화된 패킷
   ▼
LapAnalyzer         ── 플레이어 차량 상태 추적, 랩/섹터 전이 감지
   │  상태 변화
   ▼
DomainEventFactory  ── 의미 있는 이벤트만 생성 (LapFinished 등)
   │  TelemetryEnvelope
   ▼
Outbox(SQLite) → TelemetryClient(SignalR)   ── Raw 패킷은 서버에 전송/저장하지 않음
```

**핵심 원칙**
- 모든 UDP 패킷을 서버로 보내지 않는다. **도메인 이벤트만** 전송.
- Raw 패킷은 서버에 저장하지 않는다. (Agent 로컬에서 소비)
- `Agent.Core`는 네트워크/파일 I/O 무의존 → 고정 샘플 패킷으로 단위 테스트.

---

## 2. F1 UDP 개요 (파싱 대상)

F1(Codemasters/EA) 텔레메트리는 UDP로 여러 **패킷 타입**을 브로드캐스트한다.
각 패킷은 공통 `PacketHeader`로 시작하고 `m_packetId`로 종류를 구분한다.

### 2.1 PacketHeader (모든 패킷 공통, 핵심 필드)

| 필드 | 용도 |
|---|---|
| `m_packetFormat` | 게임 연식(예: 2024) — **버전 호환성 판단** |
| `m_packetId` | 패킷 종류 식별 |
| `m_sessionUID` | 세션 고유 ID → `sessionRef`로 사용 |
| `m_playerCarIndex` | 22대 배열 중 **플레이어 차량 인덱스** — 이 인덱스만 관심 |
| `m_sessionTime` | 세션 경과 시간 |

### 2.2 MVP에서 실제 파싱하는 패킷

| packetId | 이름 | 사용 목적 |
|---|---|---|
| 1 | **Session** | 트랙 ID, **세션 타입(m_sessionType)** → `SessionStarted`. Time Trial 구분 필수(D-16) |
| 2 | **Lap Data** | 랩/섹터 시간, 현재 랩 유효성, 랩 번호 → 랩/섹터 판정의 **주 소스** |
| 3 | **Event** | `SSTA`(세션시작)/`SEND`(세션종료) 등 마커 → 세션 경계 보정 |

> Motion(0), CarTelemetry(6), CarStatus(7), CarDamage(10) 등은 MVP 랭킹에 불필요 → **파싱하지 않음**(YAGNI).
> 단, 이들은 **상세 텔레메트리 조회(Future)**의 소스이므로 Agent 파이프라인은 프레임 순회 지점을
> 확장 가능하게 유지한다. → [09-lap-telemetry-trace.md](./09-lap-telemetry-trace.md)

### 2.3 Lap Data 패킷의 관심 필드 (플레이어 인덱스 기준)

| 필드(개념) | 용도 |
|---|---|
| `m_currentLapNum` | 현재 랩 번호 — 증가 시 **랩 전환** 감지 |
| `m_sector` (0/1/2) | 현재 섹터 — 변화 시 **섹터 완료** 감지 |
| `m_sector1TimeInMS` / `m_sector2TimeInMS` | 확정된 섹터 시간 |
| `m_lastLapTimeInMS` | 직전 랩 총 시간 → `LapFinished.lapTimeMs` |
| `m_currentLapInvalid` | 현재 랩 무효 플래그 → `isValid` |
| `m_pitStatus` / `m_driverStatus` | 피트·차고 상태(무효/제외 판단 보조) |

> **정확한 오프셋/타입/구조체 레이아웃은 대상 연식의 공식 UDP Spec을 근거로** `shared/telemetry/`에
> 확정 문서화한다. 본 문서는 판정 **규칙**만 정의하고, 바이너리 레이아웃은 스펙 확정 후 채운다. (D-14)

---

## 3. Lap / Sector 판정 규칙 (LapAnalyzer)

LapAnalyzer는 플레이어 차량에 대해 **직전 상태 스냅샷**을 유지하고 전이를 감지한다.

### 3.1 상태 모델

```
Idle ──SessionStart──► InSession ──lapNum 증가──► LapInProgress ──(다음 lapNum 증가)──► LapFinished
                            ▲                                                              │
                            └──────────────────────────────────────────────────────────────┘
```

### 3.2 판정 규칙

| 감지 | 조건 | 생성 이벤트 |
|---|---|---|
| 세션 시작 | Session 패킷 최초 수신 or Event `SSTA` | `SessionStarted` |
| 랩 시작 | `m_currentLapNum`가 이전보다 증가 | `LapStarted(lapNumber)` |
| 섹터 완료 | `m_sector` 값 변화 (0→1, 1→2) | `SectorCompleted(sector, sectorTimeMs)` |
| **랩 완주** | `m_currentLapNum` 증가 시점에 `m_lastLapTimeInMS` 확정 | **`LapFinished`** (전 랩의 총시간·3섹터·유효성) |
| 세션 종료 | Event `SEND` or 세션UID 변경/타임아웃 | `SessionEnded` |

**랩 완주 판정 상세**
- 랩 번호가 N→N+1로 바뀌는 순간, **완료된 랩은 N번**이다.
- 이때 `m_lastLapTimeInMS`(=랩 N의 총시간)와 누적 섹터(S1,S2) + (총시간−S1−S2=S3)로 3섹터 구성.
- `isValid` = 해당 랩 진행 중 `m_currentLapInvalid`가 한 번이라도 set 되면 false.

**유효성(Invalid) 규칙 (D-15 확정)**
- 트랙 이탈, 컷팅 등으로 게임이 무효 처리한 랩 → `isValid=false`.
- **무효 랩·아웃랩·인랩도 Agent는 그대로 전송하고 Backend는 저장한다.** 개별 조회는 가능해야 함.
- **랭킹 적격(IsRankingEligible) 판정은 Backend가 최종 수행**(정책 일원화):
  `isValid && SessionType=TimeTrial && 아웃/인랩 아님 && 수동무효 아님`.
- Agent는 판단 근거 데이터(`isValid`, 피트상태, `sessionType`, `lapNumber`)만 충실히 전달한다.

### 3.3 노이즈 제거

- UDP는 고주파(수십 Hz)로 동일 상태를 반복 전송한다. LapAnalyzer는 **전이(edge)에서만** 이벤트를 만든다(레벨이 아니라 엣지 트리거) → 서버 전송량 최소화.

---

## 4. Agent → Backend 이벤트 (TelemetryEnvelope)

판정 결과는 [05-signalr-design.md](./05-signalr-design.md)의 `TelemetryEnvelope`로 감싸 전송한다.

```jsonc
// 예: LapFinished
{
  "eventId": "guid",
  "rigCode": "A-01",
  "gameCode": "F1_25",
  "occurredAt": "2026-07-06T09:03:21Z",
  "type": "LapFinished",
  "payload": {
    "sessionRef": "0xF1SESSIONUID",
    "sessionType": "TimeTrial",
    "lapNumber": 4,
    "lapTimeMs": 83452,
    "sectors": [
      { "sectorNumber": 1, "sectorTimeMs": 27010 },
      { "sectorNumber": 2, "sectorTimeMs": 30110 },
      { "sectorNumber": 3, "sectorTimeMs": 26332 }
    ],
    "isValid": true,
    "isOutOrInLap": false,
    "trackId": 2
  }
}
```

- `trackId`(게임 정수) → Backend가 `Track` 마스터(GameCode+GameTrackId)로 변환.
- `eventId`는 Agent가 생성하는 **멱등키**. 재전송 시 동일 값 → Backend 중복 제거.

---

## 5. 내구성 (Outbox / 오프라인 캐시)

```
DomainEvent ──► [SQLite Outbox: status=Pending] ──► SignalR 전송 시도
                                                        │
                              ┌─────────────────────────┴──────────────────┐
                           성공(Ack)                                     실패/오프라인
                              │                                             │
                     status=Sent(또는 삭제)                      재시도 큐 유지(지수 백오프)
```

- **모든 이벤트는 전송 전에 Outbox에 먼저 기록**된다. (전원/네트워크 장애 시 유실 방지)
- 앱 재시작·네트워크 복구 시 `Pending` 이벤트를 `occurredAt` 순서로 재전송.
- Backend `Ack(eventId)` 수신 후에만 Outbox에서 정리. (at-least-once + 멱등 = effectively-once)

---

## 6. Agent 설정 (config)

| 항목 | 예시 | 비고 |
|---|---|---|
| `RigCode` | `A-01` | 이 Agent가 담당하는 좌석. 서버 SimRig.RigCode와 일치 |
| `UdpPort` | `20777` | 게임 텔레메트리 포트 |
| `BackendUrl` | `https://.../hubs/telemetry` | |
| `GameCode` | `F1_25` | 대상 게임(D-14 확정) |
| `AgentCredential` | (secret) | 장비 인증(D-12) — 코드에 하드코딩 금지 |

---

## 7. 확정된 결정 (반영 완료)

- **D-14 ✅** F1 25 대상. `m_packetFormat` 버전 검증 + 게임별 파서 확장 여지(OCP).
- **D-15 ✅** 무효/아웃/인랩도 저장, 랭킹 적격 판정은 Backend가 최종 수행.
- **D-16 ✅** SessionType 캡처, 실시간 랭킹은 Time Trial만. 타 세션 개별 조회 가능.
- **D-7 ✅** 섹터는 가변 배열로 전송(타 게임 대비).
- 플레이어 차량만 집계: `m_playerCarIndex` 기준으로만 판정(§2.1).
