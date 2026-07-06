# PROGRESS — 진행 상황 / 인수인계

> Last Updated: 2026-07-06
> **이 문서 목적:** 다른 PC·다른 세션에서도 작업을 그대로 이어가기 위한 단일 상태 파일.
> 새 세션은 이 파일 → `CLAUDE.md` → `docs/00~09` 순으로 읽으면 맥락이 복원된다.
> (주의: AI 메모리는 머신 로컬(`~/.claude`)이라 이동하지 않는다. **진행 상태의 진실 원천은 이 문서**다.)

---

## 1. 한 줄 상태

**설계(Design) 단계 완료 · 사용자 승인 완료. 아직 코드 0줄. 다음 단계 = Phase 0(계약·스캐폴딩) 상세 설계 착수.**

---

## 2. 리포지토리 현재 상태

- 위치(개발 PC 기준): `D:\SimHub`  (경로는 환경마다 다를 수 있음)
- 형상: **Greenfield.** 현재 실제 파일은 아래뿐. 코드/솔루션/프로젝트 미생성.
  ```
  CLAUDE.md            # 프로젝트 헌장(압축본, 71줄)
  docs/00~09 + PROGRESS.md
  ```
- Git: 미초기화(현 세션 기준). `shared/ backend/ agent/ app/` 폴더는 **아직 없음**(설계상 예정).

---

## 3. 완료된 작업 ✅

1. **전체 설계 문서 세트 작성** (`docs/`)
   | 문서 | 내용 |
   |---|---|
   | `00-overview.md` | Monorepo 구조 · 프로젝트 역할 · Dependency 방향 |
   | `01-architecture.md` | Backend(Clean Arch)/Agent/App Solution·폴더 구조·레이어 규칙 |
   | `02-domain-design.md` | Bounded Context 지도 + MVP 도메인 |
   | `03-entity-design.md` | ERD · Entity · PK/공통규약 · 인덱스 |
   | `04-api-design.md` | MVP REST API · DTO · 인증 · 에러 규약 |
   | `05-signalr-design.md` | SignalR 2-Hub 이벤트 계약 |
   | `06-telemetry-design.md` | F1 25 UDP 파이프라인 · Lap/Sector 판정 · Outbox |
   | `07-roadmap.md` | Phase 0~5 MVP + Future |
   | `08-open-decisions.md` | 결정 근거 + 전체 확정 요약표 |
   | `09-lap-telemetry-trace.md` | 상세 텔레메트리 조회(Future 설계) |
2. **핵심 결정 D-1~D-16 + D-8a 전부 확정** (§5 참조), 각 문서 반영 완료.
3. **사용자 최종 승인 완료** (설계 세트 approve).
4. **`CLAUDE.md` 압축 재작성** (646줄 → 71줄, 상세는 docs로 위임).

---

## 4. 다음 할 일 (미완료) ⬜

**다음 단계: Phase 0 — 계약 & 스캐폴딩 상세 설계 → 리뷰 → 구현.**
헌장 원칙에 따라 **바로 코드 작성 금지.** 먼저 아래를 "설계안"으로 제시하고 사용자 리뷰를 받는다.

Phase 0 산출 목표:
1. `shared/` 계약 초안 확정
   - `shared/openapi/openapi.yaml` (04 API 기반)
   - `shared/schema/*.json` (05 SignalR 이벤트 payload)
   - `shared/telemetry/` (06 기반, F1 25 패킷 레이아웃 오프셋 문서화)
   - `shared/samples/` (테스트용 고정 샘플)
2. 3개 솔루션 뼈대 생성(빌드만 통과하는 빈 레이어 + DI 조립)
   - `backend/`  : Domain/Application/Infrastructure/Api + tests (01 §2 구조)
   - `agent/`    : Agent.Core/Infrastructure/Tray + tests (01 §3 구조)
   - `app/`      : Flutter Feature First 스캐폴드 (01 §4 구조)

이후 순서: P1 Backend 코어/인증 → P2 Agent Core → P3 실시간 인입 → P4 랭킹·브로드캐스트 → P5 Flutter MVP.
(상세 `docs/07-roadmap.md`)

---

## 5. 확정 결정 요약 (근거: `docs/08`)

| ID | 결정 |
|---|---|
| D-1 | 멀티스토어 `StoreId` 선반영 |
| D-2 | 랩-사용자 귀속 = 앱 체크인 세션(Agent 무상태·무인증) |
| D-3 | 유스케이스 = 얇은 Service + 인터페이스 (MediatR 보류) |
| D-4 | App = `dio` + `signalr_netcore` (잠정) |
| D-5 | Car/차량 개념 MVP 제외 |
| D-6 | PK = `Guid(UUID v7)` |
| D-7 | 섹터 = 가변 `LapSector` 테이블 (타 게임 대비) |
| D-8 | 랭킹 = 일/월/연 지원, 일별 경계 = 매장 로컬 자정 |
| **D-8a** | **실시간 랭킹 기본 기준 = 월별(monthly)** |
| D-9 | Refresh Token MVP 제외 |
| D-10 | 중복 활성 세션 = 사용자 본인 이전 세션 자동 종료 |
| D-11 | 회원가입 = 앱 직접 가입(self-signup) |
| D-12 | Agent 인증 = 장비별 API Key |
| D-13 | 이벤트 순서 = 세션 단위 |
| D-14 | 대상 게임 = F1 25(`F1_25`), 도메인은 게임 중립 |
| D-15 | 무효 랩 저장 + 랭킹 제외(개별 조회 가능) |
| D-16 | SessionType 구분, 실시간 랭킹 = Time Trial만, 타 세션 개별 조회 |

**Future 결정(해당 Phase 착수 시 결정, 지금 불필요):** D-17(트레이스 저장 원칙 해석), D-18(트레이스 저장소), D-19(샘플링·채널·보존). → `docs/09`

---

## 6. 다른 환경에서 재개하는 방법

1. 리포지토리를 새 위치에 배치(현재는 Git 미초기화 — 이동 시 `docs/`+`CLAUDE.md` 동반 필수).
2. 새 세션에서 읽는 순서: **이 `PROGRESS.md` → `CLAUDE.md` → `docs/08`(결정) → 필요한 설계 문서.**
3. 진행 지점: **§4 "다음 할 일" = Phase 0 상세 설계 착수.** 코드 착수 전 설계안 리뷰부터.
4. 작업 규칙(헌장): 설계 → 리뷰 → 구현 → 리뷰. 추측 금지, 불확실하면 질문. 구조 임의 변경 금지.

### 개발 환경 전제(참고 · 미검증 항목은 착수 시 확인)
- Backend/Agent: **.NET 8 SDK** 필요.
- Backend DB: **PostgreSQL** (EF Core Code First + Migration).
- App: **Flutter SDK** (Android/iOS/Web).
- Agent: Windows + F1 25(UDP Telemetry 활성, 기본 포트 20777).
- Secrets(JWT 서명키, 장비 API Key, DB 접속)는 코드에 두지 않음(환경변수/User-Secrets).

---

## 7. 이 문서 갱신 규칙

- **Phase/작업이 진행될 때마다 §1(상태)·§3(완료)·§4(다음 할 일)를 갱신**한다.
- 새 결정이 생기면 `docs/08`에 추가하고 §5 요약에 반영한다.
- 이 문서가 항상 "지금 어디까지 왔고 다음에 뭘 하는지"의 단일 진실이 되도록 유지한다.
