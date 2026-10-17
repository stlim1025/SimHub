# 10 · Realtime Ingest (Phase 3) — As-Built

> Status: **Implemented** · Last Updated: 2026-10-17 (P6 개인 모드 반영)
> Agent → Backend 실시간 인입 파이프라인 구현 기록. 계약은 [05](./05-signalr-design.md)·[06](./06-telemetry-design.md),
> 결정은 [08](./08-open-decisions.md) D-21~23(→ P6에서 D-25·D-26으로 대체된 부분은 아래에 표시). 여기서는 **실제 구현된 형태**를 정리한다.
> **P6 변경 요약:** 좌석 키 → 장치 키, 체크인 세션 매칭 → 장치 주인 귀속, 활성 세션 없는 랩 Drop 규칙(D-22) 삭제. 상세: [11](./11-personal-mode.md) §5.

---

## 1. 범위 (D-23)

| 포함 (P3) | 제외 (P4로 연기) |
|---|---|
| `TelemetryHub` 인입(단일 `SubmitEvent`) | `RankingHub` 브로드캐스트(App) |
| Agent 인증(P3 좌석 키 → **P6 장치 키**) | 랭킹 REST(`GET /rankings`) |
| 멱등(eventId) + 귀속 확정(P3 세션매칭 → **P6 장치 주인**) + Lap 저장 | PersonalBest/RankingUpdated 알림 |
| ~~체크인/체크아웃/활성 세션 REST~~ (P6에서 삭제) | App 화면(P5) |
| Agent Outbox(SQLite) + 업로더 + 자동 재접속 | |

**산출물 검증:** E2E 통합 테스트(`TelemetryIngestE2ETests`)로 회원가입→로그인→**연결 코드 발급→`/agent/pair`**→장치 키로 Hub 전송→**DB Lap 귀속 저장**
→`/me/laps`·`/me/tracks`·`/rankings` 확인→장치 해제→다음 `SubmitEvent` Reject를 실 PostgreSQL에서 확인(P3 당시에는 체크인 흐름).

---

## 2. 흐름

```
[Agent]  LapAnalyzer → Envelope (rigCode 없음)
   │  OutboxTelemetrySink: wire JSON 직렬화 → SQLite Outbox(Pending)
   │  TelemetryUploadService: 장치 키 확인 + 자동재접속 + 배수 루프
   └── SubmitEvent(envelope) ──►  [TelemetryHub]  (AgentApiKey 스킴, 클레임 deviceId·sub)
   ◄── IngestResult(ack) ─────    └─ TelemetryIngestService.IngestAsync(envelope, deviceId)
                                       1. 멱등: ProcessedEvent(eventId) 있으면 Ack
                                       2. 장치 확인: deviceId로 AgentDevice 재조회 — 없거나 해제됐으면 Reject("연결이 해제된 장치입니다.")
                                       3. LastSeenAt 갱신(null이거나 1분 이상 지났을 때만, 모든 이벤트 유형)
                                       4. LapFinished만 저장(그 외 Ack)
                                       5. 페이로드 파싱 실패 → Reject
                                       6. Track 매핑((gameCode,trackId)→Track; 없으면 Reject)
                                       7. 랭킹적격 = IsValid && !OutOrIn && TimeTrial
                                       8. Lap(UserId=device.UserId, AgentDeviceId=device.Id)+LapSector + ProcessedEvent
                                          단일 트랜잭션 커밋 → Ack → (커밋 후 best-effort 브로드캐스트)
```

- **응답 규약(D-23 정련):** `SubmitEvent`는 `IngestResult{acknowledged, rejectReason}`를 **반환**(요청/응답).
  Ack·Reject 모두 Agent는 Outbox flush. **무응답(네트워크 장애)만** 보관·재전송(at-least-once + 멱등 = effectively-once).
  **예외:** Reject("연결이 해제된 장치입니다.")는 장치 키가 무효라는 뜻이라 Agent가 그 항목을 남기고 `다시 연결 필요`로 멈춘다(401과 같은 처리, [11](./11-personal-mode.md) §6.4).
- **삭제(D-25):** 활성 체크인 세션 조회와 "활성 세션 없음 → Drop+Ack"(D-22). 랩은 항상 장치 주인에게 귀속된다.

---

## 3. 인증 (D-26, P3의 D-21 대체)

- 저장: `AgentDevice.ApiKeyHash` = `SHA-256(원문)` hex(원문 미저장, Unique 인덱스). 키 원문은 `POST /agent/pair` 응답에서 한 번만 내려간다.
- 전송: Agent가 DPAPI로 저장한 장치 키 → 헤더 `X-Agent-Key`(쿼리 `access_token` 폴백).
- 검증: `AgentApiKeyAuthenticationHandler`가 해시로 `AgentDevice`를 특정 → 연결에 `deviceId`·`sub`(장치 주인) 클레임 귀속.
  `[Authorize(AuthenticationSchemes="AgentApiKey")]`. 사용자 JWT와 완전 분리. 해제(soft delete)된 장치는 전역 필터로 조회되지 않아 **새 연결은 401**.
- **귀속은 인증된 deviceId를 신뢰**(엔벨로프에는 식별자가 없다 → 위조 방지). 이미 열린 연결은 인입 때마다 장치를 재확인해 Reject한다.
- 개발용 시드 키(`dev-agent-key-*`)는 제거됐다. 로컬에서는 웹(또는 Swagger)에서 코드를 발급해 `pair`로 연결한다([TESTING-local-e2e.md](./TESTING-local-e2e.md)).

---

## 4. 내구성 (Agent Outbox)

- `TelemetryOutbox`(SQLite, 단일 연결 + 세마포어 직렬화). 스키마: `outbox(seq, event_id UNIQUE, occurred_at, payload)`.
- 모든 이벤트는 전송 전 Outbox에 먼저 기록(전원/네트워크 장애 무손실). `INSERT OR IGNORE`로 재적재 멱등.
- `TelemetryUploadService`: `occurred_at` 순 배수, 서버 응답 시 삭제, 예외 시 지수 백오프(최대 30s) 재시도.
  **P6:** 장치 키가 없으면 업로드를 멈춘다(수신·적재는 계속). 허브가 **401**이면 재시도를 멈추고 `다시 연결 필요`로 전환하며 Outbox 항목은 보존한다.
  키 파일은 10초마다 다시 확인한다.
- `ServerBaseUrl`(구 `BackendUrl`) 미설정 시 업로드 비활성(이벤트는 계속 적재) — 백엔드 없이 Tray 단독 실행 가능.

---

## 5. 계약 직렬화 세부

- SignalR JSON: **camelCase + enum 문자열**(양측 `AddJsonProtocol` 일치).
- Agent wire 봉투: `Type`는 문자열, `Payload`는 `object`로 담아 **런타임 타입(LapFinished)** 의 전체 필드가 직렬화.
- `SessionType`은 Agent/Domain 열거형 이름이 일치(TimeTrial 등) → 문자열로 무손실 매핑.
- 서버는 `TelemetryEnvelopeDto.Payload`를 `JsonElement`로 받아 type에 따라 `LapFinishedPayloadDto`로 해석(OCP).

---

## 6. 스키마 변경

- 마이그레이션 `AddTelemetryIngest`(P3): `sim_rigs.api_key_hash`(nullable, unique) + `processed_events`(event_id PK) 테이블.
  `sim_rigs`는 P6 `PersonalMode`에서 삭제됐다.
- 마이그레이션 `AddAgentDevices`(P6): `agent_devices`·`agent_pairing_codes` 추가(가산적).
- 마이그레이션 `PersonalMode`(P6): `laps`·`lap_sectors`·`processed_events` 기존 행 삭제, `laps.driving_session_id` → `agent_device_id`, `laps.user_id` FK 추가,
  `driving_sessions`·`sim_rigs`·`stores` 삭제. 두 건으로 나눈 이유는 [11](./11-personal-mode.md) §3.4 참조.
- `ProcessedEvent`는 BaseEntity가 아님(Soft Delete 대상 아닌 추가 전용 멱등 원장, PK=EventId).

---

## 7. 남은 라이브 검증 (하드웨어 의존)

- 실 F1 25 + Agent(Cli/Tray, `ServerBaseUrl` 설정 + 계정 연결)로 UDP→LapFinished→서버→DB 관찰. 현재는 단위/통합(E2E) 테스트까지 검증됨.
  P6 헤드리스 확인(연결 코드→`pair`→허브 연결→장치 해제 후 401 중단)은 [PROGRESS.md](./PROGRESS.md) 참조 — 랩 단계만 F1 25가 필요해 보류.
