# 01 · Architecture — Solution 구조 · 폴더 구조 · Layer 규칙

> Status: **Design (미승인)** · Last Updated: 2026-07-06

---

## 1. 목적

각 런타임(Backend / Agent / App)의 **내부 구조**와 **레이어 의존 규칙**을 정의한다.
공통 지침: Clean Architecture, 의존성은 항상 **바깥 → 안쪽(도메인)** 방향으로만 흐른다.

---

## 2. Backend — ASP.NET Core 8 (Clean Architecture)

### 2.1 Solution 구조

```
backend/
├── SimCenter.sln
├── src/
│   ├── SimCenter.Domain/            # (1) 가장 안쪽 — 순수 도메인, 무의존
│   ├── SimCenter.Application/       # (2) 유스케이스 / 포트(Interface)
│   ├── SimCenter.Infrastructure/    # (3) EF Core, 외부 구현 (어댑터)
│   └── SimCenter.Api/               # (4) 진입점 — Controller, Hub, DI 조립
└── tests/
    ├── SimCenter.Domain.Tests/
    ├── SimCenter.Application.Tests/
    └── SimCenter.Api.IntegrationTests/
```

### 2.2 레이어별 책임

| Layer | Project | 책임 | 의존 대상 |
|---|---|---|---|
| Domain | `SimCenter.Domain` | Entity, Value Object, 도메인 규칙, 도메인 이벤트 | **없음** (프레임워크 참조 금지) |
| Application | `SimCenter.Application` | 유스케이스(핸들러), Repository/Service **인터페이스(포트)**, DTO | Domain |
| Infrastructure | `SimCenter.Infrastructure` | EF Core DbContext, Repository 구현, JWT, 시간·랜덤 등 어댑터 | Application, Domain |
| Api | `SimCenter.Api` | Controller, SignalR Hub, 미들웨어, DI 등록, 설정 | Application, Infrastructure |

### 2.3 의존성 규칙 (컴파일 강제)

```
Api ──► Infrastructure ──► Application ──► Domain
 │                             ▲
 └─────────────────────────────┘  (Api는 Application도 직접 참조)

Domain 은 그 무엇도 참조하지 않는다. (핵심 불변식)
Application 은 인터페이스만 정의하고 구현은 Infrastructure가 담당한다. (DIP)
```

- Controller/Hub는 **Application의 유스케이스만 호출**한다. EF Core를 직접 만지지 않는다.
- Repository 인터페이스는 `Application`에, 구현은 `Infrastructure`에. (Repository Pattern + DIP)

### 2.4 Api 내부 폴더 (MVP)

```
SimCenter.Api/
├── Program.cs                  # DI 조립, 파이프라인, Hub 매핑
├── Controllers/
│   ├── AuthController.cs
│   ├── RankingController.cs
│   └── LapsController.cs
├── Hubs/
│   ├── TelemetryHub.cs         # Agent → Backend 인입
│   └── RankingHub.cs           # Backend → App 브로드캐스트
├── Middleware/
│   └── ExceptionHandlingMiddleware.cs
├── appsettings.json
└── appsettings.Development.json
```

### 2.5 기능(Feature) 조직 — Application 내부

Application은 기능(Vertical Slice) 단위로 폴더를 나눈다. (도메인 성장에 따라 확장)

```
SimCenter.Application/
├── Common/
│   ├── Interfaces/             # IRepository<T>, ILapRepository, IUnitOfWork, IClock ...
│   ├── Models/                 # Result<T>, PagedResult<T>
│   └── Exceptions/
├── Auth/                       # Login 유스케이스
├── Laps/                       # Lap 저장/조회 유스케이스
├── Ranking/                    # Today TOP10 조회
└── Telemetry/                  # Agent 이벤트 → 유스케이스 매핑
```

---

## 3. Agent — .NET 8 Windows Telemetry Agent

### 3.1 Solution 구조

```
agent/
├── SimCenter.Agent.sln
├── src/
│   ├── SimCenter.Agent.Core/         # UDP 파싱, Lap 분석 (순수 로직, 테스트 대상)
│   ├── SimCenter.Agent.Infrastructure/ # SignalR Client, SQLite 캐시, 파일 설정
│   └── SimCenter.Agent.Tray/         # Windows Tray 앱 (진입점, DI 조립)
└── tests/
    └── SimCenter.Agent.Core.Tests/    # 패킷 파싱/랩 판정 단위 테스트
```

### 3.2 레이어별 책임

| Project | 책임 | 비고 |
|---|---|---|
| `Agent.Core` | Packet Parser, Lap Analyzer, Sector Analyzer, 도메인 이벤트 생성 | **UI·네트워크 무의존** → 100% 단위 테스트 가능 |
| `Agent.Infrastructure` | SignalR Client, SQLite Outbox, 재접속/재전송 정책, 설정 로딩 | 외부 I/O 어댑터 |
| `Agent.Tray` | Tray UI, 자동 실행, 생명주기, DI 조립 | Windows 전용 진입점 |

### 3.3 내부 파이프라인

```
UdpListener ─► PacketParser ─► LapAnalyzer ─► DomainEventFactory
                                                   │
                                     ┌─────────────┴─────────────┐
                                     ▼                           ▼
                              TelemetryClient(SignalR)     OutboxStore(SQLite)
                                     │                           │
                                온라인 전송                 오프라인 큐잉 → 복구 시 flush
```

> **Outbox 패턴:** 모든 도메인 이벤트는 먼저 SQLite Outbox에 기록 후 전송을 시도한다.
> 전송 성공 시 flush. 이 구조로 "자동 재전송 / 오프라인 캐시" 요구사항을 만족하고,
> 이벤트 유실을 방지한다. (상세: [06](./06-telemetry-design.md))

---

## 4. App — Flutter (Feature First)

### 4.1 폴더 구조

```
app/
├── pubspec.yaml
└── lib/
    ├── main.dart
    ├── app/
    │   ├── router/                 # GoRouter 설정
    │   ├── theme/                  # Material 3 테마
    │   └── di/                     # Riverpod ProviderScope 루트
    ├── core/
    │   ├── network/                # Dio/HTTP client, 인터셉터(JWT)
    │   ├── realtime/               # SignalR client 래퍼
    │   ├── error/                  # Failure 모델
    │   └── utils/
    ├── shared/
    │   ├── widgets/                # 공통 위젯
    │   └── models/                 # shared 계약 기반 공통 DTO
    └── features/
        ├── splash/
        ├── auth/                   # Login
        ├── home/
        ├── ranking/                # Today's Ranking
        └── lap_record/             # My Lap Record
```

### 4.2 Feature 내부 레이어 (각 feature 동일 구조)

```
features/ranking/
├── data/
│   ├── datasources/     # remote(REST/SignalR) 호출
│   ├── dtos/            # 서버 계약 매핑 (shared 기반)
│   └── repositories/    # RankingRepositoryImpl
├── domain/
│   ├── entities/        # Ranking, RankEntry (UI 독립 모델)
│   └── repositories/    # RankingRepository (추상)
└── presentation/
    ├── providers/       # Riverpod (StateNotifier/AsyncNotifier)
    ├── screens/
    └── widgets/
```

### 4.3 의존성 규칙 (Flutter)

```
presentation ──► domain ◄── data
   (providers)    (추상)    (구현)

presentation 은 domain 추상에만 의존. data 구현은 DI(Riverpod)로 주입.
```

- Riverpod Provider가 Repository **인터페이스**를 노출, 구현체는 override로 주입 → 테스트 시 mock 교체.
- SignalR 실시간 갱신은 `core/realtime` → feature repository stream으로 전달 → provider가 구독.

---

## 5. 공통 설계 규약 (3 런타임 공통)

| 규약 | 적용 |
|---|---|
| 의존성 역전(DIP) | 상위 정책은 추상에 의존, 구현은 주입 |
| 테스트 경계 | 순수 로직(Domain / Agent.Core / feature.domain)은 프레임워크 무의존 → 단위 테스트 |
| 시간·랜덤 추상화 | `IClock` 등으로 감싸 결정론적 테스트 (Global Static·`DateTime.Now` 직접 사용 금지) |
| 계약 준수 | 모든 외부 통신 payload는 `shared/` 스펙과 일치 |

---

## 6. 미해결/승인 필요 사항

- **D-3. Backend 유스케이스 실행 방식** — 순수 Service 클래스 vs MediatR(CQRS) 도입 여부.
  MVP 규모에서는 **얇은 Service + 인터페이스**를 권장(YAGNI). ([08](./08-open-decisions.md))
- **D-4. App HTTP 클라이언트** — `dio` vs `http`. SignalR Dart 클라이언트 패키지 선택. ([08](./08-open-decisions.md))
