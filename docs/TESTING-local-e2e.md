# 로컬 E2E 테스트 가이드 (집에서 실제 F1로 테스트)

> Last Updated: 2026-07-07 · 대상: Phase 3(Agent → Backend → DB)까지 구현된 상태.
> 목표: **F1 25 주행 → Agent가 랩 감지 → 백엔드 전송 → PostgreSQL `laps` 저장**을 눈으로 확인.
> 앱(Flutter) 화면은 아직 없으므로(P4/P5) **확인은 로그 + DB 조회**로 한다.

전체 그림:
```
F1 25 (UDP 20777) ──► Agent(Cli) ──SignalR──► Backend(:5284) ──► PostgreSQL(laps)
```
같은 PC에서 넷을 다 띄우는 시나리오를 기준으로 한다.

---

## 0. 사전 준비 (최초 1회)

- **.NET 9 SDK**, **PostgreSQL**(실행 중), **F1 25** 설치.
- 시크릿은 리포에 없다 → **이 PC에서 직접 주입**해야 한다(연결 문자열/JWT 키):
  ```bash
  cd backend
  dotnet user-secrets set "ConnectionStrings:Postgres" "Host=localhost;Port=5432;Database=simcenter;Username=postgres;Password=<비번>" --project src/SimCenter.Api
  dotnet user-secrets set "Jwt:Key" "dev-super-secret-key-please-change-32+chars" --project src/SimCenter.Api
  ```
  - DB(`simcenter`)는 미리 안 만들어도 된다 — 백엔드가 시작 시 **마이그레이션으로 생성 + 시드**한다.
  - 시드 결과: 좌석 `A-01~A-04`(각 dev API Key), 트랙 마스터(F1_25).

---

## 1. 백엔드 실행

```bash
cd backend
dotnet run --project src/SimCenter.Api --launch-profile http
```
- `http://localhost:5284` 에서 대기(Development). 시작 시 자동 마이그레이션 + 시드.
- http 프로파일이면 HTTPS 리다이렉트가 없어 인증서 신뢰가 필요 없다(로컬 테스트 편의).
- Swagger: <http://localhost:5284/swagger>

---

## 2. 사용자 만들고 좌석 체크인 (Swagger에서)

> 랩은 **활성 체크인 세션이 있어야** 사용자에게 귀속된다(없으면 서버가 드롭, D-22).

Swagger(<http://localhost:5284/swagger>)에서 순서대로:
1. `POST /api/v1/auth/register` — `{ "email":"me@test.com", "password":"P@ssw0rd!", "displayName":"나" }`
2. `POST /api/v1/auth/login` — 같은 email/password → 응답의 `accessToken` 복사
3. Swagger 우측 상단 **Authorize** → 토큰 붙여넣기
4. `POST /api/v1/sessions/check-in` — `{ "rigCode":"A-01", "gameCode":"F1_25" }` → 201
   - (확인: `GET /api/v1/sessions/active` 가 A-01 세션을 반환)

---

## 3. Agent 설정 & 실행

`agent/src/SimCenter.Agent.Cli/appsettings.json` 의 `Agent` 섹션을 테스트용으로 채운다:
```jsonc
"Agent": {
  "RigCode": "A-01",                                   // 체크인한 좌석과 동일해야 함
  "UdpPort": 20777,
  "GameCode": "F1_25",
  "ExpectedPacketFormat": 2025,
  "BackendUrl": "http://localhost:5284/hubs/telemetry", // ← 비어 있으면 업로드 비활성
  "AgentCredential": "dev-agent-key-A-01",              // A-01의 시드 키
  "OutboxPath": "outbox.db"
}
```
> ⚠️ `RigCode` · `AgentCredential`은 **같은 좌석(A-01)** 이어야 한다. 키가 좌석을 특정하고(D-21), 세션 매칭은 그 좌석의 활성 세션으로 이뤄진다.

실행(콘솔 로그가 보이는 **Cli** 권장):
```bash
cd agent
dotnet run --project src/SimCenter.Agent.Cli
```
- 정상 시 로그: `UDP 텔레메트리 수신 시작 (포트 20777)`, `TelemetryHub 연결됨: http://localhost:5284/hubs/telemetry`
- (Tray 앱으로도 되지만 콘솔이 없어 이벤트 로그가 안 보인다. 연결 상태 신호등만 확인용.)

---

## 4. F1 25 텔레메트리 설정

게임 내 **설정 → 텔레메트리 설정**:
| 항목 | 값 |
|---|---|
| UDP Telemetry | **On** |
| UDP 형식(Format) | **2025** |
| 포트 | **20777** |
| IP 주소 | **127.0.0.1** (같은 PC) |
| Broadcast | Off |
| 전송 속도 | 기본 |

> **랭킹 적격 랩**을 만들려면 **Time Trial** 세션에서 유효한(코스 이탈·컷 없는) 플라잉 랩을 돈다.
> 다른 세션·무효 랩도 저장은 되지만 랭킹에서는 제외된다(개별 조회는 가능, D-15/16).

---

## 5. 주행 & 확인

트랙에서 **한 바퀴 완주**하면(랩 번호가 넘어가는 순간) Agent가 `LapFinished`를 전송한다.

**(a) 백엔드 콘솔 로그**
```
랩 저장 rig=A-01 user=... track=Silverstone lapMs=83452 eligible=True eventId=...
```

**(b) DB 직접 조회** (psql 등)
```sql
SELECT lap_number, lap_time_ms, is_valid, is_ranking_eligible, set_at
FROM laps ORDER BY created_at DESC LIMIT 5;
-- 섹터: SELECT * FROM lap_sectors WHERE lap_id = '<위 lap의 id>';
```

이 행이 보이면 **Agent → 백엔드 → DB** 전 경로가 동작한 것이다.

---

## 6. 자주 막히는 지점

| 증상 | 원인 / 해결 |
|---|---|
| Agent가 `BackendUrl 미설정` 로그 후 조용함 | `BackendUrl`이 비어 있음 → §3처럼 채운다 |
| 백엔드 로그에 `활성 체크인 세션 없음 — 랩 드롭` | 체크인을 안 했거나 `RigCode` 불일치 → §2 체크인 + 좌석 코드 확인 |
| 랩은 저장되는데 `eligible=False` | Time Trial이 아니거나 무효 랩(정상 동작). 랭킹용은 Time Trial 유효 랩 |
| Agent 연결 실패(무한 재시도 로그) | 백엔드가 안 떠 있거나 URL/포트 틀림. http 프로파일인지 확인 |
| 신호등이 계속 🟡/🔴 (Tray) | F1 UDP 설정 누락 or 포트/포맷 불일치 → §4 |
| 백엔드 시작 실패(연결 문자열/JWT) | user-secrets 미주입 → §0 |

---

## 7. 다른 PC/콘솔에서 게임을 돌릴 때 (참고)

- F1 IP 주소 = **백엔드/Agent PC의 LAN IP**, Agent `BackendUrl`도 그 IP로.
- 방화벽에서 **UDP 20777**(게임→Agent) + **TCP 5284**(Agent→백엔드) 인바운드 허용.
- 이 경우 http 평문 대신 HTTPS 권장(`dotnet dev-certs https --trust` 후 https 프로파일/URL 사용).

---

## 8. 현재 범위 메모

- 여기까지가 **Phase 3**(인입·저장). **랭킹 조회·실시간 브로드캐스트·앱 화면은 아직 없음**(P4/P5).
- 네트워크가 끊겨도 이벤트는 Agent의 `outbox.db`(SQLite)에 쌓였다가 재연결 시 자동 재전송된다.
- 상세 설계: [10-realtime-ingest.md](./10-realtime-ingest.md).
