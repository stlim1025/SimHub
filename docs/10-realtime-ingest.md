# 10 · Realtime Ingest (Phase 3) — As-Built

> Status: **Implemented** · Last Updated: 2026-07-07
> Agent → Backend 실시간 인입 파이프라인 구현 기록. 계약은 [05](./05-signalr-design.md)·[06](./06-telemetry-design.md),
> 결정은 [08](./08-open-decisions.md) D-21~23. 여기서는 **실제 구현된 형태**를 정리한다.

---

## 1. 범위 (D-23)

| 포함 (P3) | 제외 (P4로 연기) |
|---|---|
| `TelemetryHub` 인입(단일 `SubmitEvent`) | `RankingHub` 브로드캐스트(App) |
| Agent 장비 API Key 인증(D-21) | 랭킹 REST(`GET /rankings`) |
| 멱등(eventId) + 세션매칭 + Lap 저장 | PersonalBest/RankingUpdated 알림 |
| 체크인/체크아웃/활성 세션 REST | App 화면(P5) |
| Agent Outbox(SQLite) + 업로더 + 자동 재접속 | |

**산출물 검증:** E2E 통합 테스트(`TelemetryIngestE2ETests`)로 회원가입→로그인→체크인→Hub 전송→**DB Lap 귀속 저장**을 실 PostgreSQL에서 확인.

---

## 2. 흐름

```
[Agent]  LapAnalyzer → Envelope
   │  OutboxTelemetrySink: wire JSON 직렬화 → SQLite Outbox(Pending)
   │  TelemetryUploadService: 자동재접속 + 배수 루프
   └── SubmitEvent(envelope) ──►  [TelemetryHub]  (AgentApiKey 스킴)
   ◄── IngestResult(ack) ─────    └─ TelemetryIngestService.IngestAsync(envelope, 인증rigCode)
                                       1. 멱등: ProcessedEvent(eventId) 있으면 Ack
                                       2. LapFinished만 저장(그 외 Ack)
                                       3. 세션매칭: 인증 rigCode의 활성 DrivingSession (없으면 drop+Ack, D-22)
                                       4. Track 매핑((gameCode,trackId)→Track; 없으면 Reject)
                                       5. 랭킹적격 = IsValid && !OutOrIn && TimeTrial
                                       6. Lap+LapSector + ProcessedEvent 단일 트랜잭션 커밋 → Ack
```

- **응답 규약(D-23 정련):** `SubmitEvent`는 `IngestResult{acknowledged, rejectReason}`를 **반환**(요청/응답).
  Ack·Reject 모두 Agent는 Outbox flush. **무응답(네트워크 장애)만** 보관·재전송(at-least-once + 멱등 = effectively-once).

---

## 3. 인증 (D-21)

- 저장: `SimRig.ApiKeyHash` = `SHA-256(원문)` hex(원문 미저장, Unique 인덱스).
- 전송: Agent `AgentCredential`(원문) → 헤더 `X-Agent-Key`(쿼리 `access_token` 폴백).
- 검증: `AgentApiKeyAuthenticationHandler`가 해시로 SimRig 특정 → 연결에 `rigCode` 클레임 귀속.
  `[Authorize(AuthenticationSchemes="AgentApiKey")]`. 사용자 JWT와 완전 분리.
- **세션 매칭은 인증된 rigCode를 신뢰**(엔벨로프의 rigCode는 사용 안 함 → 위조 방지).
- 개발용 키: 시더가 `dev-agent-key-{RigCode}` 결정적 프로비저닝(로컬 E2E용). 운영 키 발급은 범위 밖.

---

## 4. 내구성 (Agent Outbox)

- `TelemetryOutbox`(SQLite, 단일 연결 + 세마포어 직렬화). 스키마: `outbox(seq, event_id UNIQUE, occurred_at, payload)`.
- 모든 이벤트는 전송 전 Outbox에 먼저 기록(전원/네트워크 장애 무손실). `INSERT OR IGNORE`로 재적재 멱등.
- `TelemetryUploadService`: `occurred_at` 순 배수, 서버 응답 시 삭제, 예외 시 지수 백오프(최대 30s) 재시도.
- `BackendUrl` 미설정 시 업로드 비활성(이벤트는 계속 적재) — 백엔드 없이 Tray 단독 실행 가능.

---

## 5. 계약 직렬화 세부

- SignalR JSON: **camelCase + enum 문자열**(양측 `AddJsonProtocol` 일치).
- Agent wire 봉투: `Type`는 문자열, `Payload`는 `object`로 담아 **런타임 타입(LapFinished)** 의 전체 필드가 직렬화.
- `SessionType`은 Agent/Domain 열거형 이름이 일치(TimeTrial 등) → 문자열로 무손실 매핑.
- 서버는 `TelemetryEnvelopeDto.Payload`를 `JsonElement`로 받아 type에 따라 `LapFinishedPayloadDto`로 해석(OCP).

---

## 6. 스키마 변경

- 마이그레이션 `AddTelemetryIngest`: `sim_rigs.api_key_hash`(nullable, unique) + `processed_events`(event_id PK) 테이블.
- `ProcessedEvent`는 BaseEntity가 아님(Soft Delete 대상 아닌 추가 전용 멱등 원장, PK=EventId).

---

## 7. 남은 라이브 검증 (하드웨어 의존)

- 실 F1 25 + Agent(Cli/Tray, `BackendUrl` 설정)로 UDP→LapFinished→서버→DB 관찰. 현재는 단위/통합(E2E) 테스트까지 검증됨.
