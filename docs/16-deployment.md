# 16 · 외부 공개 배포 — 웹은 GitHub Pages, 백엔드는 Tailscale Funnel

> Status: **Design 확정 (2026-10-19, 구현 전)** · Last Updated: 2026-10-19
> 사용자 요청(2026-10-19): "DB와 웹서버를 내 PC가 아닌 곳에 올려 외부에서도 보고 싶다. 비용은 들지 않게."
> 논의 결과: 항상 켜져 있는 PC(`DESKTOP-JC07560`)와 이미 쓰고 있는 Tailscale Funnel을 그대로 활용하고, 웹은 GitHub Pages에 올린다.
> 결정은 §11(D-55~D-60), [08](./08-open-decisions.md) §M에도 반영했다.

---

## 0. 요약

| 구성 요소 | 위치 | 공개 주소 | 비용 |
|---|---|---|---|
| 웹(Flutter Web) | GitHub Pages | `https://stlim1025.github.io/SimHub/` | 0 |
| 백엔드(ASP.NET Core 10, REST·SignalR) | `DESKTOP-JC07560`, `127.0.0.1:5290` | `https://desktop-jc07560.tail4a150e.ts.net:8443` (Funnel) | 0 |
| PostgreSQL | `DESKTOP-JC07560`, DB `simcenter_prod` | 공개하지 않음 | 0 |
| Agent | 각자의 게임 PC | — | 0 |

```
브라우저 ──HTTPS──► stlim1025.github.io/SimHub/ (정적 파일만)
   │
   │ REST /api/v1 · SignalR /hubs/ranking  (CORS: github.io 한 곳만 허용)
   ▼
Tailscale Funnel :8443 ──► 127.0.0.1:5290  SimCenter.Api (Production)
                                  │
게임 PC Agent ──SignalR /hubs/telemetry (장치 키)──┘      └──► PostgreSQL simcenter_prod (로컬 전용)

(같은 머신의 기존 Funnel :443 → 127.0.0.1:5280 "치이카와 마을 생활"은 건드리지 않는다)
```

---

## 1. 범위

| 포함 | 제외(이후) |
|---|---|
| 백엔드 운영 모드 실행에 필요한 코드 변경(§4) | 유료 클라우드·VPS 이전 |
| 이 PC에서 백엔드를 상시 실행하는 절차(§5) | Docker 컨테이너화(이 구성에는 필요 없음) |
| Funnel 8443 연결(§6) | 사용자 도메인 연결(`*.ts.net`·`*.github.io` 그대로 사용) |
| GitHub Pages 자동 배포 워크플로(§7) | Agent 설치 파일·자동 업데이트(P11) |
| Agent 서버 주소 변경 안내(§8) | 무중단 배포, 다중 인스턴스 |
| 백업·업데이트·로그 운영 절차(§9) | 모니터링·알림 |

---

## 2. 전제와 제약

- **회사 PC 사용:** `DESKTOP-JC07560`은 회사 자산이다. 외부 공개 서비스를 올리는 것은 회사 규정 확인을 전제로 한다(사용자 책임). 이미 같은 머신에서 Funnel로 다른 서비스를 공개하고 있다.
- **Funnel 포트:** 공개할 수 있는 포트는 443·8443·10000뿐이다. 443은 기존 서비스가 쓰고 있으므로 SimCenter는 **8443**을 쓴다.
- **저장소 공개:** `stlim1025/SimHub`는 공개 저장소다(GitHub Pages 무료 조건). 웹 빌드에 들어가는 API 주소는 공개되어도 되는 값이고, 시크릿은 저장소·빌드 어디에도 넣지 않는다.
- **같은 PC에서 개발도 한다:** 개발용 백엔드(`:5284`, Development)와 운영 백엔드(`:5290`, Production)가 동시에 떠도 충돌하지 않도록 **포트와 DB를 분리**한다.
- **가용성:** 이 PC가 꺼지거나 재부팅 중이면 웹 화면은 열리지만 로그인·조회가 실패한다. Agent는 Outbox에 쌓았다가 복구되면 다시 보낸다(기존 동작, [13](./13-outbox-dead-letter.md)).

---

## 3. 주소·포트·설정 값

| 항목 | 값 | 비고 |
|---|---|---|
| 운영 백엔드 바인딩 | `http://127.0.0.1:5290` | 루프백만. 회사 LAN에 직접 노출하지 않는다 |
| 개발 백엔드 | `http://localhost:5284` | 기존 그대로 |
| Funnel | `https://desktop-jc07560.tail4a150e.ts.net:8443` → `http://127.0.0.1:5290` | HTTPS 종료는 Tailscale이 한다 |
| 웹 오리진 | `https://stlim1025.github.io` | CORS 허용 대상(경로 `/SimHub/`는 오리진에 포함되지 않음) |
| 웹 base href | `/SimHub/` | 프로젝트 페이지 하위 경로 |
| 운영 DB | 로컬 PostgreSQL의 `simcenter_prod` | 개발·E2E·통합 테스트 DB와 분리 |
| `ASPNETCORE_ENVIRONMENT` | `Production` | |

---

## 4. 백엔드 코드 변경

현재 [Program.cs](../backend/src/SimCenter.Api/Program.cs)는 개발 모드를 전제로 한 부분이 있다. 아래 5가지를 바꾼다.

### 4.1 운영 설정 주입

- 시크릿은 **환경 변수**로만 넣는다(저장소·`appsettings.*.json`에 넣지 않음).
  - `ConnectionStrings__Postgres` = `Host=localhost;Port=5432;Database=simcenter_prod;Username=...;Password=...`
  - `Jwt__Key` = 32자 이상 무작위 값(개발 키와 다른 값)
- 시크릿이 아닌 운영 값은 `appsettings.Production.json`(저장소 포함)에 둔다: CORS 허용 오리진(§4.4), 마이그레이션 플래그(§4.2), 로그 파일 설정(§9.3).
- 누락 시 기동 실패는 이미 구현되어 있다(`ConnectionStrings:Postgres` 예외, `Jwt:Key` `ValidateOnStart`).

### 4.2 마이그레이션·시드를 설정으로 켜기

- 지금은 `IsDevelopment()`일 때만 `MigrateAndSeedAsync`를 실행한다. 그런데 **트랙 마스터 시드(`DbSeeder`)는 운영에도 필요하다** — 트랙 매핑이 없으면 그 트랙의 랩·세션이 거부되어 영구 손실된다(D-41, `TrackSeedE2ETests`).
- 설정 `Database:MigrateOnStartup`(bool)을 추가한다.
  - Development: 설정이 없으면 `true`(기존 동작 유지).
  - Production: `appsettings.Production.json`에 `true`. 단일 인스턴스라 기동 시 적용해도 경합이 없다.
- 시드는 이미 멱등(있는 트랙은 표시 정보만 맞춤)이므로 매 기동마다 실행해도 된다.
- Swagger는 지금처럼 Development에서만 연다.

### 4.3 프록시 헤더와 HTTPS 리다이렉트

- Funnel은 HTTPS를 받아 `127.0.0.1:5290`으로 **HTTP**로 넘긴다. 앱이 보는 원격 주소는 모두 `127.0.0.1`이다.
- `UseForwardedHeaders`를 켠다(`XForwardedFor | XForwardedProto`). 신뢰할 프록시는 **루프백(`127.0.0.1`, `::1`)만** 지정한다([11 §9 배포 메모](./11-personal-mode.md)).
  - 효과 1: `X-Forwarded-Proto: https`가 오면 요청 스킴이 https가 되어 `UseHttpsRedirection`이 리다이렉트하지 않는다(무한 리다이렉트 방지).
  - 효과 2: `X-Forwarded-For`가 오면 `/agent/pair`의 IP당 요청 제한이 실제 클라이언트별로 나뉜다.
- 미들웨어 순서: `UseForwardedHeaders` → `UseSerilogRequestLogging` → 예외 매핑 → `UseHttpsRedirection` → CORS → 인증 → …
- ⚠ **확인 필요(§10-1):** Funnel이 두 헤더를 실제로 붙이는지는 구현 단계에서 요청 로그로 확인한다. 붙이지 않으면 IP당 제한은 전 사용자가 버킷 하나를 공유하게 된다(기능은 동작, 제한만 거칠어짐).

### 4.4 운영 CORS

- 웹(`stlim1025.github.io`)과 API(`*.ts.net:8443`)의 오리진이 다르므로 운영 CORS가 필요하다.
- 설정 `Cors:AllowedOrigins`(문자열 배열)를 추가하고, 운영은 `["https://stlim1025.github.io"]` **한 곳만** 허용한다. 와일드카드는 쓰지 않는다.
- 정책 내용은 개발 정책과 같다: 지정 오리진, `AllowAnyHeader`, `AllowAnyMethod`, `AllowCredentials`(SignalR negotiate).
- Development는 기존 루프백 반사 정책을 유지한다. 운영에서 설정이 비어 있으면 CORS를 열지 않는다(동일 오리진만).
- Agent의 `TelemetryHub` 연결은 브라우저가 아니므로 CORS와 무관하다.

### 4.5 공개 인터넷 노출 보호

Funnel은 인터넷 전체에 공개된다. 지금 `POST /auth/register`·`POST /auth/login`에는 요청 제한이 없다.

- **로그인 요청 제한(제안 D-58):** `POST /auth/login`에 IP당 분당 10회 정책(`auth-login`)을 추가한다. 기존 고정 창 정책(`RateLimitPolicies`)을 재사용한다. §4.3의 IP 판별에 의존한다.
- **회원가입 차단(D-59, 사용자 결정 2026-10-19: "가입을 막고 내 계정만 쓸게"):**
  - 설정 `Auth:AllowRegistration`(bool)을 추가한다. 설정이 없으면 `true`(Development·통합 테스트의 기존 동작 유지).
  - 운영은 `appsettings.Production.json`에 `false`. 이때 `POST /auth/register`는 **403**(ProblemDetails, 기존 예외 매핑 사용)을 돌려주고 사용자를 만들지 않는다.
  - 로그인·장치 연결 등 다른 API는 영향 없다. 앱의 가입 화면은 그대로 두고 403을 기존 오류 표시로 보여준다(앱 수정 없음).
  - **첫 계정 만들기:** 운영 DB(`simcenter_prod`)는 비어 있다. 처음 한 번만 환경 변수 `Auth__AllowRegistration=true`로 기동 → 웹에서 본인 계정 가입 → 환경 변수를 지우고 재기동한다(§5-6). 환경 변수가 `appsettings.Production.json`보다 우선한다.
  - 검토했으나 제외: "사용자가 0명일 때만 가입 허용"(첫 가입 경쟁 시 공개 상태에서 남이 먼저 가입할 수 있음), 초대 코드(YAGNI).

---

## 5. 백엔드 상시 실행 (이 PC)

추가 패키지나 서비스 래퍼 없이 **Windows 작업 스케줄러**로 실행한다(제안 D-57).

1. **DB 준비:** 로컬 PostgreSQL에 `simcenter_prod` DB와 전용 계정을 만든다(개발 DB와 분리).
2. **게시(publish):** 저장소 밖의 고정 폴더로 게시한다.
   ```
   dotnet publish backend/src/SimCenter.Api -c Release -o D:\SimCenterServer\app
   ```
3. **환경 변수:** 작업 스케줄러 작업이 읽도록 시스템 환경 변수 또는 실행 스크립트(`D:\SimCenterServer\run.cmd`, 저장소 밖)에 설정한다.
   - `ASPNETCORE_ENVIRONMENT=Production`
   - `ASPNETCORE_URLS=http://127.0.0.1:5290`
   - `ConnectionStrings__Postgres=...`, `Jwt__Key=...`
4. **작업 스케줄러 등록:** 트리거 "시스템 시작 시", "사용자 로그온 여부에 관계없이 실행", 실패 시 1분 뒤 재시작(최대 3회). 대상 = `run.cmd`(내부에서 `SimCenter.Api.exe` 실행).
5. 재부팅 후 자동으로 떠 있는지 `curl -i http://127.0.0.1:5290/api/v1/me`가 401(토큰 없음)을 돌려주는지로 확인한다.
6. **첫 계정(최초 1회):** `run.cmd`에 `Auth__AllowRegistration=true`를 임시로 넣고 기동 → 웹에서 가입 → 그 줄을 지우고 재기동 → `POST /auth/register`가 403인지 확인한다(§4.5).

> 대안: `UseWindowsService`(Windows 서비스 등록)는 `Microsoft.Extensions.Hosting.WindowsServices` 패키지 추가가 필요해 이번 범위에서 제외한다. 운영이 불편하면 그때 다시 판단한다.

---

## 6. Funnel 연결

기존 443 설정은 그대로 두고 8443만 추가한다. 백그라운드(`--bg`) 설정은 재부팅 후에도 유지된다.

```
tailscale funnel --bg --https=8443 http://127.0.0.1:5290
tailscale funnel status
```

기대 결과:

```
https://desktop-jc07560.tail4a150e.ts.net (Funnel on)
|-- / proxy http://127.0.0.1:5280
https://desktop-jc07560.tail4a150e.ts.net:8443 (Funnel on)
|-- / proxy http://127.0.0.1:5290
```

명령 문법은 실행 전에 `tailscale funnel --help`(현재 1.104.1)로 다시 확인한다.

---

## 7. 웹 — GitHub Pages 자동 배포

### 7.1 워크플로

`.github/workflows/deploy-web.yml`을 추가한다.

- 트리거: `main`에 push되고 `app/**`가 바뀌었을 때 + 수동 실행(`workflow_dispatch`).
- 단계: checkout → Flutter stable 설치(`pubspec.yaml`의 Dart `^3.11.0`을 만족하는 버전) → `flutter pub get` → `flutter test` → 웹 빌드 → Pages 아티팩트 업로드 → 배포.
- 빌드 명령:
  ```
  flutter build web --release --base-href /SimHub/ --dart-define=API_BASE_URL=${{ vars.API_BASE_URL }}
  ```
- `API_BASE_URL`은 코드나 워크플로에 박지 않고 **저장소 변수(Repository variable)** 로 둔다. 값 = `https://desktop-jc07560.tail4a150e.ts.net:8443`. 주소가 바뀌면 변수만 고치고 다시 실행한다.
- `RANKING_HUB_URL`은 넣지 않는다. 없으면 `API_BASE_URL + /hubs/ranking`을 쓴다([app_config.dart](../app/lib/core/config/app_config.dart)).
- 배포는 GitHub 공식 액션(`actions/configure-pages`, `actions/upload-pages-artifact`, `actions/deploy-pages`)을 쓴다.
- Flutter는 서드파티 설치 액션 대신 **공식 저장소(`flutter/flutter`)의 버전 태그를 받아** 쓴다. 버전은 로컬 개발 SDK와 같은 `3.44.5`(stable)로 고정한다(워크플로의 `FLUTTER_VERSION`).
- base href는 저장소 이름에서 만든다(`/SimHub/`). 저장소 변수 `API_BASE_URL`이 비어 있으면 빌드 전에 실패한다.

### 7.2 사용자가 GitHub에서 할 일

1. Settings → Pages → Source를 **GitHub Actions**로 바꾼다.
2. Settings → Secrets and variables → Actions → Variables에 `API_BASE_URL`을 추가한다.

### 7.3 라우팅

- 앱은 URL 전략을 따로 정하지 않아 Flutter 기본값인 **해시 방식(`/#/laps`)** 을 쓴다. GitHub Pages에서 하위 화면을 새로고침해도 404가 나지 않으므로 `404.html` 우회는 필요 없다.
- `web/index.html`은 이미 `$FLUTTER_BASE_HREF`를 쓰므로 수정하지 않는다.

---

## 8. Agent

- 이 PC에서 실행하는 Agent는 기존처럼 로컬 주소를 써도 된다. 단 운영 서버에 붙이려면 `http://127.0.0.1:5290`.
- 다른 PC(집 게임 PC)의 Agent는 `appsettings.json`의 `Agent:ServerBaseUrl`을 `https://desktop-jc07560.tail4a150e.ts.net:8443`으로 바꾼다.
- 장치 키 연결(`POST /agent/pair`) → `TelemetryHub` WebSocket 연결이 Funnel을 통과하는지 E2E로 확인한다(§10-2).
- 코드 변경은 없다. 사용자 안내는 [TESTING-local-e2e.md](./TESTING-local-e2e.md)가 아닌 이 문서 §8에 둔다.

---

## 9. 운영

### 9.1 백업

- 작업 스케줄러로 매일 1회 `pg_dump -Fc simcenter_prod`를 실행해 `D:\SimCenterServer\backup\`에 날짜별로 저장하고, 최근 7개만 남긴다.
- 회사 PC 회수·재설치에 대비해 가끔 덤프 파일을 PC 밖으로 옮긴다(사용자 수동).

### 9.2 새 버전 반영

1. 저장소에서 `main` 최신을 받는다.
2. 작업 스케줄러 작업 중지 → §5-2의 publish 다시 실행 → 작업 시작.
3. 마이그레이션은 기동 시 자동 적용된다(§4.2). 적용 전에 §9.1 백업을 한 번 수동으로 돌린다.
4. 웹은 `main`에 push되면 GitHub Actions가 자동 배포한다.

### 9.3 로그

- 작업 스케줄러로 실행하면 콘솔 출력이 남지 않는다. `appsettings.Production.json`의 `Serilog` 섹션에서 파일 출력(`D:\SimCenterServer\logs\`, 일 단위, 14일 보관)을 켠다.
- 파일 싱크는 `Serilog.AspNetCore`에 포함된 `Serilog.Sinks.File`을 쓴다고 보고 있으며, 포함 여부는 구현 시 확인한다. 포함되지 않으면 패키지 추가를 따로 묻는다.
- 기존 원칙 유지: JWT·장치 키·연결 코드 원문은 로그에 남기지 않는다.

---

## 10. 위험과 확인할 것

| # | 항목 | 확인 방법 | 안 될 때 |
|---|---|---|---|
| 1 | Funnel이 `X-Forwarded-For`·`X-Forwarded-Proto`를 붙이는가 | 운영 기동 후 요청 로그의 원격 IP·스킴 확인 | Proto가 없으면 HTTPS 리다이렉트를 운영에서 끈다. For가 없으면 IP당 제한이 공유 버킷이 됨을 문서화 |
| 2 | SignalR WebSocket이 Funnel을 통과하는가 | 웹 리더보드 실시간 갱신, Agent `TelemetryHub` 연결 | SignalR이 자동으로 SSE·롱 폴링으로 내려가는지 확인 |
| 3 | 허브 메시지 1MiB(D-49)가 Funnel을 통과하는가 | 트레이스가 있는 랩 전송 E2E | 실패 시 원인 확인 후 별도 결정 |
| 4 | Funnel 대역폭·사용 정책 한도 | Tailscale 문서 확인 | 개인 사용 수준이면 문제없을 것으로 봄 |
| 5 | 회사 규정 | 사용자 확인 | Oracle Always Free VM 등으로 이전(이 문서 §4·§7은 그대로 재사용 가능) |
| 6 | PC 재부팅(Windows 업데이트) | 재부팅 후 자동 기동 확인(§5-5) | 작업 스케줄러 트리거·재시도 설정 점검 |

---

## 11. 결정 (2026-10-19 확정, 08 §M)

| ID | 결정 | 비고 |
|---|---|---|
| D-55 | 외부 공개 = 웹 GitHub Pages(`/SimHub/`) + 백엔드 `DESKTOP-JC07560` Tailscale Funnel `:8443` → `127.0.0.1:5290`, DB는 로컬 `simcenter_prod` | 비용 0. 같은 PC의 개발 환경과 포트·DB 분리 |
| D-56 | 운영 설정 = 시크릿은 환경 변수, 비시크릿은 `appsettings.Production.json`. `Database:MigrateOnStartup`·`Cors:AllowedOrigins` 추가 | 트랙 시드는 운영에도 필요 |
| D-57 | 상시 실행 = 작업 스케줄러(시스템 시작 시) + publish 폴더 `D:\SimCenterServer\app` | Windows 서비스 래퍼는 제외 |
| D-58 | 프록시 헤더는 루프백만 신뢰, `POST /auth/login` IP당 분당 10회 | 11 §9 배포 메모 이행 |
| D-59 | 운영 회원가입 차단 = `Auth:AllowRegistration=false`(기본값 true), 가입 요청 403. 첫 계정은 환경 변수로 잠깐 열고 만든다 | 사용자 결정 2026-10-19 |
| D-60 | 웹 API 주소 = 저장소 변수 `API_BASE_URL`, 워크플로가 `--dart-define`으로 주입 | 주소 변경 시 코드 수정 없음 |

---

## 12. 구현 순서와 테스트

헌장 순서(설계 → 리뷰 → 구현 → 리뷰)를 따른다. 각 단계 끝에 리뷰한다.

| 단계 | 내용 | 테스트 |
|---|---|---|
| 1 | §4.1·§4.2 운영 설정, `MigrateOnStartup` | 통합 테스트: 플래그 true면 마이그레이션·시드 실행, false면 실행 안 함, Development 기본값 유지 |
| 2 | §4.3 프록시 헤더 | 통합 테스트: 루프백에서 온 `X-Forwarded-Proto: https`는 리다이렉트 없음, `X-Forwarded-For`로 IP당 제한이 분리됨 |
| 3 | §4.4 운영 CORS | 통합 테스트: 허용 오리진 preflight 성공, 다른 오리진 거부, 설정 비면 CORS 헤더 없음 |
| 4 | §4.5 로그인 제한·가입 차단 | 통합 테스트: 11번째 로그인 429, `AllowRegistration=false`면 가입 403·사용자 미생성, 설정 없으면 가입 성공 |
| 5 | §7 GitHub Pages 워크플로 | PR에서 워크플로 실행 확인, 배포된 페이지 접속 |
| 6 | §5·§6 이 PC 실행·Funnel 연결 | 수동: §10 확인 항목 1~3, 다른 PC Agent로 랩 1개 전송 → 웹 리더보드 표시 |

단계 1~5는 코드 변경이고, 단계 6은 사용자 PC 설정이라 명령을 안내하고 사용자와 함께 진행한다.
