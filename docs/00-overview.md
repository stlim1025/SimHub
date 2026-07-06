# 00 · Overview — Monorepo 구조 · 프로젝트 역할 · Dependency 방향

> Status: **Design (미승인)** · Last Updated: 2026-07-06
> 이 문서는 설계안이며, 구현 전 승인이 필요합니다. 미확정 항목은 [08-open-decisions.md](./08-open-decisions.md) 참조.

---

## 1. 목적

이 문서는 SimCenter Monorepo의 **최상위 물리 구조**와 **각 프로젝트 간 의존성 방향**을 정의한다.
개별 프로젝트 내부 구조는 [01-architecture.md](./01-architecture.md)에서 다룬다.

핵심 설계 목표(헌장 준수):

- 확장성 · 유지보수성 · 테스트 용이성 · 성능
- SOLID / Clean Architecture
- 계약(Contract) 기반 통합 — 프로젝트 간 결합도 최소화

---

## 2. Monorepo 디렉토리 구조

```
SimCenter/
├── docs/                     # 프로젝트 문서 (설계, 결정, 다이어그램)
│   ├── 00-overview.md
│   ├── 01-architecture.md
│   ├── 02-domain-design.md
│   ├── 03-entity-design.md
│   ├── 04-api-design.md
│   ├── 05-signalr-design.md
│   ├── 06-telemetry-design.md
│   ├── 07-roadmap.md
│   └── 08-open-decisions.md
│
├── shared/                   # 프로젝트 계약(Contract) — 코드가 아닌 스펙
│   ├── openapi/              # REST API 계약 (openapi.yaml)
│   ├── schema/               # JSON Schema (SignalR 이벤트, Telemetry 이벤트 payload)
│   ├── telemetry/            # F1 UDP 패킷 사양 요약, 이벤트 정의
│   └── samples/              # 샘플 payload (테스트/문서용 고정 데이터)
│
├── backend/                  # ASP.NET Core 8 — 서버 (Clean Architecture)
│   └── (상세: 01-architecture.md)
│
├── agent/                    # .NET 8 — Windows Telemetry Agent
│   └── (상세: 01-architecture.md)
│
├── app/                      # Flutter — 모바일/웹 앱 (Feature First)
│   └── (상세: 01-architecture.md)
│
├── .editorconfig             # (예정) 공통 코딩 스타일
├── .gitignore
└── README.md
```

> **원칙:** `shared/`는 실행 코드를 담지 않는다. 세 런타임(Backend/Agent/App)이 각자의 언어로
> 코드를 생성/구현하되, **동일한 계약**을 참조하도록 하는 "단일 진실 원천(Single Source of Truth)"이다.

---

## 3. 각 프로젝트의 역할

### 3.1 `shared` — Contract Layer (계약)

| 항목 | 내용 |
|---|---|
| 성격 | 문서/스펙 저장소 (런타임 코드 없음) |
| 포함 | OpenAPI, JSON Schema, Telemetry Spec, 샘플 데이터 |
| 소비자 | Backend(서버 계약 준수 검증), Agent(이벤트 payload), App(DTO 생성 근거) |
| 규칙 | **모든 프로젝트가 shared를 참조하되, shared는 어떤 프로젝트도 참조하지 않는다.** |

`shared`는 "코드 공유"가 아니라 **"계약 공유"**다. 예: App의 Dart DTO와 Backend의 C# DTO는
서로 다른 코드지만, 둘 다 `shared/openapi/openapi.yaml`이라는 하나의 계약을 만족해야 한다.

### 3.2 `agent` — Telemetry Producer (생산자)

| 항목 | 내용 |
|---|---|
| 런타임 | .NET 8 / C# / Windows |
| 입력 | F1 게임 UDP Telemetry (기본 20777) |
| 처리 | Packet Parse → Lap/Sector Analyze → 의미 있는 **도메인 이벤트** 생성 |
| 출력 | SignalR로 Backend에 이벤트 전송 (Raw 패킷 전송 금지) |
| 내구성 | 오프라인 시 SQLite 캐시 → 복구 시 자동 재전송 |
| 형태 | Windows Tray Application (자동 실행 / 자동 재접속) |

### 3.3 `backend` — Core / Orchestrator (핵심 서버)

| 항목 | 내용 |
|---|---|
| 런타임 | ASP.NET Core 8 |
| 아키텍처 | Clean Architecture + Repository Pattern |
| DB | PostgreSQL (EF Core, Code First, Migration) |
| 제공 | REST API(조회/명령) + SignalR Hub(실시간 이벤트) + JWT 인증 |
| 역할 | Agent 이벤트 수신·검증·영속화 → 랭킹 계산 → App에 브로드캐스트 |

### 3.4 `app` — Consumer / Experience (소비자)

| 항목 | 내용 |
|---|---|
| 런타임 | Flutter (Android / iOS / Web) |
| 아키텍처 | Feature First + Riverpod + GoRouter + Material 3 |
| 입력 | Backend REST(조회) + SignalR(실시간 랭킹 갱신) |
| MVP 화면 | Splash · Login · Home · Today's Ranking · My Lap Record |

---

## 4. Dependency 방향 (가장 중요)

프로젝트 간 의존성은 **단방향**이며, 실제 코드 참조가 아니라 **계약과 네트워크 프로토콜**을 통해 이루어진다.

```
                         ┌──────────────────────┐
                         │       shared         │   (Contract — 무의존)
                         │  OpenAPI / Schema /   │
                         │  Telemetry Spec       │
                         └──────────▲───────────┘
                                    │ conforms to (계약 준수)
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
        ┌─────┴─────┐         ┌─────┴─────┐         ┌─────┴─────┐
        │   agent   │         │  backend  │         │    app    │
        │ (Producer)│         │  (Core)   │         │(Consumer) │
        └─────┬─────┘         └─────▲─────┘         └─────┬─────┘
              │                     │                     │
              │  SignalR (이벤트 인입) │                     │
              └────────────────────►│◄────────────────────┘
                                    │   REST(조회) + SignalR(브로드캐스트)
                                    ▼
                            ┌───────────────┐
                            │  PostgreSQL   │
                            └───────────────┘
```

### 규칙

1. **shared는 아무것도 의존하지 않는다.** (최상위 안정 계약)
2. **agent / backend / app 은 shared만 의존한다.** (서로의 내부 코드를 직접 참조하지 않는다)
3. **런타임 데이터 흐름:** `agent → backend → app` (단방향 파이프라인)
   - agent는 backend를 "이벤트 싱크(sink)"로만 안다. (backend 내부를 모른다)
   - app은 backend를 "데이터 소스"로만 안다. (agent의 존재를 모른다)
4. **backend는 agent/app을 컴파일 타임에 의존하지 않는다.** (네트워크 계약으로만 통신)

> 이 방향성 덕분에 각 런타임은 **독립적으로 배포/테스트/교체** 가능하다.
> 예: F1 게임이 아닌 다른 시뮬레이터(iRacing 등) Agent를 추가해도, 동일 SignalR 계약만 지키면
> backend/app은 변경 없이 동작한다. (개방-폐쇄 원칙 / OCP)

---

## 5. 런타임 데이터 흐름 (MVP End-to-End)

```
[F1 Game PC]
   │ UDP 20777 (Raw Packet)
   ▼
[Agent] ── Parse ─► Lap Analyzer ─► 도메인 이벤트(LapFinished 등)
   │ SignalR (TelemetryHub.SubmitEvent)          │ 오프라인 시
   ▼                                             ▼
[Backend Ingest] ── 검증 ─► 영속화(Lap 저장) ─► 랭킹 재계산   [SQLite 캐시]→복구 시 재전송
   │ SignalR (RankingHub 브로드캐스트)
   ▼
[App] ── Today's TOP10 실시간 갱신 / My Lap Record 조회(REST)
```

상세 흐름과 이벤트 계약은 다음 문서 참조:
- Telemetry 판정/이벤트 → [06-telemetry-design.md](./06-telemetry-design.md)
- SignalR 계약 → [05-signalr-design.md](./05-signalr-design.md)
- 저장 모델 → [03-entity-design.md](./03-entity-design.md)

---

## 6. 핵심 결정 (확정 · [08](./08-open-decisions.md))

- **D-1 ✅** 멀티스토어 `StoreId` 선반영 (SaaS 확장 대비)
- **D-2 ✅** 랩-사용자 귀속 = 앱 체크인 세션 (Agent 무상태·무인증)
- **D-14 ✅** 대상 게임 = F1 25 (`F1_25`), 단 도메인은 게임 중립 설계(가변 섹터 등 타 게임 확장 대비)

> 결정에 따라 **F1 전용이 아닌 게임 확장 가능 구조**로 설계를 정렬했다. 전체 결정 목록/근거는
> [08-open-decisions.md](./08-open-decisions.md) 참조.
