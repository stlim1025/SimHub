# 08 · Open Decisions — 승인 필요 결정사항

> Status: **Design** · Last Updated: 2026-10-18 (프로필·설정: D-39 추가. P7 시즌·세션: D-28~34 추가. P6 개인 모드: D-25~27 추가·대체된 결정 표기는 2026-10-17)
> AI 작업 규칙("추측 금지, 필요 시 질문") 준수를 위해, **추측 없이 사용자 승인이 필요한 결정**을 모은다.
> 각 항목: 배경 / 선택지 / **권장안** / 영향 문서. 승인 시 각 문서에 반영한다.

---

## A. 반드시 먼저 확정해야 할 핵심 결정 (구조에 영향)

### D-1. 멀티스토어(Multi-Store) 선반영 여부 — → D-25로 대체
> **→ D-25로 대체 (2026-10-17):** 개인 모드에는 매장이 없다. `Store`·`StoreId`는 마이그레이션 `PersonalMode`로 제거됐다.
- 배경: 헌장은 "SaaS 수준" 목표, MVP는 단일 매장.
- 선택지: (a) `StoreId`를 Entity에 지금 반영 / (b) 나중에 마이그레이션으로 추가.
- **권장:** (a). 지금 넣는 비용은 작고, 나중에 소급 추가는 데이터 마이그레이션 리스크가 큼. (확장성 우선)
답변 : (a)안으로
- 영향: [02](./02-domain-design.md), [03](./03-entity-design.md)

### D-2. 랩 ↔ 사용자 귀속(Attribution) 방식 ⭐가장 중요 — → D-25로 대체
> **→ D-25로 대체 (2026-10-17):** 랩은 계정에 연결된 Agent 장치의 주인에게 귀속한다. 체크인 세션(`DrivingSession`)은 제거됐다.
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
  > 타임존 출처는 D-24 → **D-27**(서버 설정 `Ranking:TimeZoneId`)로 바뀌었다. 일/월/연·자정 리셋 결정은 유지된다.
- 영향: [03](./03-entity-design.md), [04](./04-api-design.md)
- ❓ **질문:** 랭킹 리셋 기준 시각(예: 자정/영업 시작)은?
일별 랭킹, 월별랭킹, 연도별 랭킹을 지원할 예정 일별 랭킹의 리셋 시간은 자정
---

## C. 인증/세션 결정

### D-9. Refresh Token 도입
- **권장:** MVP 제외(단순 access token + 재로그인). 보안 요구 커지면 도입.
- 영향: [04](./04-api-design.md)

### D-10. 사용자 중복 활성 세션 정책 — → D-25로 대체
> **→ D-25로 대체 (2026-10-17):** 체크인 세션이 없어져 중복 세션 정책도 필요 없다.
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

### D-12. Agent(장비) 인증 방식 — → D-25로 대체
> **→ D-25로 대체 (2026-10-17):** 좌석(SimRig)별 키 대신 계정에 연결된 장치별 키를 쓴다(연결 방식은 D-26).
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

### D-21. Agent 인증 = 장비별 API Key (D-12 구체화) — → D-25로 대체
> **→ D-25로 대체 (2026-10-17):** `SimRig.ApiKeyHash`·`rigCode` 클레임·개발용 좌석 키 시드는 제거됐다. `X-Agent-Key` 헤더와
> SHA-256 해시 저장은 그대로 쓰되 키가 `AgentDevice`를 가리키고, 연결에는 `deviceId`·`sub` 클레임이 귀속된다(D-26).
- 배경: D-12에서 "장비별 API Key"로 방향은 정했으나 저장/전송 방식 미확정.
- **결정:** `SimRig.ApiKeyHash`에 **SHA-256(원문) hex** 저장(원문 미저장). Agent config `AgentCredential`에 원문 보관,
  접속 시 헤더 `X-Agent-Key`(쿼리 `access_token` 폴백)로 전송. 커스텀 인증 스킴(`AgentApiKey`)이 해시로 SimRig를 특정해
  연결에 `rigCode` 클레임을 귀속. **세션 매칭은 엔벨로프가 아닌 인증된 rigCode를 신뢰**(위조 방지).
  개발용 키는 시더가 `dev-agent-key-{RigCode}`로 결정적 프로비저닝. 운영 키 발급은 범위 밖.
- 영향: [05](./05-signalr-design.md), [06](./06-telemetry-design.md), backend

### D-22. 활성 세션 없는 랩 = Drop + Ack — → D-25로 대체
> **→ D-25로 대체 (2026-10-17):** 랩은 항상 장치 주인에게 귀속되므로 Drop 규칙이 없어졌다. 대신 없거나 연결 해제된 장치의
> 이벤트는 **Reject**("연결이 해제된 장치입니다.")한다. 영구 무효 = Reject, 무응답만 재전송 규칙은 유지된다.
> 단, 이 연결 해제 Reject는 Agent가 Outbox에서 지우지 않고 `다시 연결 필요`로 멈춘다(401과 같은 처리, [11](./11-personal-mode.md) §6.4).
- 배경: LapFinished가 왔으나 해당 Rig에 활성 체크인 세션이 없으면(손님이 체크인 없이 주행) 귀속 대상이 없다.
- **결정:** **저장하지 않고 Ack**(경고 로깅). D-2(Agent 무상태, 귀속=체크인) 원칙에 부합. Agent Outbox는 flush되어 무한 재시도 없음.
  파싱 실패·트랙 매핑 없음 등 영구 무효는 **Reject**(Outbox 폐기). 네트워크 무응답만 Outbox 보관·재전송.
- 영향: [06](./06-telemetry-design.md), backend

### D-23. Phase 3 범위 = 인입·저장·체크인 (브로드캐스트는 P4)
- **결정:** P3는 TelemetryHub 인입 + 멱등 + 세션매칭 + Lap 저장 + 체크인 API까지. `RankingHub` 브로드캐스트·
  랭킹 REST·PB 알림은 App 착수(P4/P5)와 함께. 저장이 검증된 뒤 실시간 계층을 얹는다.
- **정련:** `TelemetryHub.SubmitEvent`를 **요청/응답(반환값 Ack)** 으로 구현(05의 별도 Ack/Reject S→C 메서드 대신).
  상관관계가 단순·신뢰적. Ack·Reject 모두 Agent는 flush, 무응답만 재전송.
  (P6: 연결 해제 Reject만 예외로 보관 — D-25, [11](./11-personal-mode.md) §6.4)
- 영향: [05](./05-signalr-design.md), [07](./07-roadmap.md)

## G. Phase 4 랭킹·브로드캐스트 결정 (2026-07-08 확정)

### D-24. 랭킹 기간 경계 타임존 = `Store.TimeZoneId` (D-8 구체화) — 타임존 출처 → D-27로 대체
> **타임존 출처 → D-27로 대체 (2026-10-17):** `Store.TimeZoneId`·`IStoreRepository` 대신 서버 설정 `Ranking:TimeZoneId`를 쓴다.
> 경계 계산(`RankingPeriodRange`), 쿼리 온디맨드, 브로드캐스트 규칙은 유지된다.
- 배경: D-8이 "일별 경계 = 매장 로컬 자정"으로 방향은 정했으나 타임존 보관 위치 미확정. `Store`에 타임존 필드가 없었다.
- **결정:** `Store`에 **`TimeZoneId`(IANA, 예 `Asia/Seoul`)** 필드 추가(마이그레이션 `AddStoreTimeZone`, 기존 행 기본값 `""` → 시더 백필).
  기간(일/월/연) 경계는 순수 헬퍼 `RankingPeriodRange`가 이 타임존의 자정 기준으로 계산 후 UTC로 환산한다.
  **MVP 단순화:** `/rankings`는 store 파라미터가 없어 (유일한) 매장 타임존을 사용(`IStoreRepository.GetPrimaryTimeZoneIdAsync`).
  멀티스토어 확장 시 `storeId` 파라미터화. 랭킹 = **쿼리 온디맨드**(materialized 테이블 없음, 기존 Lap 인덱스 활용).
- **브로드캐스트:** 저장 커밋 후 best-effort. 유효 랩→`LapRecorded`(user 그룹), PB 갱신→`PersonalBestAchieved`(user 그룹),
  랭킹적격→월별 TOP10 재조회 후 `RankingUpdated`(track 그룹, D-8a). `IRankingNotifier` 포트(Application)를 Api가 `IHubContext<RankingHub>`로 구현.
- 영향: [03](./03-entity-design.md), [04](./04-api-design.md), [05](./05-signalr-design.md), backend

## H. Phase 6 개인 모드 결정 (2026-10-17 확정, 상세: [11](./11-personal-mode.md))

### D-25. 제품 방향 = 개인 모드로 전환
- 배경: MVP(P0~P5) 완료 후 제품 방향을 카페 운영 플랫폼에서 **개인용 F1 기록 플랫폼**(F1Laps 참고)으로 바꾼다.
- **결정:** 카페 운영 모델(매장·좌석·체크인)을 쓰지 않는다. 사용자가 **자기 PC에 Agent를 설치하고 자기 계정에 연결**한다.
  랩은 연결된 장치(`AgentDevice`)의 주인에게 귀속한다(`Lap.UserId = device.UserId`, `Lap.AgentDeviceId = device.Id`).
  마이그레이션 `PersonalMode`가 `stores`·`sim_rigs`·`driving_sessions`를 삭제하고, 귀속할 장치가 없는 기존 랩·섹터·멱등 기록
  (로컬 개발·테스트 데이터)을 지운다(사용자 승인 2026-10-17). 회원·트랙은 유지한다.
- **대체되는 결정:** D-1(멀티스토어 `StoreId`), D-2(랩 귀속 = 체크인 세션), D-10(중복 세션 정책),
  D-12·D-21(좌석별 API Key), D-22(활성 세션 없는 랩 Drop), D-24 중 **타임존 출처**(`Store.TimeZoneId`).
- **유지되는 결정:** D-6(UUID v7), D-7(가변 섹터), D-8·D-8a(일/월/연 랭킹, 기본 월별), D-13, D-14(F1 25),
  D-15·D-16(무효 랩 저장, 랭킹 = Time Trial만), D-20(F1Game.UDP), D-23(Hub 요청/응답 Ack), D-24 중 경계 규칙과 브로드캐스트 규칙.
- 영향: [00](./00-overview.md), [02](./02-domain-design.md), [03](./03-entity-design.md), [04](./04-api-design.md),
  [05](./05-signalr-design.md), [06](./06-telemetry-design.md), [07](./07-roadmap.md), [11](./11-personal-mode.md), backend, agent, app

### D-26. Agent 계정 연결 = 1회용 연결 코드 → 장치별 키
- **결정:** 웹에서 10분짜리 1회용 코드를 발급하고(`POST /me/agent-pairing-codes`), Agent가 그 코드를 장치별 장기 키로 교환한다
  (`POST /agent/pair`, 키 원문은 응답에서 한 번만). 이후 인증은 기존 `X-Agent-Key` 메커니즘(SHA-256 해시 저장)을 그대로 쓰되,
  키가 **AgentDevice**를 가리키고 연결에 `deviceId`·`sub`(장치 주인) 클레임이 귀속된다. 연결 해제 = soft delete이며,
  이미 열린 연결로 오는 이벤트도 인입 시 장치를 다시 확인해 Reject한다.
- 검토한 대안: 계정 고정 코드(F1Laps 방식, 노출 시 도용·일괄 재발급 필요), Agent에서 이메일·비밀번호 로그인(Refresh Token 필요, 트레이 앱이 비밀번호를 다룸).
- 영향: [04](./04-api-design.md), [05](./05-signalr-design.md), [06](./06-telemetry-design.md), [11](./11-personal-mode.md), backend, agent

### D-27. 랭킹 기간 경계 타임존 = 서버 설정 `Ranking:TimeZoneId`
- **결정:** 기본값 `Asia/Seoul`(IANA). 서버 시작 시 검증하고, 잘못되면 시작을 실패시킨다(fail fast).
  경계 계산(`RankingPeriodRange`)은 그대로다. 타임존을 어디서 읽는지만 바뀐다(D-24의 `Store.TimeZoneId` 대체).
- 영향: [03](./03-entity-design.md), [04](./04-api-design.md), [11](./11-personal-mode.md), backend

> D-28~D-34는 P7 시즌·세션([12](./12-seasons-sessions.md))이 쓴다.

### D-35. 서버 오류가 반복되는 Outbox 항목 = 격리하지 않고 그 항목만 미룬다 (2026-10-17)
- **결정:** 같은 항목에 서버 오류가 5번(`ItemDeferThreshold`) 나면 그 항목만 30초부터 두 배씩 최대 5분 간격으로 다시 시도하고, 뒤 항목을 먼저 보낸다.
  영구 무효 입력은 이미 Reject이므로 서버 **예외**는 서버 쪽 문제로 보고, 고쳐지면 저절로 올라가게 한다.
- 검토한 대안: N번 실패 시 dead-letter(서버 전체 장애 동안 항목이 하나씩 격리됨), 다른 항목 성공을 증거로 dead-letter(랩 경로만 깨진 배포에서 모든 랩 격리 — 리뷰에서 기각),
  허브가 예외를 Reject로 변환(일시 장애도 삭제 = 손실), 최대 나이(TTL).
- 상세: [13](./13-outbox-dead-letter.md) §2·§3.2. 영향: agent

### D-36. 업로드 실패 분류 = 서버 오류만 센다
- **결정:** 세션 경계가 허브 메서드 예외·오류와 함께 연결 종료·빈 응답·60초 무응답을 `TelemetryHubServerException`으로 알리고, 업로더는 그것만 센다.
  연결 실패·전송 중 끊김은 세지도 초기화하지도 않는다(같은 항목을 순서대로 재시도). 장치 키가 바뀌거나 거부되면 기록을 비운다. 기록은 메모리에만 둔다.
- 상세: [13](./13-outbox-dead-letter.md) §3.1. 영향: agent

### D-37. dead-letter = 읽을 수 없는 payload만
- **결정:** JSON으로 읽히지 않는 Outbox 항목만 같은 SQLite 파일의 `outbox_dead_letter` 테이블로 옮기고(한 트랜잭션) 다음 항목으로 간다. 자동 삭제는 없다.
- 상세: [13](./13-outbox-dead-letter.md) §3.4. 영향: agent

### D-38. 올리지 못한 기록 알림 + D-13 순서의 예외
- **결정:** 로그와 Tray "계정 연결" 영역에 `서버가 처리하지 못한 기록 N건 — 자동으로 다시 보냅니다` · `읽을 수 없어 따로 보관한 기록 N건`을 보인다.
  미뤄진 항목은 뒤 항목보다 늦게 도착할 수 있다(D-13 예외). 영향은 도착 순서로 계산하는 PB 알림과 P7 링크 키 다툼(12 §6.2)뿐이다.
- 상세: [13](./13-outbox-dead-letter.md) §3.3·§3.5. 영향: agent

---

## I. Phase 7 시즌·세션 결정 (2026-10-17 확정, 상세: [12](./12-seasons-sessions.md))

> 사용자가 질문 없이 진행(자동 모드)하도록 요청해, 아래는 권장안을 기본값으로 확정한 것이다. 바꾸려면 새 결정으로 해당 항목을 대체한다.

### D-28. 세션 결과 수집 = 세션당 최종 순위표 1건(`SessionClassified`)
- **결정:** Agent가 Final Classification 패킷을 받으면 같은 세션의 Session 맥락(모드·링크 식별자·트랙)과 Participants(이름·팀·AI 여부)를
  차 번호(`carIndex`)로 합쳐 도메인 이벤트 1건을 보낸다. 같은 `SessionRef`로는 한 번만 보낸다. raw 패킷은 보내지 않는다(헌장).
- 이유: 이벤트 하나가 자기 완결적이라 순서·재전송·중복에 강하다. 22대 기준 약 10KB다.
- 검토한 대안: (a) Participants·Classification을 각각 이벤트로 보내고 서버에서 합치기 — 패킷 중계에 가깝고, 두 이벤트의 순서·누락을 서버가 다뤄야 한다.
  (b) `SessionStarted`에 맥락을 싣고 `SessionClassified`에는 결과만 — 이벤트끼리 의존이 생겨 재접속·재개 시 깨지기 쉽다.
- 영향: [05](./05-signalr-design.md), [06](./06-telemetry-design.md), [12](./12-seasons-sessions.md) §5, `shared/schema`, backend, agent

### D-29. 시즌·주말·세션 식별 = 게임 링크 식별자(시즌 대상 모드에서만)
- **결정:** `SeasonLinkIdentifier`·`WeekendLinkIdentifier`·`SessionLinkIdentifier`(`uint`, "세이브가 바뀌어도 유지")로 묶는다.
  **시즌 대상** = 게임 모드가 커리어 4종(Driver Career · My Team · Online Career · Challenge Career) 또는 Grand Prix이고 시즌·주말 링크가 모두 0이 아닐 때.
  그 밖의 세션(온라인 로비, 스토리 등)은 시즌 없이 Sessions 목록에만 나온다.
- **세션 키:** 시즌 대상이고 세션 링크가 0이 아니면 `link:{season}:{weekend}:{session}`, 그 밖에는 `uid:{SessionRef}`. 사용자·게임별로 유일하다.
  링크 값의 의미를 확인하지 못한 모드(온라인 등)에서 서로 다른 세션이 같은 키로 덮이지 않게 하기 위해서다.
- 같은 키로 다시 분류되면 최신 결과로 병합한다(세션 재시작, 세이브 불러온 뒤 다시 완주). 저장된 세션과 트랙 또는 세션 종류가 다르면 `uid:` 키로 따로 저장하고
  경고 로그를 남기며 시즌·주말에 넣지 않는다. 받은 시각이 저장된 것보다 이르면 무시한다.
- 랩도 같은 규칙으로 `Lap.SessionKey`를 저장한다(P8에서 세션과 연결하기 위한 씨앗, P7은 조회에 쓰지 않는다).
- 이 가정들(링크 값이 세션 재시작·다음 해에 어떻게 변하는지 등)은 게임에서 확인해야 한다 — [12](./12-seasons-sessions.md) §3.3, [TESTING-local-e2e.md](./TESTING-local-e2e.md) §10.
- 영향: [02](./02-domain-design.md), [03](./03-entity-design.md), [12](./12-seasons-sessions.md) §4·§6, backend, agent

### D-30. Sessions 목록 = 최종 순위가 확정된 세션만, Time Trial 제외
- **결정:** 최종 순위표를 받은 세션만 `GameSession`이 된다(중간에 나간 세션은 목록에 없다). Time Trial은 Laps·Leaderboard가 담당하므로
  Agent는 `SessionType.TimeTrial` 순위표를 보내지 않고, **백엔드도** `sessionType` 또는 `gameMode`가 TimeTrial이면 저장하지 않고 Ack한다.
- 이유: 정책의 최종 판정은 백엔드에 둔다(D-15와 같은 원칙). Agent만 거르면 옛·다른 Agent가 보낸 Time Trial 순위표가 그대로 저장된다.
- 영향: [06](./06-telemetry-design.md), [12](./12-seasons-sessions.md) §5.3·§6.2, backend, agent

### D-31. Standings = 기록된 세션의 점수 합(본 레이스 카운트백), Constructors 포함
- **결정:** 드라이버 점수 = 그 시즌에 **기록된** 세션의 `Points` 합(스프린트 포함). 게임 안의 공식 순위표가 아니라 Agent가 받은 세션 기준이며,
  화면에 "기록된 세션 기준"을 표시한다.
- **계산 대상 세션:** 같은 주말·같은 세션 종류(`SessionKind`, `Unknown` 제외)가 여러 건이면 `ClassifiedAt`이 가장 늦은 1건만 쓴다(링크 식별자가 바뀌어 같은 세션이 두 번 저장된 경우의 이중 집계 방지).
- **본 레이스:** 주말마다 레이스 세션(`SessionType.Race`) 중 `ClassifiedAt`이 가장 늦은 1건. 우승·포디움·카운트백은 본 레이스만 센다(스프린트는 점수에만 들어간다).
  기록된 레이스가 스프린트 하나뿐인 주말은 그 스프린트가 본 레이스가 된다.
- 동점: 본 레이스 1위 횟수 → 2위 횟수 → … → 표시 이름 오름차순(Ordinal) → `DriverKey` 오름차순(Ordinal).
  Constructors = 팀별 점수 합, 동점은 우승 수 → 팀 이름 오름차순(Ordinal) → 팀 ID 오름차순.
- 이유: 스프린트 우승을 GP 우승으로 세면 실제 F1 규칙과 어긋난다. 이중 집계 방지는 가정(§3.3)이 틀렸을 때의 안전장치다.
- 영향: [12](./12-seasons-sessions.md) §7.3, backend, app

### D-32. 시즌 안의 드라이버 식별 = 플레이어 → 게임 드라이버 ID → 이름+차 번호
- **결정:** `isPlayer`(그 PC의 플레이어 차)이면 `player`, 게임 드라이버 ID가 있으면 `driver:{id}`, 없으면(네트워크 사람 등) `name:{정규화한 이름}#{차 번호}`.
  참가자 정보를 못 받은 차는 `car:{SessionRef}:{carIndex}` — 그 세션 안에서만 유일하다(다른 라운드의 다른 드라이버와 합쳐지지 않게).
- 이유: 커리어에서 플레이어의 드라이버 ID는 게임마다 특수값일 수 있고, 온라인 사람은 ID가 `NetworkHuman`(65535)이다.
- 영향: [12](./12-seasons-sessions.md) §4.4, backend

### D-33. 팀 이름·색 = 백엔드의 게임별 정적 카탈로그
- **결정:** `(gameCode, teamId)` → 표시 이름·색(hex). F1 25의 2025 팀 10개, 2024 차량 10개, 2026 시즌팩 팀 11개, My Team(104), F1 Generic(41)을 넣고,
  없는 ID는 `Team {id}` + 중립 회색으로 보인다. API가 `teamName`·`teamColor`를 내려 주어 앱은 매핑하지 않는다.
- 이유: 상수 표(불변)라 헌장의 "Global Static 금지"(가변 전역 상태)에 해당하지 않는다. `GameCodes`와 같은 성격이다.
- 영향: [04](./04-api-design.md), [12](./12-seasons-sessions.md) §7.4, backend

### D-34. 남의 시즌·세션 조회 = 404
- **결정:** 조회 API는 모두 `sub` 기준으로 내 것만 찾는다. 남의 ID는 없는 ID와 똑같이 404를 돌려준다(존재 여부를 알려 주지 않는다).
  (P6의 장치 해제는 쓰기 작업이라 403을 유지한다.)
- 영향: [04](./04-api-design.md), backend

---

## J. 프로필·계정 설정 결정 (2026-10-18 확정, 상세: [14](./14-profile-settings.md))

> 사용자 요청("내 프로필 누르면 설정화면이 나와야 해", F1Laps Edit Profile 참고)과 컨트롤러 결정(R1~R10)을 질문 없이 기본값으로 확정했다.

### D-39. 프로필·설정 = User의 설정 필드 + 전체 교체 API, 이름 비공개는 랭킹에서 "익명 드라이버"
- **범위:** 이메일·닉네임 변경, 랭킹 이름 공개 여부, 게임·컨트롤러·플랫폼·단위·타임존·테마, 프로필 사진, 저장/취소, 로그아웃.
  결제·구독(헌장 제외)·비밀번호 변경·계정 삭제는 하지 않는다.
- **저장:** `User`에 `ShowOnLeaderboard`(기본 true)·`AvatarTeam`(null)·`PreferredGame`(`F1_25`)·`Controller`(`Wheel`)·`Console`(`Pc`)·`Units`(`Metric`)·
  `TimeZoneId`(`Asia/Seoul`, IANA만)·`Theme`(`System`). enum은 문자열. 마이그레이션 `AddUserProfileSettings`가 기존 사용자를 기본값으로 백필한다.
  게임·컨트롤러·플랫폼·단위·타임존은 **저장만** 하고 이후 Phase에서 쓴다(랭킹 기간 경계는 계속 D-27의 서버 설정).
- **API:** `GET /me`가 설정을 함께 돌려주고, `PUT /me/profile`(전체 교체, 필드별 400)·`POST /me/email`(현재 비밀번호 확인 — 틀리면 401이 아니라 400, 중복 409).
  닉네임은 폼에서 함께 저장하고, 이메일은 대화상자에서 바로 저장한다.
- **랭킹 비공개:** `ShowOnLeaderboard = false`면 `/rankings`와 RankingHub `RankingUpdated`의 표시 이름이 `익명 드라이버`(순위·기록은 그대로). `/me/*`는 영향 없음.
- **프로필 사진:** 실제 팀 로고(상표) 대신 팀 색 원 + 코드 `MER FER RBR MCL AST ALP WIL RB SAU HAA`. 코드 목록은 백엔드 `AvatarTeamCodes`·앱 `kAvatarTeams`·OpenAPI enum이 같다.
- **테마:** 밝은 팔레트 추가(`AppColors.light*` + `AppPalette` 테마 확장), System은 기기 밝기를 따른다. 로그인·스플래시는 System. 어두운 화면은 그대로.
- 영향: [03](./03-entity-design.md), [04](./04-api-design.md), [05](./05-signalr-design.md), [14](./14-profile-settings.md), backend, app, shared/openapi

---

## 결정 요약 (전체 확정 ✅ · 2026-07-06, 2026-10-17 P6 갱신, 2026-10-18 P7 갱신)

| ID | 결정 | 반영 문서 |
|---|---|---|
| D-1 | ~~멀티스토어 `StoreId` 선반영~~ → D-25로 대체 | 02, 03 |
| D-2 | ~~랩 귀속 = 앱 체크인 세션~~ → D-25로 대체 | 02, 03, 04 |
| D-3 | 유스케이스 = 얇은 Service + 인터페이스 | 01 |
| D-4 | App = `dio` + `signalr_netcore`(잠정) | 01 |
| D-5 | Car 개념 MVP 제외 | 02 |
| D-6 | PK = `Guid(UUID v7)` | 03 |
| D-7 | 섹터 = 가변 `LapSector` 테이블 | 02, 03, 05, 06 |
| D-8 | 랭킹 = 일/월/연 지원, 일별 자정 리셋 | 03, 04 |
| D-8a | **실시간 랭킹 기본 기준 = 월별** | 02, 03, 04, 05 |
| D-9 | Refresh Token MVP 제외 | 04 |
| D-10 | ~~중복 세션 = 이전 자동 종료~~ → D-25로 대체 | 04 |
| D-11 | 앱 직접 가입(self-signup) | 04 |
| D-12 | ~~Agent 인증 = 장비 API Key~~ → D-25로 대체 | 05, 06 |
| D-13 | 이벤트 순서 = 세션 단위 | 05 |
| D-14 | 게임 = F1 25(`F1_25`), 게임 중립 설계 | 00, 06 |
| D-15 | 무효 랩 저장 + 랭킹 제외(개별 조회 가능) | 03, 06 |
| D-16 | SessionType 구분, 랭킹 = Time Trial만 | 02, 03, 04, 05, 06 |
| D-20 | F1 UDP 파싱 = **F1Game.UDP(26.0.0)** 채택, Infra에서 게임중립 모델로 매핑(Core 무의존) | 01, 06, agent, shared/telemetry |
| D-21 | ~~Agent 인증 = SimRig별 API Key(SHA-256 해시 저장, `X-Agent-Key` 전송, 연결에 rigCode 귀속)~~ → D-25로 대체 | 05, 06, backend |
| D-22 | ~~활성 세션 없는 랩 = Drop+Ack~~ → D-25로 대체. 영구 무효 = Reject. 무응답만 재전송(유지) | 06, backend |
| D-23 | P3 = 인입·저장·체크인. 브로드캐스트 P4. Hub는 요청/응답(반환값 Ack) | 05, 07 |
| D-24 | 랭킹 기간 경계 타임존 = ~~`Store.TimeZoneId`(IANA)~~ → D-27로 대체. 랭킹 = 쿼리 온디맨드. 브로드캐스트 = 커밋 후 best-effort(`IRankingNotifier`) | 03, 04, 05, backend |
| D-25 | **개인 모드 전환**: 매장·좌석·체크인 제거, 랩 귀속 = 계정에 연결된 Agent 장치(장치 주인) | 00, 02~07, 11, backend, agent, app |
| D-26 | Agent 계정 연결 = 1회용 연결 코드(10분) → 장치별 키(`X-Agent-Key`, SHA-256 해시 저장, `deviceId`·`sub` 클레임) | 04, 05, 06, 11, backend, agent |
| D-27 | 랭킹 기간 경계 타임존 = 서버 설정 `Ranking:TimeZoneId`(기본 `Asia/Seoul`, 시작 시 검증) | 03, 04, 11, backend |
| D-28 | 세션 결과 수집 = 세션당 최종 순위표 1건(`SessionClassified`, Participants·Final Classification을 Agent가 합침) | 05, 06, 12, agent, backend |
| D-29 | 시즌·주말·세션 식별 = 게임 링크 식별자(시즌 대상 모드만), 세션 키 `link:`/`uid:`, 같은 키는 최신 결과로 병합, `Lap.SessionKey` 저장 | 02, 03, 12, backend, agent |
| D-30 | Sessions 목록 = 최종 순위가 확정된 세션만, Time Trial 제외(Agent·백엔드 모두) | 06, 12, backend, agent |
| D-31 | Standings = 기록된 세션 점수 합, 우승·포디움·카운트백은 본 레이스만, 같은 주말·종류는 최신 1건, Constructors 포함 | 12, backend, app |
| D-32 | 시즌 안의 드라이버 식별 = `player` → `driver:{id}` → `name:{이름}#{번호}` (→ `car:{SessionRef}:{carIndex}`) | 12, backend |
| D-33 | 팀 이름·색 = 백엔드의 게임별 정적 카탈로그(`TeamCatalog`), 앱은 매핑하지 않음 | 04, 12, backend |
| D-34 | 남의 시즌·세션 조회 = 404(없는 것과 동일) | 04, backend |
| D-35 | 서버 오류가 반복되는 Outbox 항목 = 격리하지 않고 그 항목만 미룸(5번 → 30초~최대 5분, 뒤 항목 먼저) | 13, agent |
| D-36 | 업로드 실패 분류 = 서버 오류(`TelemetryHubServerException`)만 셈, 연결 문제는 세지 않음, 키 변경 시 초기화 | 13, agent |
| D-37 | dead-letter = 읽을 수 없는 payload만(`outbox_dead_letter`, 자동 삭제 없음) | 13, agent |
| D-38 | 올리지 못한 기록을 로그·Tray에 표시, 미뤄진 항목은 D-13 순서의 예외 | 13, agent |
| D-39 | 프로필·설정 = User 설정 필드(저장만 하는 항목 포함) + `PUT /me/profile`·`POST /me/email`, 이름 비공개 = 랭킹에서 "익명 드라이버", 사진 = 팀 색 원(로고 미사용), 밝은 테마 + System | 03, 04, 05, 14, backend, app |

**MVP 관련 결정은 모두 확정되어 각 문서에 반영 완료.** 본 설계 문서 세트 최종 승인 시,
**Phase 0(계약 & 스캐폴딩)** 상세 설계로 진입합니다.

### Future 결정 (지금 답변 불필요 — 해당 Phase 착수 시 결정)

| ID | 항목 | 문서 |
|---|---|---|
| D-17 | 정제 1랩 트레이스 저장이 Raw-패킷 저장 금지 원칙과 양립한다는 해석 승인 | [09](./09-lap-telemetry-trace.md) |
| D-18 | 상세 텔레메트리 저장소(bytea / Object Storage / TimescaleDB) | [09](./09-lap-telemetry-trace.md) |
| D-19 | 샘플링 기준·해상도·채널 세트·보존 기간 | [09](./09-lap-telemetry-trace.md) |