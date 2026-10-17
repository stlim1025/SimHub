# 07 · Roadmap

> Status: **Design (미승인)** · Last Updated: 2026-10-18 (P7 완료 반영, 앞서 P6 개인 모드 반영)
> 헌장 Roadmap을 구체화한다. **설계 → 리뷰 → 구현 → 리뷰 → 다음 단계** 순서를 각 Phase에 적용한다.
> P0~P5(MVP)는 카페 모델(매장·좌석·체크인)로 구현·완료되었고, **P6에서 개인 모드로 전환**했다(D-25). P6 이후는 §3 및 [11](./11-personal-mode.md) §0.

---

## 1. 원칙

- 한 번에 모든 기능을 구현하지 않는다. **수직 슬라이스(End-to-End)로 얇게** 완성한다.
- 각 Phase는 **"동작하는 결과물"**을 남긴다. (통합 가능한 상태)
- MVP 완료 = "게임에서 낸 랩이 앱 TOP10에 실시간 표시". (P6 이후: 내 PC의 Agent로 낸 랩)

---

## 2. MVP Phase (완료 · P0~P5)

> 아래 Phase 1·3·5의 시드(Store/SimRig)·체크인·DrivingSession 바인딩은 당시 설계이며 **P6에서 제거**됐다
> (좌석 → `AgentDevice`, 체크인 → 연결 코드. 마이그레이션 `AddAgentDevices`·`PersonalMode`).

### Phase 0 — 계약 & 스캐폴딩 (Foundation)
- `shared/` 계약 초안 확정: OpenAPI, SignalR JSON Schema, Telemetry Envelope.
- 3개 솔루션 뼈대 생성(빈 레이어 + DI 조립 + 빌드 통과).
- **산출물:** 계약 문서 + 컴파일되는 빈 프로젝트 3종.
- **선행 조건:** [08-open-decisions.md](./08-open-decisions.md) 결정 **전부 확정 완료 ✅** (D-1~D-16).

### Phase 1 — Backend 데이터/인증 코어
- Entity + EF Migration + Seed(Store/SimRig/Track).
- Auth(register/login/JWT), `/me`.
- **산출물:** DB 생성, 로그인 API 동작, Swagger 노출.

### Phase 2 — Telemetry Agent (Core)
- `Agent.Core`: UDP 수신 + 패킷 파싱 + LapAnalyzer + 단위 테스트.
- 고정 샘플 패킷으로 LapFinished 판정 검증.
- **산출물:** 샘플 입력 → 올바른 도메인 이벤트 생성(테스트 통과). (아직 서버 전송 없음)

### Phase 3 — 실시간 인입 파이프라인 (Agent ↔ Backend)
- `TelemetryHub` 인입 + 멱등 처리 + 세션 매칭 + Lap 저장.
- Agent Outbox(SQLite) + SignalR Client + 자동 재접속/재전송.
- 체크인/체크아웃 API로 DrivingSession 바인딩.
- **산출물:** Agent가 낸 랩이 DB `Lap`으로 귀속되어 저장됨.

### Phase 4 — 랭킹 & 브로드캐스트
- 기간별 TOP10 쿼리(REST, **Time Trial·랭킹적격만**) + `RankingHub` 브로드캐스트 + 개인기록/PB 이벤트.
- **실시간 랭킹 기본 기준 = 월별(D-8a).** 일/연 랭킹은 동일 쿼리 형태로 확장(D-8).
- **산출물:** 새 랩 저장 시 랭킹 재계산 + 실시간 이벤트 발행.

### Phase 5 — Flutter MVP 앱
- Splash → Login → Home → Today's Ranking(실시간) → My Lap Record.
- Riverpod + GoRouter + SignalR 구독 + REST 조회.
- **산출물:** 앱에서 로그인·체크인·실시간 TOP10·내 기록 확인.

### ✅ MVP 완료 정의 (Definition of Done)
1. 게임(F1)에서 랩 완주 → Agent 이벤트 전송
2. Backend가 로그인 사용자에게 귀속하여 저장 (P6 이후: 연결된 장치의 주인)
3. 앱 Leaderboard(구 Today's Ranking)가 **실시간**으로 갱신
4. 앱 Laps(구 My Lap Record)에서 본인 기록 확인
5. Agent 오프라인 후 복구 시 누락 없이 재전송(내구성 검증)

---

## 3. P6 이후 Phase (개인 모드 · [11](./11-personal-mode.md) §0)

| Phase | 범위 | 상태 |
|---|---|---|
| **P6** | 개인 모드 전환(`AgentDevice`·연결 코드·장치 키) + 사이드바 웹 셸(Dashboard · Laps · Leaderboard · Telemetry App) | ✅ 완료 (2026-10-17) |
| P7 | **시즌·세션 수집** — `SeasonLinkIdentifier`/`WeekendLinkIdentifier`/`SessionLinkIdentifier`로 시즌 → 그랑프리 → 세션을 묶고, `FinalClassification`·`Participants`로 전 드라이버 결과·Standings 저장 ([12](./12-seasons-sessions.md)) | ✅ 완료 (2026-10-18) — 게임 확인(12 §3.3 가정)은 미완 |
| P8 | 세션 상세 — 랩별 랩타임, 타이어 스틴트별 마모·랩타임, 패널티 | ⬜ **다음** |
| P9 | 랩 상세 + 텔레메트리 트레이스([09](./09-lap-telemetry-trace.md)), 섹터 비교 | ⬜ |
| P10 | Analytics (트랙별 AI 난이도 등) | ⬜ |
| P11 | Agent 배포 — 설치 파일, 자동 업데이트, 다운로드 링크 | ⬜ |
| Future | Competition(대회/리그) · Community · Membership | 경계만 정의([02](./02-domain-design.md)) |
| 인프라 | Redis 캐시, GitHub Actions CI/CD, Docker Compose 운영화 | 상시 병행 |

> 각 단계는 따로 **설계 → 계획 → 구현 → 리뷰**를 거친다. Reservation(예약/좌석)·매장 운영 통계는 개인 모드(D-25)에서 로드맵을 폐기했다.
> Future는 **구현하지 않는다.** 컨텍스트 경계([02](./02-domain-design.md))만 확보해 두어 이후 확장을 막지 않도록 한다.

---

## 4. 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| F1 UDP 버전차 | 파싱 실패 | `m_packetFormat` 검증 + 버전별 파서 분리 여지 |
| 랩-사용자 오귀속 | 랭킹 신뢰도 | 랩은 인증된 장치 키 → 장치 주인에게만 귀속(D-25·D-26). 장치를 웹에서 해제하면 새 연결 401, 열린 연결의 이벤트는 Reject |
| 장치 키 유출 | 남이 내 계정에 랩 업로드 | 키는 DPAPI로 암호화 저장, 서버엔 해시만 보관. 웹에서 장치 단위로 즉시 해제 |
| 연결 코드 추측 | 남의 계정에 장치 연결 | 코드 8자(약 40비트)·10분·1회용, `POST /agent/pair`는 IP당 분당 10회 제한, 실패 사유 단일화 |
| 이벤트 유실 | 기록 누락 | Outbox + 멱등키 + Ack |
| "오늘" 경계 혼란 | 랭킹 리셋 오류 | 타임존 기준 명문화(D-8), 서버 설정 `Ranking:TimeZoneId`(D-27, 시작 시 검증) |

---

## 5. 다음 액션

1. ✅ P0~P5 MVP 완료, ✅ P6 개인 모드 완료, ✅ P7 시즌·세션 수집 완료 ([PROGRESS.md](./PROGRESS.md))
2. 다음 = **P8 세션 상세**: 설계 → 리뷰 → 계획 → 구현 → 리뷰 순서로 착수
3. 이후 Phase마다 설계 → 리뷰 → 구현 → 리뷰 반복
