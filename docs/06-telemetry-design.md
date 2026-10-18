# 06 · Telemetry Event Design (F1 UDP)

> Status: **Design (미승인)** · Last Updated: 2026-10-18 (P7 시즌·세션 반영, 앞서 P6 개인 모드 반영)
> 계약 원본: `shared/telemetry/`. Agent(`Agent.Core`)의 파싱·판정 규칙을 정의한다.
> P6에서 Agent 설정(`RigCode`·`BackendUrl`·`AgentCredential` → `ServerBaseUrl` + 장치 키 파일)과 envelope(`rigCode` 삭제)이 바뀌었다([11](./11-personal-mode.md) §6).
> P7에서 Participants(4)·Final Classification(8) 패킷 파싱, `SessionResultTracker`, `LapFinished` 세션 맥락 필드, Outbox 적재 전 크기 검사가 추가됐다([12](./12-seasons-sessions.md) §5).
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
분석기 목록 (순서 무관 · 분석기마다 예외 격리)
  ├─ LapAnalyzer          ── 플레이어 차량 상태 추적, 랩/섹터 전이 감지
  └─ SessionResultTracker ── 세션 최종 순위표 + 참가자 → SessionClassified (P7)
   │  상태 변화
   ▼
DomainEventFactory  ── 의미 있는 이벤트만 생성 (LapFinished, SessionClassified 등)
   │  TelemetryEnvelope
   ▼
Outbox(SQLite) → TelemetryClient(SignalR)   ── Raw 패킷은 서버에 전송/저장하지 않음
              (적재 전 직렬화 크기 검사 48KiB — §5)
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
| 1 | **Session** | 트랙 ID, **세션 타입(m_sessionType)** → `SessionStarted`. Time Trial 구분 필수(D-16). P7: `GameMode`·`SessionKind`(상세)·링크 식별자 3개(`SeasonLinkIdentifier`·`WeekendLinkIdentifier`·`SessionLinkIdentifier`)·`TotalLaps`·`AIDifficulty`·`IsNetworkGame` |
| 2 | **Lap Data** | 랩/섹터 시간, 현재 랩 유효성, 랩 번호 → 랩/섹터 판정의 **주 소스** |
| 3 | **Event** | `SSTA`(세션시작)/`SEND`(세션종료) 등 마커 → 세션 경계 보정 |
| 4 | **Participants** (P7) | 차별 `Name`·`Driver`(게임 드라이버 ID, 사람이면 `NetworkHuman`)·`Team`·`RaceNumber`·`IsAiControlled` → `SessionClassified`의 드라이버 정보 (5초마다 도착) |
| 8 | **Final Classification** (P7) | 세션 끝의 최종 순위표: 순위·그리드·랩 수·점수·피트·패널티·결과 상태·베스트 랩·총 시간·타이어 스틴트 → `SessionClassified` (세션당 도착) |
| 6 | **Car Telemetry** (P9) | 플레이어 차의 속도·스로틀·브레이크·스티어·기어·RPM → 1랩 트레이스(`LapFinished.trace`, D-45) |
| 7 | **Car Status** (P9) | 연료·남은 랩·ERS 저장량/이 랩 배포·회수·컴파운드·타이어 나이 → 랩 스냅샷(`LapFinished.car`, D-44) |
| 10 | **Car Damage** (P9) | 타이어 마모·손상, 브레이크 손상, 날개·플로어·디퓨저·사이드포드·기어박스·엔진 손상 → 랩 스냅샷 |

> P9에서 Session은 날씨·기온·노면 온도·트랙 길이·비 예보를, Lap Data는 `m_lapDistance`·`m_currentLapTimeInMS`를 더 읽는다([15](./15-lap-detail-telemetry.md) §3).
> Motion(0), Session History(11) 등은 아직 파싱하지 않는다(YAGNI). Session History(11)는 P8 후보.

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

### 3.4 세션 결과 수집 (SessionResultTracker · P7)

`SessionResultTracker`(`Agent.Core/Analysis`)는 `SessionFrame`·`ParticipantsFrame`·`ClassificationFrame`만 보는 순수·상태 저장 분석기다. `LapAnalyzer`와 **상태를 공유하지 않으므로**
파이프라인에서 두 분석기의 순서는 상관없다. 분석기마다 try/catch로 감싸 한쪽의 예외가 다른 쪽을 막지 않는다.

| 입력 | 처리 |
|---|---|
| `SessionFrame` | 세션 맥락(모드·링크 식별자·트랙·세션 종류)을 바꾼다. `SessionRef`가 바뀌면 참가자 목록을 비운다 |
| `ParticipantsFrame` | 맥락과 `SessionRef`가 같을 때만 저장한다 |
| `ClassificationFrame` | 맥락이 없거나 `SessionRef`가 다르면 무시. `SessionType`이 `TimeTrial`이면 무시(D-30). 이미 보낸 `SessionRef`면 무시. **행이 하나도 없으면 무시하고 그 `SessionRef`를 보낸 것으로 기억하지 않는다.** 아니면 참가자를 `carIndex`로 붙여 `SessionClassified` 1건을 만들고 그 `SessionRef`를 기억한다 |

- 참가자 정보가 없는 차는 `driverName`·`gameDriverId`·`teamId`·`raceNumber`를 null, `isAiControlled`를 false로 보낸다.
- 세션 도중에 Agent를 시작해 맥락 없는 순위표를 받으면 보내지 않는다(그 세션 1건 손실).
- 매퍼(`F1PacketMapper`, Agent.Infrastructure)는 Final Classification에서 `ResultStatus`가 Invalid·Inactive이거나 `Position == 0` 또는 `Position > 32`(백엔드 검증 상한)인 칸(빈 그리드·쓰레기 순위)을 빼고,
  시간을 ms로 바꾼다(`TotalRaceTime`은 초 → ms 반올림). NaN·0 이하·범위 밖의 깨진 값은 0 또는 `int.MaxValue`로 보정한다. UDP 이름은 첫 NUL에서 자른다.
  게임 모드·세션 종류·컴파운드 매핑은 [12](./12-seasons-sessions.md) §5.2.

---

## 4. Agent → Backend 이벤트 (TelemetryEnvelope)

판정 결과는 [05-signalr-design.md](./05-signalr-design.md)의 `TelemetryEnvelope`로 감싸 전송한다.

```jsonc
// 예: LapFinished
{
  "eventId": "guid",
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
    "trackId": 2,
    "gameMode": "DriverCareer",          // P7 선택 필드 4개 — 세션 맥락(LapAnalyzer가 Session 패킷에서 보관)
    "seasonLinkId": 2847561234,
    "weekendLinkId": 99112233,
    "sessionLinkId": 44556677
  }
}
```

- P7 선택 필드(`gameMode`·`seasonLinkId`·`weekendLinkId`·`sessionLinkId`)는 백엔드가 `Lap.SessionKey`를 계산하는 데 쓴다(저장만, 조회는 P8). 게임 모드를 모르거나 링크가 없으면 `gameMode = "Other"`, 링크 `0`으로 간다.
- 세션 끝에는 `SessionClassified`(최종 순위표 1건)가 따로 간다. payload·응답 규칙은 [05](./05-signalr-design.md) §2.4·§2.5.
- **P9 선택 필드 3개**([15](./15-lap-detail-telemetry.md) §3·§4.3): `car`(팀 ID·타이어·손상·연료·ERS의 랩 시작/끝 값, D-44) · `conditions`(날씨·기온·노면 온도·비 예보) ·
  `trace`(거리 5m 표본 — `resolutionM` + `timeMs`·`speedKph`·`throttle`·`brake`·`steer`·`gear`·`rpm` 정수 배열, D-45).
  봉투가 48KiB를 넘으면 트레이스를 10m → 20m로 낮추고, 그래도 넘으면 트레이스만 뺀다. 백엔드는 틀린 스냅샷·트레이스만 버리고 랩은 저장한다.

- `trackId`(게임 정수) → Backend가 `Track` 마스터(GameCode+GameTrackId)로 변환.
- `eventId`는 Agent가 생성하는 **멱등키**. 재전송 시 동일 값 → Backend 중복 제거.
- envelope에는 사용자·좌석 식별자가 없다. 귀속은 서버가 **인증된 장치 키**로 결정한다(장치 주인, D-25).

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
- 서버가 같은 항목에 오류를 되풀이하면 그 항목만 미루고 뒤 항목을 먼저 보낸다. 읽을 수 없는 payload는 `outbox_dead_letter`로 옮긴다([13](./13-outbox-dead-letter.md), D-35~D-38).
- **적재 전 크기 검사 (P7):** 허브는 64KiB를 넘는 메시지를 Reject가 아니라 연결 종료로 거절하고, 그러면 같은 항목이 끝없이 재시도된다. 그래서 Outbox에 넣기 전에
  직렬화한 JSON의 UTF-8 바이트가 `OutboxTelemetrySink.MaxEnvelopeBytes`(48KiB)를 넘는지 잰다. 넘는 `SessionClassified`는 **타이어 스틴트를 빼고** 다시 재서 적재하고(경고 로그),
  그래도 넘거나 다른 유형이면 적재하지 않고 오류 로그를 남긴다. 게임 최대(24대 × 8스틴트) 실측은 약 24KB(이름이 검증 한도까지 길어도 약 32KB)라 정상 경로에서는 일어나지 않는다([12](./12-seasons-sessions.md) §5.5·§14).

---

## 6. Agent 설정 (config)

| 항목 | 예시 | 비고 |
|---|---|---|
| `UdpPort` | `20777` | 게임 텔레메트리 포트 |
| `ServerBaseUrl` | `http://localhost:5284` | 연결 API는 `{ServerBaseUrl}/api/v1/agent/pair`, 허브는 `{ServerBaseUrl}/hubs/telemetry`. 비우면 업로드 비활성 |
| `GameCode` | `F1_25` | 대상 게임(D-14 확정) |
| `ExpectedPacketFormat` | `2025` | `m_packetFormat` 검증 |
| `OutboxPath` | `outbox.db` | SQLite Outbox 위치 |

**장치 키(자격)** 는 설정 파일이 아니라 `%LOCALAPPDATA%\SimCenter\Agent\device.key`에 **Windows DPAPI(CurrentUser)** 로 암호화해 저장한다
(`IDeviceCredentialStore`, D-26). 파일이 없으면 "미연결", 복호화에 실패하면 미연결로 보고 오류 로그를 남긴다.

**계정 연결**
- Cli: `dotnet run -- pair <코드>` (`agent/src/SimCenter.Agent.Cli`에서 실행). 성공 시 키를 저장하고 종료 코드 0, 실패 시 1.
- Tray: "계정 연결" 영역(코드 입력 + [연결], 상태 `미연결` / `연결됨 · {PC 이름}` / `다시 연결 필요`, [이 PC 연결 끊기] = 로컬 키 삭제).

**업로드 규칙** (`TelemetryUploadService`)
- 키가 없으면 업로드를 멈추되 UDP 수신과 Outbox 적재는 계속한다. 키가 저장되면(10초마다 파일 재확인 + 변경 이벤트) 바로 시작한다.
- 허브 연결이 **401**이면 재시도를 멈추고 `다시 연결 필요`가 된다(Outbox 항목은 보존). 새 키가 저장될 때까지 업로드하지 않는다.
- 그 밖의 네트워크 오류는 지수 백오프(최대 30초)로 재시도한다.
- 서버 오류(허브 메서드 예외 등)가 같은 항목에 5번 나면 그 항목만 30초~최대 5분 간격으로 미룬다. 연결 끊김은 세지 않는다([13](./13-outbox-dead-letter.md)).
- 연결 전에 쌓인 이벤트는 연결 후 업로드되어 그 계정에 귀속된다.

---

## 7. 확정된 결정 (반영 완료)

- **D-26 ✅** Agent 인증 = 장치 키(DPAPI 저장). 활성 세션이 없으면 랩을 버리던 규칙(~~D-22~~)은 사라졌다 — 랩은 항상 장치 주인에게 귀속된다.
- **D-28 ✅** 세션 결과 = 세션당 최종 순위표 1건(`SessionClassified`), Participants·Final Classification을 Agent가 합쳐 보낸다.
- **D-30 ✅** Time Trial 순위표는 Agent도 보내지 않고, 백엔드도 저장하지 않는다(최종 판정은 백엔드).
- **D-14 ✅** F1 25 대상. `m_packetFormat` 버전 검증 + 게임별 파서 확장 여지(OCP).
- **D-15 ✅** 무효/아웃/인랩도 저장, 랭킹 적격 판정은 Backend가 최종 수행.
- **D-16 ✅** SessionType 캡처, 실시간 랭킹은 Time Trial만. 타 세션 개별 조회 가능.
- **D-7 ✅** 섹터는 가변 배열로 전송(타 게임 대비).
- 플레이어 차량만 집계: `m_playerCarIndex` 기준으로만 판정(§2.1).
