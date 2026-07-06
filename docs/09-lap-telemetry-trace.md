# 09 · Lap Telemetry Trace — 상세 텔레메트리 조회 (Future 설계)

> Status: **Future 설계 (MVP 아님)** · Last Updated: 2026-07-06
> 목적: 브레이크·스로틀·스티어링·타이어 마모/온도 등 **상세 텔레메트리를 개별 화면에서 조회**하는
> 기능을 **지금 구현하지 않되, 아키텍처가 나중에 수용**할 수 있도록 설계 지점을 확정한다.

---

## 1. 요구사항

- 사용자는 특정 랩(또는 세션)의 **상세 주행 데이터**를 그래프로 볼 수 있어야 한다.
- 초기 관심 채널: **스로틀, 브레이크, 스티어링(핸들 기울기), 타이어 마모, 타이어 온도.**
  (확장: 속도, 기어, RPM, 브레이크 온도, G-force 등)
- **MVP 범위 아님.** 단, MVP 구조가 이 기능을 막지 않아야 한다(확장성 우선 — 헌장).

---

## 2. 핵심 설계 원칙 — 데이터 평면 분리

상세 텔레메트리는 **초당 수십 프레임의 시계열**이라, MVP의 이벤트 스트림과 성격이 완전히 다르다.
따라서 **두 개의 데이터 평면**으로 분리한다.

| 평면 | 데이터 | 전송 | 저장 | 시점 |
|---|---|---|---|---|
| **Event Plane** (MVP) | 이산 도메인 이벤트(LapFinished 등) | SignalR | 정규 Entity(Lap 등) | 실시간 |
| **Trace Plane** (Future) | 랩 단위 정제 시계열(트레이스) | **REST(1랩=1아티팩트)** | 압축 Blob/Object Store | 랩 완주 후 |

> **헌장 원칙과의 조화:** "Raw UDP 패킷 스트림을 서버로 흘리거나 그대로 저장하지 않는다"는 원칙은 유지된다.
> Trace Plane이 저장하는 것은 **raw firehose가 아니라, Agent가 랩 동안 로컬에서 수집·다운샘플·압축한
> "정제된 1랩 트레이스" 아티팩트 1건**이다. (패킷 단위 스트리밍/원본 저장이 아님)
> → 이 해석의 승인 필요: **D-17**.

```
게임 UDP(60Hz)
   │  (Agent 로컬에서만 고빈도 소비)
   ▼
[Agent] ── 랩 진행 중: 선택 채널을 distance/time 버킷으로 다운샘플 버퍼링
   │
   └─ LapFinished 시점: 1랩 트레이스 조립 → 압축 → REST 업로드(비동기, best-effort)
                                                   │
                                                   ▼
                                     [Backend] LapTelemetryTrace 저장(Blob)
                                                   │  GET (App 상세 화면)
                                                   ▼
                                              [App] 그래프 렌더
```

---

## 3. F1 25 UDP 소스 패킷 (Future에 추가 파싱)

MVP에서는 파싱하지 않는 패킷들이 여기에 사용된다. (§06의 "MVP는 파싱 안 함" 항목이 여기로 확장)

| packetId | 패킷 | 제공 채널(예) |
|---|---|---|
| 6 | Car Telemetry | throttle, brake, steer, speed, gear, engineRPM, **타이어 표면/내부 온도**, 브레이크 온도 |
| 10 | Car Damage | **타이어 마모(%)**, 타이어/브레이크 손상 |
| 7 | Car Status | 연료, ERS, 타이어 컴파운드/나이 |
| 0 | Motion | G-force, 위치(선택) |

> 채널 목록은 **게임 중립적 key→series 모델**로 추상화한다. F1 패킷은 이 모델로 매핑되고,
> 추후 타 게임(iRacing 등)은 자기 채널을 같은 모델로 매핑한다(OCP, D-7/D-16 방향과 일치).

---

## 4. 데이터 모델 (Future Entity — 개념)

```
Lap (1) ───────── (0..1) LapTelemetryTrace
                          │──────────────────────────────
                          │ Id (PK)
                          │ LapId (FK, unique)      -- 1랩 1트레이스
                          │ SampleBasis (enum)      -- ByDistance | ByTime
                          │ SampleCount             -- 샘플 개수
                          │ Resolution              -- 거리 간격(m) 또는 Hz
                          │ Channels (jsonb)        -- 포함 채널 메타(이름/단위/범위)
                          │ Format (enum)           -- Json+Gzip | Protobuf | Parquet
                          │ SizeBytes
                          │ StorageRef              -- Blob 위치(DB bytea PK 또는 object key)
                          │ CreatedAt
                          └──────────────────────────────
```

- **payload(실 시계열)는 Entity 컬럼이 아니라 Blob**으로 보관. (정규 테이블 비대화 방지)
  - 초기: PostgreSQL `bytea` 또는 별도 `trace_blob` 테이블.
  - 확장: Object Storage(S3 호환) 또는 TimescaleDB(샘플 단위 질의 필요 시). → **D-18**
- Lap과 1:1(선택적). 트레이스 없는 랩도 정상(과거 데이터/업로드 실패).

---

## 5. API (Future)

| Method | Path | 주체 | 설명 |
|---|---|---|---|
| POST | `/api/v1/laps/{lapId}/trace` | Agent(장비 인증) | 1랩 트레이스 업로드(압축 본문) |
| GET | `/api/v1/laps/{lapId}/trace` | App(사용자) | 트레이스 조회(채널/샘플 또는 다운로드 URL) |

```jsonc
// GET 응답(개념) — App이 그래프로 렌더
{
  "lapId": "guid",
  "sampleBasis": "ByDistance",
  "resolution": 5,                 // 5m 간격
  "channels": [
    { "key": "throttle", "unit": "ratio", "min": 0, "max": 1 },
    { "key": "brake", "unit": "ratio", "min": 0, "max": 1 },
    { "key": "steer", "unit": "ratio", "min": -1, "max": 1 },
    { "key": "tyreWearFL", "unit": "percent", "min": 0, "max": 100 },
    { "key": "tyreTempFL", "unit": "celsius" }
  ],
  "series": { "distance": [0,5,10,...], "throttle": [...], "brake": [...], "steer": [...] }
}
```

---

## 6. App (Future)

- 신규 feature `lap_detail` (또는 `my_lap_record` 상세 진입).
- 채널별 라인차트(스로틀/브레이크/스티어 vs 거리), 타이어 마모/온도 히트/라인.
- 데이터 조회는 REST(대용량에 적합), 실시간 스트리밍 아님.

---

## 7. MVP가 지금 지켜야 할 "확장 씨앗(Seam)"

이 기능을 나중에 얹기 위해 **MVP 단계에서 미리 확보할 최소 조건**:

1. **Lap이 안정적 식별자(GUID)를 갖고, 세션/트랙/사용자에 연결**되어 있을 것 → ✅ 이미 설계됨([03](./03-entity-design.md)).
2. **Agent 파이프라인이 "이벤트 생성"과 "프레임 소비"를 분리**할 수 있는 구조일 것
   → ✅ `Agent.Core`의 파서/분석 단계가 프레임을 이미 순회하므로, 트레이스 버퍼를 추가할 확장점 존재([01](./01-architecture.md), [06](./06-telemetry-design.md)).
3. **게임 중립 채널 모델**을 전제로 둘 것 → 본 문서 §3 방향.

> 즉, **MVP에서 추가 구현은 없다.** 다만 위 3개 씨앗이 유지되는 한 Trace Plane은 기존 코드를
> 건드리지 않고(OCP) 얹을 수 있다.

---

## 8. Open Decisions (Future — 지금 답변 불필요)

- **D-17** "정제된 1랩 트레이스 저장"이 헌장의 Raw-패킷 저장 금지 원칙과 양립한다는 해석 승인.
- **D-18** 트레이스 저장소: PostgreSQL `bytea` / Object Storage / TimescaleDB.
- **D-19** 샘플링 기준(거리 vs 시간)·해상도·채널 세트·보존 기간(retention).

> 위 결정은 **해당 Phase 착수 시점**에 다룬다. MVP 설계/구현에는 영향 없음.
