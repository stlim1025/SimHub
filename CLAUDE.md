# CLAUDE.md — SimCenter Project Constitution

> Last Updated: 2026-07-06 · 상세 설계는 `docs/00~09` 참조. 헌장과 설계가 충돌하면 헌장이 우선.

## Overview
SimCenter는 레이싱 시뮬레이터 카페를 위한 통합 운영 플랫폼이다. 예약 앱이 아니라
실시간 텔레메트리·랩타임·랭킹·회원·예약·대회·커뮤니티까지 아우르는 장기 확장형 플랫폼을 지향한다.

**Core Philosophy:** 목표는 "좋은 코드"가 아니라 "손님이 다시 오고 싶은 경험"이다.
앱은 예약 시스템이 아니라 게임의 연장선이다. 모든 기능은 "재방문을 유도하는가?"로 판단한다.
기능 추가보다 **일관성·유지보수성·확장성**을 항상 우선한다.

## MVP Scope
UDP Telemetry 수신 → 랩 종료 감지 → 랩 저장 → 랭킹(TOP10) → 내 기록 조회. 여기까지가 MVP.
**제외:** 예약·커뮤니티·대회·멤버십·결제·알림·상세 텔레메트리(전부 Future).

## Repository (Monorepo)
| 폴더 | 역할 | 스택 |
|---|---|---|
| `docs/` | 설계 문서 | Markdown |
| `shared/` | 계약(OpenAPI·JSON Schema·Telemetry Spec) — 코드 아닌 Contract | — |
| `agent/` | Windows Telemetry Agent (UDP 파싱·Lap 분석·SignalR·SQLite 캐시·Tray) | .NET 8 / C# |
| `backend/` | REST·SignalR·Auth·Ranking·Telemetry (Clean Architecture) | ASP.NET Core 8 / EF Core / PostgreSQL |
| `app/` | 모바일/웹 앱 (Feature First) | Flutter / Riverpod / GoRouter / Material3 |

**Dependency 방향:** `agent → backend → app` (단방향). 모두 `shared`만 의존, `shared`는 무의존.
런타임끼리는 네트워크 계약으로만 통신(컴파일 의존 금지).

## Architecture Principles
- SOLID · DRY · KISS · YAGNI · Clean Architecture · DIP · Async/Await · Nullable Reference Types
- 의존성은 항상 바깥 → 도메인 방향. Domain은 프레임워크 무의존.
- 순수 로직(Domain / Agent.Core / feature.domain)은 단위 테스트 가능해야 한다.
- 시간·랜덤은 추상화(`IClock` 등). Global Static·`DateTime.Now` 직접 사용 금지.

## Backend Rules
Clean Architecture(Domain/Application/Infrastructure/Api) + Repository Pattern.
EF Core Code First + Migration. JWT 인증. 실시간은 SignalR, 조회는 REST.
모든 시각 UTC 저장. 공통 필드(CreatedAt/UpdatedAt/IsDeleted) + Soft Delete. PK = `Guid(UUID v7)`.

## Agent Rules
모든 UDP 패킷을 보내지 않는다. **의미 있는 도메인 이벤트만** 전송
(SessionStarted/LapStarted/SectorCompleted/LapFinished/SessionEnded).
Raw 패킷 firehose는 서버로 흘리거나 원본 저장하지 않는다.
오프라인 시 SQLite Outbox 저장 → 복구 시 자동 재전송(멱등키 + Ack). 자동 실행/재접속.

## Flutter Rules
Feature First + Riverpod + GoRouter + Material3, 반응형 필수.
MVP 화면: Splash · Login · Home · Today's Ranking · My Lap Record.

## API / SignalR Rules
RESTful JSON, 필드 camelCase, JWT, Swagger/OpenAPI 유지.
SignalR 2-Hub: `TelemetryHub`(Agent→Backend 인입) / `RankingHub`(Backend→App 브로드캐스트).

## Coding Convention
PascalCase(타입) / camelCase(멤버) / Interface는 `I` 접두사.
Magic Number·Global Static 금지. Null 체크·Exception 처리·Logging(Serilog) 필수. Secrets 하드코딩 금지.

## Confirmed Decisions (상세: `docs/08`)
- 멀티스토어 `StoreId` 선반영 · 랩 귀속 = 앱 체크인 세션(Agent 무상태)
- 대상 게임 = **F1 25**(`F1_25`), 단 도메인은 게임 중립(가변 섹터·SessionType)
- 섹터 = 가변 `LapSector` 테이블 · 무효 랩 저장하되 랭킹 제외(개별 조회 가능)
- 랭킹 = Time Trial만, 일/월/연 지원. **실시간 랭킹 기본 기준 = 월별**

## Roadmap (상세: `docs/07`)
P0 계약·스캐폴딩 → P1 Backend 코어/인증 → P2 Agent Core → P3 실시간 인입 →
P4 랭킹·브로드캐스트 → P5 Flutter MVP. 이후(Future): 예약·대회·커뮤니티·멤버십·통계·상세 텔레메트리.

## AI Working Rules
- 한 번에 다 구현하지 않는다. **설계 → 리뷰 → 구현 → 리뷰 → 다음 단계** 순서를 지킨다.
- 임의로 구조·라이브러리·아키텍처를 바꾸지 않는다. 변경이 필요하면 **이유를 먼저 설명**한다.
- 추측하지 않는다. 불확실하면 **질문**한다. 기존 설계 문서(`docs/`)를 존중하며 진행한다.
