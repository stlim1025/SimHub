# 08 · Open Decisions — 승인 필요 결정사항

> Status: **Design** · Last Updated: 2026-07-07
> AI 작업 규칙("추측 금지, 필요 시 질문") 준수를 위해, **추측 없이 사용자 승인이 필요한 결정**을 모은다.
> 각 항목: 배경 / 선택지 / **권장안** / 영향 문서. 승인 시 각 문서에 반영한다.

---

## A. 반드시 먼저 확정해야 할 핵심 결정 (구조에 영향)

### D-1. 멀티스토어(Multi-Store) 선반영 여부
- 배경: 헌장은 "SaaS 수준" 목표, MVP는 단일 매장.
- 선택지: (a) `StoreId`를 Entity에 지금 반영 / (b) 나중에 마이그레이션으로 추가.
- **권장:** (a). 지금 넣는 비용은 작고, 나중에 소급 추가는 데이터 마이그레이션 리스크가 큼. (확장성 우선)
답변 : (a)안으로
- 영향: [02](./02-domain-design.md), [03](./03-entity-design.md)

### D-2. 랩 ↔ 사용자 귀속(Attribution) 방식 ⭐가장 중요
- 배경: Agent는 SimRig 단위로 텔레메트리를 받을 뿐 "누가 운전 중인지" 모른다. 랭킹은 사용자별.
- 선택지:
  - (a) **체크인 세션**: 앱에서 좌석 QR/코드 체크인 → `DrivingSession(UserId↔RigId)` 생성 → 그 시각 Rig 이벤트를 사용자에 귀속.
  - (b) Agent가 사용자 로그인 정보를 직접 보유(관심사 혼합, 비권장).
  - (c) 운영자가 좌석에 사용자 수동 배정.
- **권장:** (a). 관심사 분리 유지, Agent 무상태·무인증화, 확장 용이. 
답변 : A안으로
- 영향: [02](./02-domain-design.md), [03](./03-entity-design.md), [04](./04-api-design.md)

### D-14. 대상 게임 버전 — ✅ 결정됨
- 배경: UDP 패킷 레이아웃이 연식마다 다름.
- **결정:** **F1 25** 를 기본(`GameCode = F1_25`)으로 사용. 새 버전 출시 시 교체.
- 반영: 파서는 `m_packetFormat`으로 버전을 검증하고, 버전별 파서 확장 여지를 남긴다(OCP).
  현재 구현은 F1 25 스펙 1종만 대상.
- 영향: [06](./06-telemetry-design.md), `shared/telemetry/` (반영 완료)

### D-20. F1 UDP 파싱 — 라이브러리 채택 vs 수제 파서 — ✅ 결정됨 (2026-07-07)
- 배경: F1 UDP 패킷은 연식마다 오프셋이 바뀌어 수제 파서 유지보수 비용이 큼.
  `shared/telemetry/f1_25_udp_spec.md`로 오프셋을 손으로 관리할 예정이었으나, 검증된 NuGet 존재.
- 조사 결과: **[F1Game.UDP](https://www.nuget.org/packages/F1Game.UDP/)** — MIT, net8/9/10, **의존성 0**,
  **순수 파싱**(byte[] → 타입 구조체, 소켓 I/O 없음), 게임 연도=메이저 버전(F1 25→25.x, 2026 시즌팩→26.0.0), 활발히 유지보수.
- **결정:**
  - **채택.** 오프셋 수제 파싱 대신 F1Game.UDP로 바이트 해독을 위임(DRY, 연식 대응).
  - **버전 = 26.0.0**(2026 시즌팩 레이아웃). 런타임에 `m_packetFormat`으로 실제 포맷 검증(불일치 시 경고/스킵, OCP).
  - **경계 = Agent.Infrastructure에서 매핑.** Infrastructure가 F1Game.UDP로 파싱 →
    **Agent.Core 자체 게임중립 입력 모델**(예: `LapSnapshot`)로 매핑 → Core가 분석.
    → **Agent.Core는 F1Game.UDP 무의존**(순수 로직·단위테스트·타 게임 확장 유지, 헌장 부합).
- 우리가 직접 구현하는 범위는 불변: LapAnalyzer(세션/랩/섹터/완주 판정), 도메인 이벤트 생성, Outbox·SignalR.
- `shared/telemetry/f1_25_udp_spec.md`의 성격 전환: **파싱 계약 → 참고 문서**(도메인 이벤트 의미론 유지, 오프셋 표는 라이브러리에 위임).
- 영향: [01](./01-architecture.md), [06](./06-telemetry-design.md), `agent/`, `shared/telemetry/`
---

## B. 데이터/저장 결정

### D-6. Primary Key 타입
- 선택지: `Guid(UUID v7)` vs `long(bigint identity)`.
- **권장:** `Guid(UUID v7)` — 외부 노출·분산·멀티스토어 안전, v7로 정렬 지역성 확보.
답변 : 전자로
- 영향: [03](./03-entity-design.md)

### D-7. Sector 저장 형태
- 선택지: Lap에 3컬럼 내장 vs 별도 `Sector` 테이블.
- **권장:** 내장(F1 고정 3섹터, KISS). 가변 섹터 필요 시 확장.
답변 :우선 MVP는 F1 기반으로만들어질 예정이나 추후 다른 게임도 지원할 예정이라 3섹터만 고정으로 지원하진 않을거같음 
- 영향: [03](./03-entity-design.md)

### D-8. "오늘(Today)" 경계 기준
- 배경: TOP10은 "오늘" 기록. 자정 기준 타임존이 애매.
- 선택지: 매장 로컬 타임존 자정 / UTC 자정 / 영업일(예: 06시 리셋).
- **권장:** **매장 로컬 타임존 자정** (Store에 타임존 보관). 
- 영향: [03](./03-entity-design.md), [04](./04-api-design.md)
- ❓ **질문:** 랭킹 리셋 기준 시각(예: 자정/영업 시작)은?
일별 랭킹, 월별랭킹, 연도별 랭킹을 지원할 예정 일별 랭킹의 리셋 시간은 자정
---

## C. 인증/세션 결정

### D-9. Refresh Token 도입
- **권장:** MVP 제외(단순 access token + 재로그인). 보안 요구 커지면 도입.
- 영향: [04](./04-api-design.md)

### D-10. 사용자 중복 활성 세션 정책
- 배경: 한 사용자가 다른 좌석에 이미 체크인된 상태에서 또 체크인.
- 선택지: 이전 세션 자동 종료 / 신규 거부(409).
- **권장:** 이전 세션 자동 종료(사용자 편의). 
답변 : 이전세선 자동 종료
- 영향: [04](./04-api-design.md)

### D-11. 회원가입 방식
- 배경: MVP에 self-signup을 넣을지, 매장 현장 발급인지 불명확.
- ❓ **질문:** 사용자는 앱에서 직접 가입합니까, 매장에서 계정을 발급받습니까?
앱에서 직접 가입
- 영향: [04](./04-api-design.md)

### D-12. Agent(장비) 인증 방식
- 배경: TelemetryHub는 신뢰된 장비만 연결해야 함(사용자 JWT와 분리).
- 선택지: 장비별 API Key / 사전 발급 장비 토큰 / mTLS.
- **권장:** MVP는 **장비별 API Key**(SimRig에 연결), 추후 강화.
- 영향: [05](./05-signalr-design.md), [06](./06-telemetry-design.md)

---

## D. 텔레메트리 판정 결정

### D-15. 아웃랩/인랩/피트랩 제외 정책
- 배경: 랭킹 신뢰도를 위해 정상 플라잉 랩만 집계해야 함.
- 선택지: Agent가 사전 필터 / Backend가 최종 필터 / 둘 다.
- **권장:** **Backend 최종 판정**(정책 일원화), Agent는 원 데이터+플래그만 전달.
invalid 랩도 우선 기록은 해두고 랭킹 집계에서는 사용하지 않도록, 개별 조회는 보이게 
- 영향: [06](./06-telemetry-design.md)

### D-16. 집계 대상 세션 유형
- 배경: 타임트라이얼/그랑프리/AI 세션 등 어떤 세션의 랩을 랭킹에 넣을지.
- ❓ **질문:** 랭킹은 특정 세션 모드(예: Time Trial)만 집계합니까?
- 영향: [06](./06-telemetry-design.md)
각 세션별로 구분하여 저장, 실시간 랭킹에는 타임트라이얼만 집계 하지만 다른 세션도 개별 기록은 볼 수 있어야 함
---

## E. 기술 스택 세부 (낮은 리스크, 기본값 진행 가능)

| ID | 항목 | 권장 기본값 |
|---|---|---|
| D-3 | Backend 유스케이스 실행 | 얇은 Service + 인터페이스 (MediatR는 보류) |
| D-4 | App HTTP/SignalR 클라이언트 | `dio` + `signalr_netcore` (검토 후 확정) |
| D-5 | Car/차량 개념 MVP 포함 | 제외(Track 단위 랭킹) |
| D-13 | 이벤트 순서 보장 범위 | 세션 단위 순서 |

---

## F. Phase 3 인입 결정 (2026-07-07 확정)

### D-21. Agent 인증 = 장비별 API Key (D-12 구체화)
- 배경: D-12에서 "장비별 API Key"로 방향은 정했으나 저장/전송 방식 미확정.
- **결정:** `SimRig.ApiKeyHash`에 **SHA-256(원문) hex** 저장(원문 미저장). Agent config `AgentCredential`에 원문 보관,
  접속 시 헤더 `X-Agent-Key`(쿼리 `access_token` 폴백)로 전송. 커스텀 인증 스킴(`AgentApiKey`)이 해시로 SimRig를 특정해
  연결에 `rigCode` 클레임을 귀속. **세션 매칭은 엔벨로프가 아닌 인증된 rigCode를 신뢰**(위조 방지).
  개발용 키는 시더가 `dev-agent-key-{RigCode}`로 결정적 프로비저닝. 운영 키 발급은 범위 밖.
- 영향: [05](./05-signalr-design.md), [06](./06-telemetry-design.md), backend

### D-22. 활성 세션 없는 랩 = Drop + Ack
- 배경: LapFinished가 왔으나 해당 Rig에 활성 체크인 세션이 없으면(손님이 체크인 없이 주행) 귀속 대상이 없다.
- **결정:** **저장하지 않고 Ack**(경고 로깅). D-2(Agent 무상태, 귀속=체크인) 원칙에 부합. Agent Outbox는 flush되어 무한 재시도 없음.
  파싱 실패·트랙 매핑 없음 등 영구 무효는 **Reject**(Outbox 폐기). 네트워크 무응답만 Outbox 보관·재전송.
- 영향: [06](./06-telemetry-design.md), backend

### D-23. Phase 3 범위 = 인입·저장·체크인 (브로드캐스트는 P4)
- **결정:** P3는 TelemetryHub 인입 + 멱등 + 세션매칭 + Lap 저장 + 체크인 API까지. `RankingHub` 브로드캐스트·
  랭킹 REST·PB 알림은 App 착수(P4/P5)와 함께. 저장이 검증된 뒤 실시간 계층을 얹는다.
- **정련:** `TelemetryHub.SubmitEvent`를 **요청/응답(반환값 Ack)** 으로 구현(05의 별도 Ack/Reject S→C 메서드 대신).
  상관관계가 단순·신뢰적. Ack·Reject 모두 Agent는 flush, 무응답만 재전송.
- 영향: [05](./05-signalr-design.md), [07](./07-roadmap.md)

---

## 결정 요약 (전체 확정 ✅ · 2026-07-06)

| ID | 결정 | 반영 문서 |
|---|---|---|
| D-1 | 멀티스토어 `StoreId` 선반영 | 02, 03 |
| D-2 | 랩 귀속 = 앱 체크인 세션 | 02, 03, 04 |
| D-3 | 유스케이스 = 얇은 Service + 인터페이스 | 01 |
| D-4 | App = `dio` + `signalr_netcore`(잠정) | 01 |
| D-5 | Car 개념 MVP 제외 | 02 |
| D-6 | PK = `Guid(UUID v7)` | 03 |
| D-7 | 섹터 = 가변 `LapSector` 테이블 | 02, 03, 05, 06 |
| D-8 | 랭킹 = 일/월/연 지원, 일별 자정 리셋 | 03, 04 |
| D-8a | **실시간 랭킹 기본 기준 = 월별** | 02, 03, 04, 05 |
| D-9 | Refresh Token MVP 제외 | 04 |
| D-10 | 중복 세션 = 이전 자동 종료 | 04 |
| D-11 | 앱 직접 가입(self-signup) | 04 |
| D-12 | Agent 인증 = 장비 API Key | 05, 06 |
| D-13 | 이벤트 순서 = 세션 단위 | 05 |
| D-14 | 게임 = F1 25(`F1_25`), 게임 중립 설계 | 00, 06 |
| D-15 | 무효 랩 저장 + 랭킹 제외(개별 조회 가능) | 03, 06 |
| D-16 | SessionType 구분, 랭킹 = Time Trial만 | 02, 03, 04, 05, 06 |
| D-20 | F1 UDP 파싱 = **F1Game.UDP(26.0.0)** 채택, Infra에서 게임중립 모델로 매핑(Core 무의존) | 01, 06, agent, shared/telemetry |
| D-21 | Agent 인증 = SimRig별 API Key(SHA-256 해시 저장, `X-Agent-Key` 전송, 연결에 rigCode 귀속) | 05, 06, backend |
| D-22 | 활성 세션 없는 랩 = Drop+Ack. 영구 무효 = Reject. 무응답만 재전송 | 06, backend |
| D-23 | P3 = 인입·저장·체크인. 브로드캐스트 P4. Hub는 요청/응답(반환값 Ack) | 05, 07 |

**MVP 관련 결정은 모두 확정되어 각 문서에 반영 완료.** 본 설계 문서 세트 최종 승인 시,
**Phase 0(계약 & 스캐폴딩)** 상세 설계로 진입합니다.

### Future 결정 (지금 답변 불필요 — 해당 Phase 착수 시 결정)

| ID | 항목 | 문서 |
|---|---|---|
| D-17 | 정제 1랩 트레이스 저장이 Raw-패킷 저장 금지 원칙과 양립한다는 해석 승인 | [09](./09-lap-telemetry-trace.md) |
| D-18 | 상세 텔레메트리 저장소(bytea / Object Storage / TimescaleDB) | [09](./09-lap-telemetry-trace.md) |
| D-19 | 샘플링 기준·해상도·채널 세트·보존 기간 | [09](./09-lap-telemetry-trace.md) |