# 07 · Roadmap

> Status: **Design (미승인)** · Last Updated: 2026-07-06
> 헌장 Roadmap을 구체화한다. **설계 → 리뷰 → 구현 → 리뷰 → 다음 단계** 순서를 각 Phase에 적용한다.

---

## 1. 원칙

- 한 번에 모든 기능을 구현하지 않는다. **수직 슬라이스(End-to-End)로 얇게** 완성한다.
- 각 Phase는 **"동작하는 결과물"**을 남긴다. (통합 가능한 상태)
- MVP 완료 = "실 좌석에서 낸 랩이 앱 TOP10에 실시간 표시".

---

## 2. MVP Phase (이번 목표)

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
1. 실 좌석 F1에서 랩 완주 → Agent 이벤트 전송
2. Backend가 로그인 사용자에게 귀속하여 저장
3. 앱 Today's Ranking이 **실시간**으로 갱신
4. 앱 My Lap Record에서 본인 기록 확인
5. Agent 오프라인 후 복구 시 누락 없이 재전송(내구성 검증)

---

## 3. Post-MVP Phase (경계만 정의, 추후)

| Phase | 범위 | 선행 |
|---|---|---|
| Phase 6 | **Reservation** (예약/좌석 스케줄) | MVP |
| Phase 7 | **Competition** (대회/리그/시즌) | Ranking 성숙 |
| Phase 8 | **Community** (피드/게시글) | Identity 확장 |
| Phase 9 | **Membership** (등급/XP/Badge/Achievement) | Analytics 일부 |
| Phase 10 | **Analytics / Admin Dashboard** (매장 운영 통계) | 데이터 축적 |
| Phase 11 | **Lap Telemetry Trace** (상세 텔레메트리 조회 — [09](./09-lap-telemetry-trace.md)) | Trace Plane 도입 |
| 인프라 | Redis 캐시, GitHub Actions CI/CD, Docker Compose 운영화 | 상시 병행 |

> Post-MVP는 **구현하지 않는다.** 컨텍스트 경계([02](./02-domain-design.md))만 미리 확보해 두어
> MVP 구조가 이후 확장을 막지 않도록 한다.

---

## 4. 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| F1 UDP 버전차 | 파싱 실패 | `m_packetFormat` 검증 + 버전별 파서 분리 여지 |
| 랩-사용자 오귀속 | 랭킹 신뢰도 | 체크인 세션 + Rig당 활성 세션 1개 불변식(D-2) |
| 이벤트 유실 | 기록 누락 | Outbox + 멱등키 + Ack |
| "오늘" 경계 혼란 | 랭킹 리셋 오류 | 타임존 기준 명문화(D-8) |

---

## 5. 다음 액션

1. ✅ [08-open-decisions.md](./08-open-decisions.md) 결정 확정 완료 (D-1~D-16)
2. 본 설계 문서 세트 최종 승인
3. 승인 후 **Phase 0(계약 & 스캐폴딩)** 상세 설계로 진입
4. 이후 Phase마다 설계 → 리뷰 → 구현 → 리뷰 반복
