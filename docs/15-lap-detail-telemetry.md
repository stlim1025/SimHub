# 15 · F1Laps 수준 맞추기 — 랩 상세 · 텔레메트리 · 트랙 순서/국기 · 팀 아이콘

> Status: **Design → 구현 중 (2026-10-18)** · Last Updated: 2026-10-18
> 사용자 요청(2026-10-18): "디자인·구성·기능이 F1Laps와 많이 다르다. 랩타임을 누르면 랩 상세가 나와야 하고, 텔레메트리도 저장·조회돼야 한다.
> 트랙 선택은 F1 캘린더 순서 + 국기, 프로필 사진은 팀 아이콘이어야 한다. Flutter라서 이런 건가, HTML·JS로 가야 하나?"
> 로드맵상 P9(랩 상세 + 텔레메트리, [09](./09-lap-telemetry-trace.md))를 P8보다 앞당긴다. 결정은 [08](./08-open-decisions.md) §L(D-42~D-48).

---

## 0. 무엇이 달랐나 (원인)

| 사용자가 본 차이 | 원인 | 이 문서의 해결 |
|---|---|---|
| 화면 구성·밀도가 F1Laps와 다름 | Flutter 때문이 아니라 **Material 기본 위젯**(DataTable·SegmentedButton·둥근 카드 목록)을 그대로 썼다 | 직접 만든 촘촘한 표·헤더·트랙 선택 메뉴(§2) |
| 랩타임을 눌러도 상세가 없음 | 랩 상세는 P9 예정이라 **화면·API가 없었다** | `/laps/:lapId` 3탭 화면 + `GET /me/laps/{id}`(§2.3, §4.2) |
| 텔레메트리가 없음 | Agent가 **랩타임·섹터만** 읽었다(Car Telemetry·Status·Damage 미해석). 서버 저장소·화면도 없음 | 1랩 트레이스·차량 스냅샷 수집 → 저장 → 그래프(§3~§5) |
| 트랙이 ABC 순서, 국기 없음 | `Track`에 국가·순서 정보가 없어 이름순 정렬 | `Track.CountryCode`·`DisplayOrder` + 국기 위젯(§4.1) |
| 프로필 사진이 영어 글자 | D-39에서 **상표인 팀 로고를 쓰지 않고** 팀 색 원 + 코드로 그렸다 | 로고 이미지 자리(asset) 지원 + 없으면 기존 원(D-48) |

**Flutter 유지(D-42).** 위 다섯 가지는 모두 데이터·기능·위젯 선택의 문제이고, HTML·JS로 바꿔도 그대로 남는다.
F1Laps의 모양(촘촘한 표, 작은 대문자 머리글, 얇은 구분선, 인디고 랩타임)은 Flutter 위젯으로 그대로 만들 수 있다.
앱 전체(약 80개 파일·테스트 364개)를 다시 쓰는 비용에 비해 얻는 것이 없다. Flutter Web의 실제 약점(첫 로딩이 무겁고, 브라우저 찾기·텍스트 선택이 제한적)은
개인 대시보드에서는 감수할 만하다 — 나중에 문제가 되면 그때 다시 판단한다.

---

## 1. 범위

| 포함 | 제외(이후) |
|---|---|
| Laps 화면 F1Laps 배치: 국기 + 트랙 이름 + 선택 메뉴, Recent/Fastest, 유효 랩만, TEAM·TIME·MODE·날씨·DATE 표, 행 클릭 → 랩 상세 | "Add New Lap Time"(수동 입력), Equal cars only |
| 트랙 메뉴 = F1 25 캘린더 순서 + 국기 (Laps · Leaderboard 공통) | 트랙 이름을 국가 이름으로 바꾸기(이름은 그대로) |
| 랩 상세 3탭: Lap Details · Telemetry · Your Best Laps | 랭킹 1위 랩과 비교(비교 대상은 내 최고 유효 랩만) |
| 랩 끝의 차량 스냅샷: 팀 · 타이어(컴파운드·나이·마모 시작/끝) · 손상 · 연료 · ERS · 날씨·기온·노면 온도·비 예보 | 트랙 지도(Motion 위치), 섹터 경계 표시 |
| 1랩 텔레메트리 트레이스(거리 기준): 시간·속도·스로틀·브레이크·스티어·기어·RPM | 타이어 온도·브레이크 온도·G-force 채널 |
| 프로필 사진의 팀 로고 이미지 자리(asset) | 로고 파일 자체(상표 — 사용자가 넣거나 따로 승인) |

---

## 2. 화면 (App)

### 2.1 Laps — `/laps`, `/laps/tracks/:trackId`

```
[국기] Jeddah ⇅                            ← 누르면 트랙 메뉴(§2.2)
[Recent | Fastest]  [✓ 유효 랩만]
┌─────────────────────────────────────────────────────────────┐
│ TEAM          TIME           MODE            (날씨)   DATE    │  ← 작은 대문자 머리글, 표면보다 살짝 어두운 줄
│ ● Ferrari     1:38.448 ✓     Driver Career     ☀    2026-07-26│  ← 행 전체 클릭 → /laps/:lapId
│ ...                                                           │
│ Showing 1 to 15 of 76 results                    [이전][다음] │
└─────────────────────────────────────────────────────────────┘
```

- `/laps`는 **마지막으로 달린 트랙**(`GET /me/tracks` 첫 항목)의 표를 바로 보인다(주소는 `/laps` 그대로). 기록이 없으면 빈 상태 카드 + 트랙 메뉴.
- 표는 `DataTable` 대신 직접 만든 행(높이 44, 구분선, 마우스 올리면 강조). 열: **TEAM**(팀 색 점 + 이름, 없으면 `-`) ·
  **TIME**(강조색 굵게, 유효 ✓ 원 아이콘 / 무효 빨간 ✕ + 툴팁) · **MODE**(게임 모드 라벨, 없으면 세션 유형 라벨) · **날씨 아이콘**(툴팁) · **DATE**.
- 600px 미만이면 MODE·날씨 열을 숨긴다.
- "유효 랩만" = `validOnly=true`. 정렬·필터를 바꾸면 1페이지로.

### 2.2 트랙 메뉴 (공용 위젯 `TrackPicker`)

- 제목(국기 + 이름 + ⇅)을 누르면 제목 자리에 붙어 열리는 목록(폭 약 280, 최대 높이 화면의 80%, 스크롤). 각 줄 = 원형 국기 + 트랙 이름, 고른 트랙은 강조색 글자.
- 순서 = `GET /tracks`의 순서(`displayOrder` — F1 25 캘린더 24개 → 리버스 3개 → 그 밖, §4.1). 기록이 없는 트랙도 보인다(고르면 빈 표).
- Leaderboard의 트랙 드롭다운도 같은 위젯으로 바꾼다.
- 국기는 `country_flags` 패키지(ISO 3166-1 alpha-2, SVG 내장)로 그린다. 코드가 없거나 모르면 회색 원.
  (Windows 브라우저는 국기 이모지를 그리지 못해 이모지는 쓰지 않는다.)

### 2.3 랩 상세 — `/laps/:lapId?tab=details|telemetry|best`

맨 위: [← 트랙 표로] 국기 + 트랙 이름 · 랩타임. 그 아래 탭 3개(F1Laps처럼 화면 폭을 나눠 쓰는 탭 바, 주소의 `tab`과 동기화, 모르는 값은 details).
탭 아래 "비교: 내 최고 유효 랩"(표시만 — 선택지는 하나).

**Lap Details** (900px 이상 2열, 미만 1열)

| 영역 | 내용 |
|---|---|
| Lap Time | Total(크게, 강조색) · Sector 1·2·3 |
| Comparison | 표: 행 = 내 최고 랩 / 이 랩 / Delta, 열 = TOTAL·SEC 1·2·3. Delta는 빠르면 초록 `-0.123`, 느리면 빨강 `+0.456`. 이 랩이 최고면 "이 랩이 내 최고 기록" |
| Lap Details | Track(국기) · Team · Game Mode · Session · Lap(번호) · Lap Valid(✓ Valid / ✕ Invalid) · Lap ID(앞 8자 + 복사 버튼) · Date(시각까지) · 세션 보기 링크(있으면) |
| Car & Tyres | 위에서 본 차 그림(CustomPainter): 네 바퀴를 마모로 색칠(<25% 초록, <50% 노랑, <75% 주황, 그 이상 빨강), 바퀴 옆 `31%` 배지 + 기울임 `+4.0%`(이 랩 동안 늘어난 마모). 앞날개 좌·우도 손상으로 색칠. 컴파운드 원 + "N랩째" |
| Damage | Front Wing (L/R) · Rear Wing · Floor · Diffuser · Sidepod · Gear Box · Engine · Tyre Wear (fl/fr/rl/rr) · Brake Damage (fl/fr/rl/rr). 0은 `-` |
| Conditions | Weather(아이콘 + 이름) · Air temperature · Track temperature · Rain forecast |
| Fuel | Used this lap(kg) · Remaining(kg) · Laps remaining |
| ERS | Used this lap(%) · Remaining(%) — 배터리 최대 4 MJ 기준(§3.2) |

스냅샷이 없는 랩(이전 Agent로 기록)은 아래 4개 영역 대신 "이 랩에는 차량 데이터가 없어요" 한 장.

**Telemetry**

- 그래프를 세로로 쌓는다: Speed · Throttle · Brake · Gear · Steering · RPM, 그리고 비교 랩 트레이스가 있으면 맨 위에 **Delta**(같은 거리에서 이 랩 시간 − 비교 랩 시간, 0 기준선).
- 가로축 = 랩 거리(m). 이 랩은 강조색, 비교 랩은 청록. 범례에 두 랩타임.
- 마우스를 올리거나 누르면 **모든 그래프에 같은 거리의 세로선**과 두 랩의 값을 보인다(동기화된 십자선).
- 속도 단위는 사용자 설정(`units`: Metric km/h, Imperial mph).
- 직접 그린다(CustomPainter) — 차트 라이브러리를 들이지 않는다(십자선 동기화가 라이브러리로는 오히려 번거롭다).
- 트레이스가 없으면 "이 랩은 텔레메트리가 저장되지 않았어요(새 Agent로 달린 랩부터 저장돼요)".

**Your Best Laps**: 이 트랙의 내 유효 랩 빠른 순 10개(`sort=fastest&validOnly=true&pageSize=10`). 열: # · TEAM · TIME · GAP(1위 대비) · MODE · DATE. 지금 보는 랩은 강조, 행을 누르면 그 랩 상세.

### 2.4 프로필 사진 (D-48)

- `assets/team_logos/{CODE}.png`(예: `FER.png`)가 있으면 팀 색 원 안에 로고를 그린다. 없으면 지금처럼 팀 색 원 + 코드.
- 앱은 시작할 때 AssetManifest에서 `assets/team_logos/` 아래 파일을 읽어 "로고가 있는 코드" 목록을 만든다(없는 파일을 요청해 404를 내지 않는다).
- 로고 파일은 저장소에 넣지 않는다(상표). 폴더 안 `README.md`에 넣는 방법을 적는다.

---

## 3. 데이터 수집 (Agent)

### 3.1 새로 읽는 패킷

| 패킷 | 새 프레임/필드 | 쓰임 |
|---|---|---|
| Session (1) | `SessionFrame` + `Weather`, `AirTemperatureC`, `TrackTemperatureC`, `TrackLengthM`, `RainForecastPercent?` | Conditions |
| Lap Data (2) | `LapFrame` + `LapDistanceM`, `CurrentLapTimeMs` | 트레이스 거리·시간 |
| Car Telemetry (6) | 새 `CarTelemetryFrame`(플레이어 차): 속도 km/h, 스로틀 0~1, 브레이크 0~1, 스티어 −1~1, 기어, RPM | 트레이스 |
| Car Status (7) | 새 `CarStatusFrame`(플레이어 차): 연료(kg), 남은 랩, ERS 저장량(J), 이 랩 배포·회수(J, MGU-K+MGU-H), 실제·표시 컴파운드, 타이어 나이 | 스냅샷 |
| Car Damage (10) | 새 `CarDamageFrame`(플레이어 차): 타이어 마모(%)·손상·브레이크 손상(바퀴 4개), 앞날개 L/R·뒷날개·플로어·디퓨저·사이드포드·기어박스·엔진(%) | 스냅샷 |
| Participants (4) | 기존 `ParticipantsFrame` — 플레이어 차의 `TeamId` | 스냅샷 팀 |

- 프레임은 게임 중립 이름을 쓴다(Core는 F1Game.UDP를 모른다). 바퀴 4개 값은 `WheelSet(FrontLeft, FrontRight, RearLeft, RearRight)` 하나로 묶는다.
  **F1 UDP 배열 순서는 RL·RR·FL·FR**이다 — 매퍼가 이름으로 옮길 때 섞지 않는다(테스트로 고정).
- 비 예보: 현재 세션 종류의 예보 샘플 중 `TimeOffset > 0`인 가장 이른 샘플의 `RainPercentage`. 없으면 그 세션 종류의 첫 샘플, 그것도 없으면 null.
- 날씨 값: `Clear · LightCloud · Overcast · LightRain · HeavyRain · Storm`(게임 0~5). 모르는 값은 null.

### 3.2 랩 스냅샷 (LapFinished `car`·`conditions`)

- 랩 동안 마지막으로 받은 Car Status·Car Damage·Session 값을 들고 있다가, 랩이 끝나는 순간(`LapAnalyzer`가 LapFinished를 만들 때) **끝 값**으로 쓴다.
- **시작 값**(연료·ERS 저장량·타이어 마모)은 새 랩이 시작된 뒤 처음 받은 값이다. 시작 값이 없으면(랩 중간에 Agent 시작 등) 그 필드는 보내지 않는다.
- "이 랩 사용량"은 앱이 계산한다: 연료 = 시작 − 끝(kg), ERS = (시작 − 끝) / 4,000,000 J × 100(%), 마모 증가 = 끝 − 시작.
- 아무 값도 받지 못했으면 `car`·`conditions`를 보내지 않는다(옛 계약과 같다).

### 3.3 텔레메트리 트레이스 (LapFinished `trace`) — D-45

- **거리 기준 표본.** Car Telemetry 프레임마다 가장 최근 Lap Data의 `LapDistanceM`·`CurrentLapTimeMs`로 칸 번호 `floor(거리 / 5m)`를 구해
  그 칸에 표본을 **덮어쓴다**(플래시백으로 되돌아가 다시 달리면 나중 값이 이긴다). 음수 거리(출발선 전)는 버린다.
- 새 랩이 시작되면(랩 번호가 바뀌는 Lap Data) 버퍼를 LapFinished에 실은 뒤 비운다.
- 길이 = 채워진 마지막 칸 + 1. 빈 칸은 앞 값으로 채우고(맨 앞이 비면 첫 값으로), **채워진 칸이 전체의 50% 미만이면 트레이스를 보내지 않는다.**
- 채널(모두 정수 배열, 같은 길이): `timeMs`(랩 시작부터 ms) · `speedKph` · `throttle`(0~100) · `brake`(0~100) · `steer`(−100~100) · `gear`(−1~8, 0=N, −1=R) · `rpm`.
- **크기 한도:** Outbox 봉투 한도(48KiB, `OutboxTelemetrySink.MaxEnvelopeBytes`)를 넘으면 표본을 하나 걸러 버려 해상도를 두 배(10m → 20m)로 낮춰 다시 잰다.
  20m에서도 넘으면 트레이스만 빼고 랩은 보낸다(경고 로그). 5m 기준 가장 긴 Spa(약 7km, 1,400칸)도 약 35~40KB로 보통은 한 번에 들어간다.
- 무효 랩·아웃/인 랩도 트레이스를 보낸다(랩과 똑같이 저장만 하고 화면에서 구분).

> **D-17 해석:** 이것은 패킷 스트림이 아니라 Agent가 로컬에서 만든 **정제된 1랩 표본 1건**이고 랩과 같은 이벤트로 한 번만 간다. 헌장의
> "Raw 패킷 firehose를 서버로 흘리거나 원본 저장하지 않는다"와 양립한다.
> **[09](./09-lap-telemetry-trace.md)의 "별도 REST 업로드"를 바꾼 이유:** Agent에는 장치 키로 인증하는 REST 클라이언트가 없고, 별도 업로드는 서버의 랩 ID와
> 이어 붙이는 키·순서·재시도를 새로 만들어야 한다. LapFinished에 실으면 Outbox(오프라인 보관·멱등·Ack)를 그대로 쓰고 랩과 트레이스가 한 번에 저장된다.

---

## 4. 계약

### 4.1 트랙 (`GET /tracks`, `GET /me/tracks`)

`TrackDto`·`MyTrackDto`에 `countryCode`(string|null, ISO 3166-1 alpha-2 대문자)·`displayOrder`(int)를 더한다.
`GET /tracks`는 `displayOrder` → 이름 순. `GET /me/tracks`는 지금처럼 마지막 주행 순.

F1 25 시드(`DbSeeder`가 매번 맞춘다 — 기존 행의 국가·순서도 시드 값으로 갱신, 이름은 바꾸지 않는다):

| 순서 | ID | 트랙 | 국가 | | 순서 | ID | 트랙 | 국가 |
|---|---|---|---|---|---|---|---|---|
| 1 | 0 | Melbourne | AU | | 17 | 20 | Baku | AZ |
| 2 | 2 | Shanghai | CN | | 18 | 12 | Singapore | SG |
| 3 | 13 | Suzuka | JP | | 19 | 15 | Texas (COTA) | US |
| 4 | 3 | Sakhir | BH | | 20 | 19 | Mexico | MX |
| 5 | 29 | Jeddah | SA | | 21 | 16 | Brazil | BR |
| 6 | 30 | Miami | US | | 22 | 31 | Las Vegas | US |
| 7 | 27 | Imola | IT | | 23 | 32 | Losail | QA |
| 8 | 5 | Monaco | MC | | 24 | 14 | Abu Dhabi | AE |
| 9 | 4 | Catalunya | ES | | 25 | 41 | Zandvoort (Reverse) | NL |
| 10 | 6 | Montreal | CA | | 26 | 40 | Austria (Reverse) | AT |
| 11 | 17 | Austria | AT | | 27 | 39 | Silverstone (Reverse) | GB |
| 12 | 7 | Silverstone | GB | | 28 | 42 | Madrid | ES |
| 13 | 10 | Spa | BE | | 29 | 1 | Paul Ricard | FR |
| 14 | 9 | Hungaroring | HU | | 30 | 8 | Hockenheim | DE |
| 15 | 26 | Zandvoort | NL | | 31 | 28 | Portimão | PT |
| 16 | 11 | Monza | IT | | | | | |

### 4.2 랩 (`GET /me/laps`, 새 `GET /me/laps/{lapId}`, 새 `GET /me/laps/{lapId}/trace`)

`GET /me/laps`: 쿼리 `validOnly`(bool, 기본 false) 추가. `LapDto`에 필드 추가:

```jsonc
{
  "lapId": "…", "trackName": "Jeddah", "gameCode": "F1_25", "sessionType": "TimeTrial",
  "lapTimeMs": 98448, "sectors": [ … ], "isValid": true, "isRankingEligible": true, "setAt": "…",
  // 추가
  "lapNumber": 5,
  "gameMode": "DriverCareer",            // null = 모름(옛 랩)
  "team": { "name": "Ferrari", "color": "#E8002D" },   // null = 스냅샷 없음. TeamCatalog(D-33)로 푼다
  "weather": "Clear",                     // null = 모름
  "hasTrace": true
}
```

`GET /me/laps/{lapId}` → `LapDetailResponse` (남의 랩·없는 랩 = 404, D-34와 같다):

```jsonc
{
  "lap": { /* 위 LapDto */ },
  "trackId": "…", "countryCode": "SA",
  "sessionId": "…",                       // 같은 SessionKey의 내 GameSession이 있으면, 없으면 null
  "car": {                                // null = 스냅샷 없음. 안의 필드도 각각 null 가능
    "visualTyreCompound": 16, "actualTyreCompound": 18, "tyreAgeLaps": 3,
    "tyreWearStart": { "frontLeft": 27.0, "frontRight": 14.0, "rearLeft": 20.0, "rearRight": 14.0 },
    "tyreWearEnd":   { "frontLeft": 31.0, "frontRight": 18.0, "rearLeft": 24.0, "rearRight": 18.0 },
    "tyreDamage":    { … }, "brakeDamage": { … },
    "frontLeftWingDamage": 0, "frontRightWingDamage": 10, "rearWingDamage": 0, "floorDamage": 0,
    "diffuserDamage": 0, "sidepodDamage": 20, "gearboxDamage": 10, "engineDamage": 30,
    "fuelStartKg": 24.4, "fuelEndKg": 22.7, "fuelRemainingLaps": 13.1,
    "ersStoreStartJ": 1494000, "ersStoreEndJ": 988000, "ersDeployedJ": 2100000, "ersHarvestedJ": 1600000
  },
  "conditions": { "weather": "Clear", "airTempC": 21, "trackTempC": 31, "rainForecastPercent": 4 },
  "comparison": {                         // 같은 트랙·게임의 내 최고 유효 랩(이 랩일 수도 있음). 유효 랩이 없으면 null
    "lapId": "…", "lapTimeMs": 97003, "sectors": [ … ], "setAt": "…", "hasTrace": true
  }
}
```

`GET /me/laps/{lapId}/trace` → 트레이스가 없거나 남의 랩이면 404:

```jsonc
{ "lapId": "…", "resolutionM": 5, "sampleCount": 1235,
  "timeMs": [ … ], "speedKph": [ … ], "throttle": [ … ], "brake": [ … ], "steer": [ … ], "gear": [ … ], "rpm": [ … ] }
```

### 4.3 LapFinished (Agent → TelemetryHub) — 선택 필드 3개 추가

`car`(위 `car`와 같은 모양 + `teamId`(int, 게임 팀 ID)), `conditions`(위와 같음), `trace`(`resolutionM` + 위 7개 배열).
모두 선택이다 — 옛 Agent·스냅샷 없는 랩은 보내지 않는다. `shared/schema/lap_finished.json`에 정의한다.

---

## 5. 저장 (Backend)

- `Track`: `CountryCode`(string?, 2자) · `DisplayOrder`(int) 추가. 마이그레이션은 가산적.
- `Lap`: `GameMode`(string?, 페이로드 그대로 — 모르는 값도 저장) 추가.
- **`LapSnapshot`**(새 테이블 `lap_snapshots`, Lap과 1:0..1, `LapId` 유니크): §4.2 `car` + `teamId` + `conditions`를 **평평한 nullable 열**로 둔다
  (바퀴 4개 값은 `TyreWearEndFrontLeft`처럼 열 4개). 목록(TEAM·날씨 열)도 여기서 읽는다.
- **`LapTelemetryTrace`**(새 테이블 `lap_telemetry_traces`, `LapId` 유니크): `ResolutionM` · `SampleCount` · `Payload`(bytea = 7개 배열 JSON을 gzip). D-18 = PostgreSQL bytea.
  보존 기간 = 무기한(개인용, 랩 1개당 약 10~15KB 압축). 랩을 지우는 기능은 아직 없다.
- **검증:** 스냅샷 — 퍼센트 0~100, 기온 −50~80, 연료 0~200kg, ERS 0~10,000,000J, 컴파운드·나이 0~255. 트레이스 — `resolutionM` 1~50,
  배열 7개 모두 있고 길이가 같으며 2~5,000, 값 범위(시간 0~3,600,000 · 속도 0~500 · 스로틀/브레이크 0~100 · 스티어 −100~100 · 기어 −1~9 · RPM 0~25,000).
  **틀리면 그 부분(스냅샷 또는 트레이스)만 버리고 경고 로그 — 랩은 절대 거부하지 않는다**(랩 기록이 본체, 나머지는 덤).
- 같은 이벤트 재전송(멱등)은 기존 `ProcessedEvent`가 막는다 — 스냅샷·트레이스도 랩과 같은 트랜잭션으로 저장한다.

---

## 6. 결정 (D-42~D-48, [08](./08-open-decisions.md) §L)

| ID | 결정 |
|---|---|
| D-42 | 앱은 **Flutter 유지**. F1Laps 모양은 직접 만든 위젯으로 맞춘다(§0) |
| D-43 | 트랙 표시 정보 = 백엔드 `Track.CountryCode`·`DisplayOrder`(시드가 매번 맞춤), 트랙 목록은 캘린더 순서, 국기는 `country_flags` 패키지 |
| D-44 | 랩 스냅샷(팀·타이어·손상·연료·ERS·날씨) = Agent가 랩 끝에 모아 LapFinished `car`·`conditions`로, 백엔드 `lap_snapshots`(평평한 열) |
| D-45 | 트레이스 = 거리 5m 표본·7채널, LapFinished `trace`로(한도 넘으면 10→20m, 그래도 넘으면 뺌), 백엔드 bytea gzip, 보존 무기한. D-17 승인 해석·D-18·D-19를 이것으로 확정 |
| D-46 | 랩 상세 = `/laps/:lapId` 3탭, 비교 대상 = 같은 트랙의 내 최고 유효 랩(랭킹 1위 비교는 이후) |
| D-47 | Laps 화면 = F1Laps 배치(`/laps`는 마지막 트랙, 제목 트랙 메뉴, TEAM·TIME·MODE·날씨·DATE, 행 클릭 → 상세), Leaderboard도 같은 트랙 메뉴 |
| D-48 | 프로필 팀 로고 = `assets/team_logos/{CODE}.png`가 있으면 그린다(파일은 저장소에 넣지 않음), 없으면 D-39의 팀 색 원 |

---

## 7. 테스트 기준

- **Agent:** 매퍼 — 새 패킷 3종 필드·바퀴 순서(RL·RR·FL·FR → 이름), 실제 F1 25 캡처가 있으면 그것으로. 스냅샷 — 시작/끝 값, 값 없음이면 생략.
  트레이스 — 칸 덮어쓰기(플래시백), 음수 거리, 빈 칸 채우기, 50% 미만 생략, 랩 경계에서 비움. 싱크 — 한도 초과 시 10m·20m·트레이스 제거 순서.
- **Backend:** 시드 국가·순서(31개 전부, 기존 행 갱신), `/tracks` 순서, 인입 — 스냅샷·트레이스 저장, 잘못된 스냅샷/트레이스만 버리고 랩 저장,
  `GET /me/laps/{id}`(내 것·남의 것 404·비교 대상·세션 연결), `/trace` 404·복원, `validOnly`. 통합 테스트로 허브 → DB → API 한 바퀴.
- **App:** 트랙 메뉴 순서·국기·선택, Laps 표 열·행 클릭 이동·좁은 화면 열 숨김, 랩 상세 3탭(주소 동기화)·비교 Delta 부호·스냅샷 없음 안내,
  Telemetry 그래프(트레이스 없음 안내, 십자선 값), Best Laps 강조, 팀 로고 있음/없음. 375px 넘침 없음.

---

## 8. 전부 수집 (D-49, 2026-10-18 추가)

> 사용자: "텔레메트리로 가져올 수 있는 건 일단 다 가져오도록 하자. 그걸 어떻게 보여주느냐는 차차 정리하고."

- **원칙:** 플레이어 차와 세션에 대해 F1 25 UDP가 주는 값은 **모두** 랩·세션 단위로 정제해 저장한다(패킷 원본·전 차량 Motion 스트림은 여전히 보내지 않는다 — 헌장).
  화면은 나중에 고른다. 그래서 새 값은 **이름 붙은 묶음**(트레이스 `extra` 채널 맵, 스냅샷 `details` 객체)으로 보내고 저장해, 화면을 만들 때 스키마를 다시 바꾸지 않는다.
- **트레이스 `trace.extra`:** `{ 채널이름: number[] }` — 기존 7개 배열과 같은 길이·같은 거리 칸. Car Telemetry(클러치·DRS·브레이크 온도 4·타이어 표면/내부 온도 4+4·엔진 온도·공기압 4·노면 종류 4),
  Car Status(ERS 배포 모드·저장량·연료 믹스 등 랩 중 바뀌는 값), Motion(플레이어: 월드 위치 X/Y/Z·G-force 3축·요/피치/롤), Motion Ex(휠 속도·슬립 비/각 4·서스펜션 위치 4·앞뒤 에어로 높이·로컬 속도 등).
  채널 목록·단위는 `shared/telemetry/f1_25_udp_spec.md`의 카탈로그가 진실 원천이다. 값은 유한 숫자(소수 둘째 자리까지).
- **스냅샷 `car.details` (JSON 객체):** 셋업(Car Setups 5), 엔진 부품 마모·고장·블리스터(Car Damage 10 나머지), Car Status 나머지(TC·ABS·브레이크 바이어스·피트 리미터 등), 타이어 세트(12),
  타임 트라이얼(14), 그 랩 동안의 이벤트 목록(Event 3: 패널티·충돌·플래시백·최고 랩·추월·세이프티카 등, 랩 시작 기준 시각).
- **세션 `SessionClassified`:** 전 차량 랩별 기록(Session History 11 — 랩타임·섹터·유효 플래그)과 랩별 순위(Lap Positions 15)를 선택 필드로 더한다(P8 세션 상세의 재료).
- **한도:** 봉투 한도를 Agent 768KiB / 허브 1MiB로 올린다(D-35 계열 값 갱신). 넘으면 지금처럼 트레이스 해상도 10m → 20m → 트레이스 제거.
- **백엔드:** `extra`는 트레이스 blob 안에 같이 넣고 `/trace` 응답에 `extra` 맵으로 돌려준다. `details`는 `lap_snapshots.details`(jsonb)에 그대로, 세션 쪽 추가분도 jsonb로 저장한다.
  검증은 구조·크기만(객체 여부, 채널 이름 `^[A-Za-z0-9]{1,40}$`, 채널 수 ≤ 150, 길이 일치, 유한 숫자) — 틀리면 그 부분만 버린다.
