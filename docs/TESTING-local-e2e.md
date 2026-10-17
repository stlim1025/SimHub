# 로컬 E2E 테스트 가이드 (집에서 실제 F1로 테스트)

> Last Updated: 2026-10-17 · 대상: Phase 6(개인 모드)까지 구현된 상태.
> 목표: **F1 25 주행 → Agent가 랩 감지 → 백엔드 전송 → PostgreSQL `laps` 저장 → 웹(Dashboard·Laps·Leaderboard)에 표시**를 눈으로 확인.
> 내 PC의 Agent는 **웹에서 받은 1회용 코드로 내 계정에 연결**한다(체크인 없음, D-25·D-26).

전체 그림:
```
F1 25 (UDP 20777) ──► Agent(Cli/Tray) ──SignalR(장치 키)──► Backend(:5284) ──► PostgreSQL(laps)
                                                              ▲
                                       Flutter 웹(:5960) ─────┘  REST + RankingHub
```
같은 PC에서 다 띄우는 시나리오를 기준으로 한다.

---

## 0. 사전 준비 (최초 1회)

- **.NET 10 SDK**, **PostgreSQL**(실행 중), **Flutter SDK**(웹 앱), **F1 25** 설치.
- 시크릿은 리포에 없다 → **이 PC에서 직접 주입**해야 한다(연결 문자열/JWT 키):
  ```bash
  cd backend
  dotnet user-secrets set "ConnectionStrings:Postgres" "Host=localhost;Port=5432;Database=simcenter;Username=postgres;Password=<비번>" --project src/SimCenter.Api
  dotnet user-secrets set "Jwt:Key" "dev-super-secret-key-please-change-32+chars" --project src/SimCenter.Api
  ```
  - DB(`simcenter`)는 미리 안 만들어도 된다 — 백엔드가 시작 시 **마이그레이션으로 생성 + 시드**한다.
  - 시드 결과: 트랙 마스터(F1_25)뿐이다. 매장·좌석·개발용 좌석 키는 없다(P6에서 제거).
  - ⚠️ P6 이전 DB에서 처음 띄우면 마이그레이션 `PersonalMode`가 **기존 랩·섹터·멱등 기록을 삭제**하고 매장·좌석·세션 테이블을 지운다(회원·트랙은 유지).

---

## 1. 백엔드 실행

```bash
cd backend
dotnet run --project src/SimCenter.Api --launch-profile http
```
- `http://localhost:5284` 에서 대기(Development). 시작 시 자동 마이그레이션 + 시드.
- http 프로파일이면 HTTPS 리다이렉트가 없어 인증서 신뢰가 필요 없다(로컬 테스트 편의).
- Swagger: <http://localhost:5284/swagger>
- 랭킹 기간 경계 타임존은 설정 `Ranking:TimeZoneId`(기본 `Asia/Seoul`). 잘못된 값이면 시작이 실패한다.

---

## 2. 웹 앱 실행 → 가입 → 연결 코드 발급

```bash
cd app
flutter run -d web-server --web-hostname localhost --web-port 5960 --dart-define=API_BASE_URL=http://localhost:5284
```
1. 브라우저에서 <http://localhost:5960> → **회원가입**(이메일·비밀번호·표시명) 후 로그인.
2. 사이드바 **Telemetry App** → **연결 코드 발급** → `XXXX-XXXX` 형태의 코드(10분 유효·1회용, 남은 시간 표시)를 복사한다.
   - 코드를 다시 발급하면 이전 미사용 코드는 무효가 된다.
3. 이 시점의 **Connection Status**는 `연결된 PC가 없습니다`.

> 웹 대신 Swagger로도 가능: `POST /api/v1/auth/register` → `POST /api/v1/auth/login`(응답의 `accessToken` 복사) → 우측 상단 **Authorize** →
> `POST /api/v1/me/agent-pairing-codes` → 응답의 `code`.

---

## 3. Agent 연결(pair) & 실행

`agent/src/SimCenter.Agent.Cli/appsettings.json`의 `Agent` 섹션은 같은 PC라면 기본값 그대로 쓴다:
```jsonc
"Agent": {
  "UdpPort": 20777,
  "GameCode": "F1_25",
  "ExpectedPacketFormat": 2025,
  "ServerBaseUrl": "http://localhost:5284",   // ← 비어 있으면 업로드 비활성
  "OutboxPath": "outbox.db"
}
```
> `RigCode`·`AgentCredential`·`BackendUrl`은 P6에서 없어졌다. 인증 키는 설정 파일이 아니라 **연결 후 로컬에 저장**된다.

**① 연결(최초 1회)** — 위에서 받은 코드로:
```bash
cd agent/src/SimCenter.Agent.Cli
dotnet run -- pair K7F2-9QXM
```
- 성공: `연결되었습니다. 이제 Agent를 실행하면 기록이 이 계정에 업로드됩니다.` (종료 코드 0)
- 장치 키는 `%LOCALAPPDATA%\SimCenter\Agent\device.key`에 **Windows DPAPI로 암호화**되어 저장된다. 컴퓨터 이름이 장치 이름이 된다.
- 웹 Telemetry App의 **연결된 PC** 목록에 이 PC가 나타나고, 상태는 `아직 받은 데이터가 없습니다`.

**② 실행**(콘솔 로그가 보이는 **Cli** 권장):
```bash
dotnet run
```
> ⚠️ **반드시 Cli 프로젝트 폴더에서 실행**한다. `Host.CreateApplicationBuilder`는 현재 폴더를 content root로 삼아 `appsettings.json`을 읽으므로,
> `agent/`에서 `dotnet run --project src/SimCenter.Agent.Cli`로 띄우면 설정이 비어 `ServerBaseUrl 미설정` 상태가 된다.
- 정상 시 로그: `UDP 텔레메트리 수신 시작 (포트 20777)`, `TelemetryHub 연결됨: http://localhost:5284/hubs/telemetry`
- 키가 없으면 `계정 미연결 — pair <코드>로 연결하세요` 경고가 뜨고 업로드만 멈춘다(UDP 수신·Outbox 적재는 계속, 연결하면 10초 안에 자동 시작).

**Tray로 연결하려면**(콘솔은 없고 연결 상태 신호등만 보인다): Tray 창의 **계정 연결** 영역에 코드를 입력하고 **[연결]**.
상태는 `미연결` / `연결됨 · {PC 이름}` / `다시 연결 필요`. **[이 PC 연결 끊기]**는 로컬 키만 지운다(서버 쪽 해제는 웹에서).

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
랩 저장 device=... user=... track=Silverstone lapMs=83452 eligible=True eventId=...
```

**(b) 웹**(새로고침 없이 갱신되는 것은 Leaderboard뿐)
- **Dashboard**: 최근 랩 5개, 연결 상태 `데이터 수신 중`.
- **Laps** → 트랙 선택: Recent/Fastest 전환, 랩타임·S1~S3·세션 유형·날짜.
- **Leaderboard**: 트랙 선택 후 월별 TOP10(Time Trial 유효 랩일 때). RankingHub로 실시간 반영.
- **Telemetry App**: 연결된 PC의 마지막 수신 시각 갱신.

**(c) DB 직접 조회** (psql 등)
```sql
SELECT l.lap_number, l.lap_time_ms, l.is_valid, l.is_ranking_eligible, l.set_at, d.name AS device
FROM laps l JOIN agent_devices d ON d.id = l.agent_device_id
ORDER BY l.created_at DESC LIMIT 5;
-- 섹터: SELECT * FROM lap_sectors WHERE lap_id = '<위 lap의 id>';
```

이 행이 보이면 **Agent → 백엔드 → DB → 웹** 전 경로가 동작한 것이다.

**(d) 연결 해제 확인**: 웹 Telemetry App → 연결된 PC의 **[연결 해제]**.
- Agent가 연결된 채라면 다음 이벤트 때 서버가 Reject("연결이 해제된 장치입니다.")한다. Agent는 `서버가 연결 해제된 장치로 Reject했습니다 … Outbox에 보관합니다`,
  `TelemetryHub가 장치 키를 거부했습니다(연결 해제 Reject) — 다시 연결이 필요합니다`를 남기고 업로드를 멈춘다(Tray `다시 연결 필요`). 그 이벤트는 Outbox에 남는다.
- Agent를 다시 시작하는 등 새로 연결하면 `TelemetryHub가 장치 키를 거부했습니다(401) — 다시 연결이 필요합니다` 후 같은 상태로 멈춘다.
- 새 코드로 `pair`하면 복구되고, 남아 있던 이벤트부터 올라간다.

---

## 6. 자주 막히는 지점

| 증상 | 원인 / 해결 |
|---|---|
| Agent가 `ServerBaseUrl 미설정` 로그 후 조용함 | `ServerBaseUrl`이 비어 있음 → §3처럼 채운다. 채웠는데도 뜨면 실행 위치가 `agent/src/SimCenter.Agent.Cli`가 아님(로그의 `Content root path` 확인) → §3 |
| Agent 로그에 `계정 미연결` 경고, 랩이 DB에 안 쌓임 | 아직 `pair`를 안 함 → §2에서 코드를 받아 §3 `pair`. 연결 전에 쌓인 이벤트는 연결 후 업로드되어 그 계정에 귀속된다 |
| `pair`가 `유효하지 않거나 만료된 코드입니다.` (400) | 코드가 틀림·10분 경과·이미 사용됨·새 코드 발급으로 무효화됨(서버는 사유를 구분해 알려주지 않는다) → 웹에서 새 코드를 발급 |
| `pair`가 429 | `POST /agent/pair`는 IP당 분당 10회 제한 → 1분 뒤 다시 시도. 코드 발급도 사용자당 분당 10회 |
| Agent가 `다시 연결 필요`로 멈춤(로그에 `401` 또는 `연결 해제 Reject`) | 웹에서 이 PC를 연결 해제했거나 서버 DB를 새로 만들어 키가 무효 → 웹에서 새 코드를 받아 `pair`. 연결된 채 해제돼 Reject된 이벤트를 포함해 Outbox에 쌓인 이벤트는 보존되어 재연결 후 올라간다 |
| 웹 Telemetry App에 PC가 안 보임 | `pair` 성공 후 목록 새로고침. 다른 계정으로 로그인했는지 확인(장치는 코드를 발급한 계정에 연결된다) |
| 랩은 저장되는데 `eligible=False` | Time Trial이 아니거나 무효 랩(정상 동작). 랭킹용은 Time Trial 유효 랩 |
| Agent 연결 실패(무한 재시도 로그) | 백엔드가 안 떠 있거나 URL/포트 틀림. http 프로파일인지 확인 |
| 신호등이 계속 🟡/🔴 (Tray) | F1 UDP 설정 누락 or 포트/포맷 불일치 → §4 |
| 백엔드 시작 실패(연결 문자열/JWT) | user-secrets 미주입 → §0 |
| 백엔드 시작 실패(`Ranking:TimeZoneId`) | 잘못된 IANA 타임존 이름 → `Asia/Seoul` 등으로 수정 |
| 웹이 서버에 못 붙음(CORS/연결 실패) | 실행 시 `--dart-define=API_BASE_URL=http://localhost:5284` 누락, 또는 백엔드가 Development가 아님(개발 CORS는 루프백 오리진만 허용) |
| `dotnet test`/`dotnet run`이 `You must install or update .NET`로 실패 | 사용자 환경 변수 `DOTNET_ROOT`가 .NET 10 런타임이 없는 폴더(예: `%USERPROFILE%\.dotnet`)를 가리킴 → `C:\Program Files\dotnet`으로 바꾸고 터미널 재시작 |
| `flutter test`가 진행 없이 멈춤(`-v` 로그에 `Could not prepare isolate`) | Windows 사용자 이름에 한글 등 비ASCII 문자가 있어 임시 폴더 경로를 못 읽음 → 사용자 `TEMP`/`TMP`를 영문 경로(예: `C:\Temp`)로 바꾸고 터미널 재시작 |

---

## 7. 다른 PC/콘솔에서 게임을 돌릴 때 (참고)

- F1 IP 주소 = **Agent PC의 LAN IP**(게임이 콘솔이면 그 IP로 UDP 송신), Agent `ServerBaseUrl`은 **백엔드 PC의 LAN IP**(예: `http://192.168.0.10:5284`).
- 방화벽에서 **UDP 20777**(게임→Agent) + **TCP 5284**(Agent→백엔드) 인바운드 허용.
- 다른 PC의 Agent도 같은 계정에 연결할 수 있다(웹에서 코드를 새로 발급해 그 PC에서 `pair`). 장치는 웹에서 개별로 해제한다.
- 이 경우 http 평문 대신 HTTPS 권장(`dotnet dev-certs https --trust` 후 https 프로파일/URL 사용).

---

## 8. 현재 범위 메모

- 여기까지가 **Phase 6**(개인 모드 전환 + 웹 셸). 인입·저장·랭킹·실시간 브로드캐스트·웹 4화면(Dashboard·Laps·Leaderboard·Telemetry App)이 동작한다.
  Seasons·Sessions·랩 상세는 P7 이후.
- 네트워크가 끊겨도 이벤트는 Agent의 `outbox.db`(SQLite)에 쌓였다가 재연결 시 자동 재전송된다.
- 상세 설계: [10-realtime-ingest.md](./10-realtime-ingest.md), [11-personal-mode.md](./11-personal-mode.md).
