# 로컬 E2E 테스트 가이드 (집에서 실제 F1로 테스트)

> Last Updated: 2026-10-18 · 대상: Phase 7(시즌·세션)까지 구현된 상태. 시즌·세션을 게임으로 확인하는 절차는 **§10**.
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
  - 백엔드 통합 테스트(`dotnet test`)는 같은 연결 정보로 **별도 DB `simcenter_test`**를 쓴다(개발 DB에 테스트 데이터가 쌓이지 않음) → §9.

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
| `dotnet test`가 빌드 중 `MSB3027`(파일이 `SimCenter.Api`에 의해 잠겨 있음)로 실패 | 백엔드(`dotnet run`)가 떠 있어 `src/SimCenter.Api/bin`이 잠김 → 백엔드를 끄거나 `dotnet test backend/SimCenter.sln --artifacts-path <임시 폴더>`로 빌드 출력을 분리 |
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

- §1~§7은 **Phase 6**(개인 모드 전환 + 웹 셸) 범위다. 인입·저장·랭킹·실시간 브로드캐스트·웹 4화면(Dashboard·Laps·Leaderboard·Telemetry App)이 동작한다.
  **Phase 7**에서 Seasons·Sessions 화면과 `SessionClassified` 인입이 더해졌다(§10). 랩 상세는 P9 이후.
- 네트워크가 끊겨도 이벤트는 Agent의 `outbox.db`(SQLite)에 쌓였다가 재연결 시 자동 재전송된다.
- 상세 설계: [10-realtime-ingest.md](./10-realtime-ingest.md), [11-personal-mode.md](./11-personal-mode.md), [12-seasons-sessions.md](./12-seasons-sessions.md).

---

## 9. 통합 테스트 DB와 개발 DB의 테스트 데이터 정리

**통합 테스트 DB 분리**
- `dotnet test backend/SimCenter.sln`의 통합 테스트(`SimCenter.Api.IntegrationTests`)는 user-secrets의 `ConnectionStrings:Postgres`에서
  **Database만 `simcenter_test`로 바꿔** 쓴다(호스트·계정·비밀번호 재사용, 추가 설정 없음). DB가 없으면 테스트가 만든다.
- 실행 시작 시 한 번 테스트 DB를 마이그레이션·시드하고 **이전 실행 데이터를 비운다**(트랙 시드·마이그레이션 이력은 유지).
  반복 실행해도 쌓이지 않고, 마지막 실행의 데이터는 디버깅용으로 남는다.
- 비우기는 연결된 DB 이름이 `simcenter_test`일 때만 한다(아니면 아무것도 지우지 않고 실패). 여러 터미널에서 동시에 돌리면 뒤 실행이 앞 실행이 끝날 때까지 기다린다.

**개발 DB(`simcenter`)에 남은 테스트 데이터 정리**
분리 전에 돌린 테스트가 개발 DB에 `e2e-…@simcenter.test` 계정(Leaderboard의 `E2E 드라이버`)과 장치·연결 코드·랩·섹터를 남겼다.
수동 점검용 `p6check-…` 계정도 같이 지운다. **되돌릴 수 없으니** 필요하면 먼저 `pg_dump`로 백업하고, psql에서 `simcenter`에 접속해 직접 실행한다.
```sql
BEGIN;

CREATE TEMP TABLE cleanup_users ON COMMIT DROP AS
  SELECT id FROM users WHERE email LIKE 'e2e-%' OR email LIKE 'p6check-%';
CREATE TEMP TABLE cleanup_laps ON COMMIT DROP AS
  SELECT id FROM laps
  WHERE user_id IN (SELECT id FROM cleanup_users)
     OR agent_device_id IN (SELECT id FROM agent_devices WHERE user_id IN (SELECT id FROM cleanup_users));

-- P7 시즌·세션 테이블이 있는 DB(마이그레이션 AddSeasonsAndSessions 적용 후)에서는 이 임시 테이블도 만든다.
CREATE TEMP TABLE cleanup_sessions ON COMMIT DROP AS
  SELECT id FROM game_sessions WHERE user_id IN (SELECT id FROM cleanup_users);

-- 대상 수 확인
SELECT (SELECT count(*) FROM cleanup_users) AS users, (SELECT count(*) FROM cleanup_laps) AS laps,
       (SELECT count(*) FROM cleanup_sessions) AS game_sessions;

-- FK 순서: 시즌·세션 계열(스틴트 → 결과 → 세션 → 주말 → 시즌) → 섹터 → 랩 → 장치·연결 코드 → 사용자
DELETE FROM session_result_tyre_stints WHERE session_result_id IN
  (SELECT id FROM session_results WHERE game_session_id IN (SELECT id FROM cleanup_sessions));
DELETE FROM session_results     WHERE game_session_id IN (SELECT id FROM cleanup_sessions);
DELETE FROM game_sessions       WHERE id      IN (SELECT id FROM cleanup_sessions);
DELETE FROM race_weekends       WHERE season_id IN (SELECT id FROM seasons WHERE user_id IN (SELECT id FROM cleanup_users));
DELETE FROM seasons             WHERE user_id IN (SELECT id FROM cleanup_users);
DELETE FROM lap_sectors         WHERE lap_id  IN (SELECT id FROM cleanup_laps);
DELETE FROM laps                WHERE id      IN (SELECT id FROM cleanup_laps);
DELETE FROM agent_devices       WHERE user_id IN (SELECT id FROM cleanup_users);
DELETE FROM agent_pairing_codes WHERE user_id IN (SELECT id FROM cleanup_users);
DELETE FROM users               WHERE id      IN (SELECT id FROM cleanup_users);

-- 위 숫자가 예상과 같으면 COMMIT; 아니면 ROLLBACK; 을 직접 입력한다.
```
- 멱등 기록(`processed_events`)은 이벤트 ID만 있고 사용자와 연결되지 않아 남겨도 화면에 영향이 없다.
- 위 SQL은 P7 스키마(`AddSeasonsAndSessions` 적용 후) 기준이다. 아직 적용 전인 DB라면 `cleanup_sessions`와 시즌·세션 `DELETE` 줄을 빼고 실행한다. 직접 실행해 보지는 않았으니 `ROLLBACK`으로 먼저 시험한다.
  이후 사용자·랩을 참조하는 테이블이 생기면 그 테이블을 먼저 지우도록 추가한다.

---

## 10. 게임으로 확인: 시즌·세션 (P7)

> 목표: **F1 25 커리어 주말(연습·예선·레이스)을 결과 화면까지 진행 → Agent가 세션마다 `SessionClassified` 1건 전송 → 서버가 시즌·주말·세션·전 드라이버 결과 저장 → 웹 Seasons·Sessions에 표시**를 눈으로 확인하고,
> [12](./12-seasons-sessions.md) §3.3의 가정 8개가 맞는지 확인한다. P7은 이 단계(게임 확인)를 아직 거치지 않았다.

**사전 조건**
- §0~§4 완료(백엔드·웹 실행, Agent `pair` 완료, F1 25 UDP 설정). 백엔드는 **이 브랜치(P7) 빌드**여야 한다 — 시작할 때 마이그레이션 `AddSeasonsAndSessions`가 적용된다.
  **배포 순서는 백엔드 → Agent**다. 옛 백엔드는 모르는 `SessionClassified`를 Ack하고 버려서 그 세션을 잃는다.
- **Agent는 세션을 시작하기 전에 켜 둔다.** 순위표는 같은 세션의 Session 패킷(모드·링크·트랙)과 Participants(이름·팀)와 합쳐 보내므로, 세션 도중에 Agent를 켜면 그 세션은 보내지 않는다(데이터 1건 손실).
- 시즌에 묶이는 모드는 커리어 4종(Driver Career · My Team · Online Career · Challenge Career)과 Grand Prix다. 온라인 로비·스토리 등은 시즌 없이 Sessions에만 나온다. **Time Trial은 저장하지 않는다**(Laps·Leaderboard 담당).

**절차**
1. 게임에서 Driver Career(또는 My Team)로 **새 시즌**을 시작한다. 첫 주말에서 세션을 **중간에 나가지 말고 결과 화면까지** 진행한다.
   연습 1개 → 예선 → 레이스 순서(스프린트 주말이면 스프린트 예선·스프린트도). 세션이 끝나면 게임이 Final Classification 패킷을 보낸다(결과 화면 어느 시점에 오는지도 확인 대상).
2. **서버 콘솔 로그**에서 세션마다 한 줄씩 확인한다.
   ```
   세션 결과 저장 device=... user=... sessionKey=link:2847561234:99112233:44556677 track=Bahrain results=22 stored=신규
   ```
   `results`는 순위표에 오른 차 수(예: 22), 같은 세션을 다시 보내면 `stored=병합`이다. **Agent 콘솔에는 정상 전송 로그가 없다** — 경고·오류(`서버 Reject …`, 한도 초과 등)만 찍힌다.
3. **웹**에서 확인한다(새로고침이 필요하다. Seasons·Sessions는 실시간 갱신이 없다).
   - **Sessions:** 방금 끝낸 세션이 목록에 나온다. All · Race · Qualifying · Practice 칩이 동작하고, 행을 누르면 세션 결과 화면이 열린다.
     결과 화면: 전 드라이버(AI 배지 포함), 내 행 강조, 팀 색 막대, 그리드·랩 수·시간/gap·베스트 랩(최고 랩 색)·타이어 컴파운드·피트·패널티·점수. 이름이 깨져 보이면 안 된다.
   - **Seasons:** 새 시즌 카드(`{모드} · {시작 날짜}`, `{N} rounds`, 내 순위·점수, 선두). 카드를 열어 **Season**(라운드별 세션 칩·우승자) · **Results**(드라이버 × 라운드 표, 이름 열 고정) · **Standings**(Drivers·Constructors, "기록된 세션 기준" 안내)를 본다.
4. (선택) **DB 직접 조회**
   ```sql
   -- 저장된 세션: 링크 값과 세션 키, 결과 행 수
   SELECT gs.classified_at, t.name AS track, gs.game_mode, gs.session_type, gs.session_kind,
          gs.season_link_id, gs.weekend_link_id, gs.session_link_id, gs.session_key,
          (SELECT count(*) FROM session_results r WHERE r.game_session_id = gs.id AND r.is_deleted = false) AS cars
   FROM game_sessions gs JOIN tracks t ON t.id = gs.track_id
   WHERE gs.is_deleted = false
   ORDER BY gs.classified_at DESC LIMIT 20;

   -- 시즌과 기록된 주말 수
   SELECT s.season_link_id, s.game_mode, s.first_session_at, s.last_session_at,
          (SELECT count(*) FROM race_weekends w WHERE w.season_id = s.id AND w.is_deleted = false) AS weekends
   FROM seasons s WHERE s.is_deleted = false ORDER BY s.last_session_at DESC;
   ```
5. 아래 **가정 체크리스트**를 확인하고, 결과를 [12](./12-seasons-sessions.md) §3.3 "확인 결과" 열에 날짜와 함께 적는다.

**가정 체크리스트** ([12](./12-seasons-sessions.md) §3.3)

| # | 가정 | 확인 방법 | 틀렸을 때 보이는 증상 |
|---|---|---|---|
| 1 | Final Classification이 **연습·예선** 세션 끝에도 온다 | 연습·예선을 결과 화면까지 마치고 Sessions의 Practice·Qualifying 칩에 나오는지, 위 SQL의 `session_kind`에 `Practice1`/`Qualifying1` 등이 있는지 | 레이스만 저장되고 연습·예선은 목록·라운드 칩에 없다(오류는 없다) |
| 2 | 같은 `SessionUID`로 Final Classification이 **여러 번** 올 수 있다 | Agent는 `SessionRef`당 1회만 보내고 중복은 조용히 무시하므로 직접 보이지 않는다. 한 세션이 목록에 **한 행**인지 확인한다. 패킷 수를 직접 보려면 UDP 캡처(포트 20777, packetId 8)가 필요하다 | (Agent가 막으므로 증상 없음 — 이 가정은 확인해도 동작이 바뀌지 않는다) |
| 3 | 세션 **재시작·세이브 재개** 시 `SessionLinkIdentifier`가 유지된다 | 레이스를 한 번 재시작하거나 세이브 후 재개해 다시 끝까지 마치고, 위 SQL에서 같은 주말·같은 `session_kind`의 `session_link_id`를 비교한다. 같으면 서버 로그가 `stored=병합` | 값이 다르면 같은 세션이 Sessions에 두 행으로 남는다(데이터 손실은 없고, 시즌 점수는 같은 주말·종류의 최신 1건만 쓴다) |
| 4 | 커리어의 **다음 해(시즌)** 는 `SeasonLinkIdentifier`가 바뀐다 | 시즌을 마치고 다음 시즌의 첫 세션을 끝낸 뒤 `seasons.season_link_id`가 새 행으로 생기는지 | 바뀌지 않으면 여러 해가 한 시즌으로 합쳐진다(확인 후 "같은 트랙 주말이 다시 나오면 새 시즌" 규칙을 추가) |
| 5 | **Grand Prix** 모드의 링크 값이 주말·챔피언십 단위로 의미가 있다 | Grand Prix 모드에서 두 주말을 진행하고 `season_link_id`·`weekend_link_id`가 주말마다 어떻게 변하는지 | 의미가 없으면 한 챔피언십이 여러 시즌으로 쪼개지거나 섞인다 → Grand Prix를 시즌 대상 모드에서 뺀다(`SeasonPolicy` 한 줄) |
| 6 | F1 25의 Grand Prix 모드 값이 라이브러리의 `GrandPrix23`(**4**)이다 | Grand Prix 세션의 `game_mode`가 `GrandPrix`로 저장되는지(Sessions "모드" 열) | `Other`로 저장되면 모르는 값이다 — 원시 값(Session 패킷의 `m_gameMode`)을 알려 매퍼에 추가한다. (원시 값 3도 Grand Prix로 처리하므로 3이면 이미 맞다) |
| 7 | 스프린트 주말에서 스프린트가 `Race`, 본 레이스가 `Race2`다 | 스프린트 주말을 진행하고 `session_kind` 값을 본다 | 세션 이름 표시(`R`/`R2`)만 다르다. 본 레이스 판정은 시각 기준이라 영향이 없다 |
| 8 | **Participants** 레이아웃이 사용자의 게임 버전(2026 시즌팩)과 맞다 | 세션 결과 화면의 드라이버 이름·팀이 실제와 같은지 | 이름이 깨지거나 팀 색이 어긋난다 → D-20의 버전 결정 문제(F1Game.UDP 26.0.0). 게임 업데이트로 맞춘다 |

**막힐 때**

| 증상 | 원인 / 해결 |
|---|---|
| Sessions가 비어 있다 | ① 결과 화면까지 안 갔거나 세션 도중에 Agent를 켰다(맥락 없는 순위표는 보내지 않는다) ② Time Trial 세션이다 ③ 백엔드가 P7 이전 빌드다(모르는 이벤트를 Ack하고 버린다) ④ Agent가 `다시 연결 필요` 상태다(§6) |
| Agent 콘솔에 `서버 Reject … reason=SessionClassified 검증 실패 …` | 서버가 영구 무효로 거절했다. 같은 시각 백엔드 로그의 `detail=`을 확인한다(예: `position`·`carIndex` 범위 밖, 음수 값) |
| Reject 사유 `트랙 매핑 없음(gameCode=…, trackId=…)` | 트랙 마스터에 없는 트랙 ID — 랩과 같은 원인이다 |
| Agent 경고 `…가 …바이트로 한도(…)를 넘어 타이어 스틴트를 빼고 적재` | 정상 경로에서는 일어나지 않는 크기다(게임 최대 약 24KB, 이름이 검증 한도까지 길어도 약 32KB, 한도 48KiB). 결과는 올라가지만 타이어 컴파운드 아이콘이 없다. 로그를 보관해 알려 준다 |
| 시즌은 생겼는데 세션이 시즌 없이 따로 나온다 | 그 세션의 링크 값이 0이거나 모드가 시즌 대상이 아니다(위 SQL의 `season_link_id`·`game_mode`). 같은 키인데 트랙·종류가 다르면 서버가 `세션 키 충돌 … uid 키로 대체` 경고를 남기고 시즌 없이 저장한다 |
