# F1 25 UDP Telemetry Specification (MVP)

> ⚠️ **역할 전환 (D-20, 2026-07-07):** 바이트 파싱은 NuGet **F1Game.UDP(25.1.1, D-41)**에 위임한다.
> 따라서 이 문서의 **오프셋 표는 더 이상 구현 계약이 아니라 참고/이해용**이다(값이 어긋나면 라이브러리가 정답).
> 유지되는 것은 **도메인 이벤트 의미론**(어떤 패킷/필드가 세션·랩·섹터·완주 판정에 쓰이는지)이다.
> 신규 오프셋을 손으로 관리하지 말 것 — 상세: [08-open-decisions.md#D-20](../../docs/08-open-decisions.md).
>
> **참조용 스펙 문서**
> F1 25 게임에서 송출되는 UDP Telemetry 패킷 중, **SimCenter MVP의 랩타임 측정 및 랭킹 정립**에 필요한 핵심 패킷 3종에 대한 세부 바이트 구조와 오프셋을 명세합니다.
> 랩 상세(차량 스냅샷·텔레메트리 트레이스, [docs/15](../../docs/15-lap-detail-telemetry.md) §3, D-44·D-45)에 새로 쓰는 패킷·필드는 **§5**에 모았습니다.
> "전부 수집"([docs/15](../../docs/15-lap-detail-telemetry.md) §8, D-49)의 **트레이스 extra 채널 카탈로그는 §6, 스냅샷 `car.details` 키는 §7, 순위표 랩 기록은 §8** — 이 세 표가 진실 원천이다.
> 모든 데이터는 **Little Endian**으로 패킹되어 있습니다.

---

## 1. Packet Header (공통 헤더 — 29 Bytes)

모든 UDP 패킷은 항상 아래의 `PacketHeader`로 시작합니다.

| Offset (Byte) | Type | Name | Description |
|---|---|---|---|
| 0 | uint16 | `m_packetFormat` | 게임 연식 (F1 25의 경우 `2025` 값 확인 필수) |
| 2 | uint8 | `m_gameMajorVersion` | 게임 메이저 버전 |
| 3 | uint8 | `m_gameMinorVersion` | 게임 마이너 버전 |
| 4 | uint8 | `m_packetVersion` | 패킷 버전 (일반적으로 `1`) |
| 5 | uint8 | `m_packetId` | 패킷 종류 식별자 (아래 참조) |
| 6 | uint64 | `m_sessionUID` | 현재 게임 세션의 고유 식별자 (`sessionRef`로 사용) |
| 14 | float | `m_sessionTime` | 세션 경과 시간 (단위: 초) |
| 18 | uint32 | `m_frameIdentifier` | 프레임 식별자 (일시정지 시 증가하지 않음) |
| 22 | uint32 | `m_overallFrameIdentifier` | 게임 전체 프레임 식별자 |
| 26 | uint8 | `m_playerCarIndex` | 플레이어의 차량 배열 인덱스 (이 인덱스의 데이터만 파싱) |
| 27 | uint8 | `m_secondaryPlayerCarIndex` | 2인용 화면인 경우 보조 플레이어 차량 인덱스 (MVP는 무시) |
| 28 | uint8 | `m_yourTelemetryButtonState` | 텔레메트리 버튼 상태 |

### Packet ID 목록
- `1`: **Session Packet** (세션 환경, 트랙 및 세션 타입 확인 · 날씨·기온·비 예보 — §5.1)
- `2`: **Lap Data Packet** (플레이어의 현재 주행 랩 수치 및 시간 · 랩 거리 — §5.2)
- `3`: **Event Packet** (세션 시작/종료 등의 마커 수신)
- `4`: **Participants Packet** (참가자 이름·팀 — 순위표 [docs/12](../../docs/12-seasons-sessions.md) §5.2, 스냅샷 팀 §5.6)
- `6`: **Car Telemetry Packet** (속도·페달·스티어·기어·RPM — 트레이스 §5.3)
- `7`: **Car Status Packet** (연료·ERS·타이어 컴파운드·나이 — 스냅샷 §5.4)
- `8`: **Final Classification Packet** (세션 최종 순위표 — [docs/12](../../docs/12-seasons-sessions.md) §5.2)
- `10`: **Car Damage Packet** (타이어 마모·손상, 날개·차체 손상 — 스냅샷 §5.5)
- `0`·`5`·`11`·`12`·`13`·`14`·`15`: **Motion · Car Setups · Session History · Tyre Sets · Motion Ex · Time Trial · Lap Positions** — "전부 수집"(D-49):
  트레이스 `extra`(§6) · 스냅샷 `details`(§7) · 순위표 랩 기록(§8). 읽지 않는 것은 `9`(Lobby Info)와 다른 차의 Motion뿐이다.

---

## 2. Packet ID 1: Session Packet (세션 스펙)

게임 세션 정보(트랙 코드, 세션 종류)를 파악하기 위한 패킷입니다. 

* **전체 크기:** 662 Bytes (F1 25 규격 기준)
* **주요 오프셋:**

| Offset (Byte) | Type | Name | Description |
|---|---|---|---|
| 0 | 29 Bytes | `m_header` | 공통 패킷 헤더 |
| 29 | uint8 | `m_weather` | 날씨 상태 (0: 맑음, 1: 흐림, 2: 비 등) |
| 30 | int8 | `m_trackTemperature` | 노면 온도 (섭씨) |
| 31 | int8 | `m_airTemperature` | 기온 (섭씨) |
| 32 | uint8 | `m_totalLaps` | 세션 총 랩 수 (Time Trial의 경우 무제한) |
| 33 | uint16 | `m_trackLength` | 트랙 길이 (단위: 미터) |
| 35 | uint8 | `m_sessionType` | **세션 종류** (중요: `19`가 Time Trial) <br> - 0: 알 수 없음, 1: P1, 2: P2, 3: P3, 4: Short P, 5: Q1, 6: Q2, 7: Q3, 8: Short Q, 9: OSQ, 10: R, 11: R2, 12: R3, 13: Time Trial (F1 25: `19` 확인 요망) |
| 36 | int8 | `m_trackId` | **트랙 ID** (-1: 알 수 없음, 0: Melbourne, 1: Paul Ricard, 2: Silverstone 등) |
| 37 | uint8 | `m_formula` | 포뮬러 종류 (0: F1 Modern, 1: F1 Classic, 2: F2 등) |
| 38 | uint16 | `m_sessionTimeLeft` | 남은 세션 시간 (초) |
| 40 | uint16 | `m_sessionDuration` | 세션 총 제한 시간 (초) |

---

## 3. Packet ID 2: Lap Data Packet (랩 데이터 스펙)

참가 중인 모든 차량(최대 22대)의 현재 랩타임, 섹터 시간, 랩 번호 등을 배열 형태로 담고 있습니다. 헤더의 `m_playerCarIndex`를 사용하여 플레이어 차량의 정보만 참조합니다.

* **전체 크기:** 1279 Bytes
* **구조:** 공통 헤더(29B) + 22대 차량의 `LapData` 구조체 배열 (각 56바이트 내외) + 기타 타임 정보
* **단일 `LapData` 구조체 세부 레이아웃 (차량별 오프셋):**

| Offset (Byte) | Type | Name | Description |
|---|---|---|---|
| 0 | uint32 | `m_lastLapTimeInMS` | 직전 완료한 랩 타임 (밀리초) |
| 4 | uint32 | `m_currentLapTimeInMS` | 현재 주행 중인 랩 경과 시간 (밀리초) |
| 8 | uint16 | `m_sector1TimeInMS` | 섹터 1 기록 (밀리초) |
| 10 | uint8 | `m_sector1TimeMinutes` | 섹터 1 기록 (분 단위) |
| 11 | uint16 | `m_sector2TimeInMS` | 섹터 2 기록 (밀리초) |
| 13 | uint8 | `m_sector2TimeMinutes` | 섹터 2 기록 (분 단위) |
| 14 | uint16 | `m_deltaToCarInFrontInMS` | 앞 차와의 차이 (밀리초) |
| 16 | uint16 | `m_deltaToPersonalBestInMS`| 개인 베스트 랩과의 차이 (밀리초) |
| 18 | float | `m_lapDistance` | 현재 랩에서 주행한 거리 (미터 단위) |
| 22 | float | `m_totalDistance` | 세션 전체 주행 거리 (미터 단위) |
| 26 | float | `m_safetyCarDelta` | 세이프티 카 델타 타임 |
| 30 | uint8 | `m_carPosition` | 현재 그리드/레이스 순위 (1~22) |
| 31 | uint8 | `m_currentLapNum` | **현재 랩 번호** (1-base) |
| 32 | uint8 | `m_pitStatus` | 피트 상태 (0: 피트없음, 1: 피팅인, 2: 피팅아웃) |
| 33 | uint8 | `m_numPitStops` | 피트 스톱 횟수 |
| 34 | uint8 | `m_sector` | **현재 섹터 번호** (0: Sector1, 1: Sector2, 2: Sector3) |
| 35 | uint8 | `m_currentLapInvalid` | **현재 랩 무효 플래그** (0: 유효, 1: 무효) |
| 36 | uint8 | `m_penalties` | 누적 페널티 시간 (초) |
| 37 | uint8 | `m_totalWarnings` | 누적 경고 횟수 |
| 38 | uint8 | `m_cornerWarnings` | 코너 컷팅 경고 횟수 |
| 39 | uint8 | `m_numUnservedDriveThroughPens`| 수행하지 않은 드라이브 스루 페널티 수 |
| 40 | uint8 | `m_numUnservedStopGoPens` | 수행하지 않은 스톱 앤 고 페널티 수 |
| 41 | uint8 | `m_gridPosition` | 출발 그리드 순위 |
| 42 | uint8 | `m_driverStatus` | 드라이버 상태 (0: in garage, 1: flying lap, 2: in lap, 3: out lap, 4: on track) |
| 43 | uint8 | `m_resultStatus` | 결과 상태 (0: invalid, 2: active, 3: finished, 4: did not finish 등) |
| 44 | uint8 | `m_pitLaneTimerActive` | 피트 레인 타이머 활성화 여부 |
| 45 | uint16 | `m_pitLaneTimeInLaneInMS` | 피트 레인 체류 시간 (밀리초) |
| 47 | uint16 | `m_pitStopDurationInMS` | 피트 스톱 시간 (밀리초) |
| 49 | uint8 | `m_pitStopShouldServePen` | 페널티 수행 여부 |

---

## 4. Packet ID 3: Event Packet (이벤트 스펙)

게임 내부의 결정적 이벤트를 알리는 메타 패킷입니다. 세션 시작(`SSTA`) 및 세션 종료(`SEND`) 마커를 감지하는 목적으로 사용합니다.

* **전체 크기:** 45 Bytes
* **주요 오프셋:**

| Offset (Byte) | Type | Name | Description |
|---|---|---|---|
| 0 | 29 Bytes | `m_header` | 공통 패킷 헤더 |
| 29 | char[4] | `m_eventStringCode` | 4자리의 이벤트 문자열 코드 (ASCII) |
| 33 | EventDetails | `m_eventDetails` | 이벤트 타입별 상세 유니온 데이터 (SSTA, SEND의 경우 세부 데이터 없음) |

### 관심 이벤트 코드 (m_eventStringCode)
- `"SSTA"`: **Session Started** (세션 주행 시작됨)
- `"SEND"`: **Session Ended** (세션이 공식적으로 종료됨)

---

## 5. 랩 상세용 패킷·필드 (docs/15 §3, D-44·D-45)

> F1Game.UDP 25.1.1의 이름으로 적는다(라이브러리가 정답). 패킷 크기는 F1 25 규격(`F1WireLayoutTests.PacketReader_ParsesF125SpecSize`),
> 차 1대 구조체 안의 오프셋은 `F1WireLayoutTests`가 바이트로 고정한 것만 적는다. 차마다 칸이 있는 패킷은 **22칸**이고 헤더의 `m_playerCarIndex` 칸만 읽는다
> (칸 수를 넘으면 = 관전 중 등 → 버리고 한 번만 경고). Raw 패킷은 서버로 보내지 않는다 — Agent가 랩 끝에 정제한 값만 LapFinished `car`·`conditions`·`trace`로 간다.

**바퀴 배열 순서:** UDP의 바퀴 4개 배열은 **RL · RR · FL · FR** 순서다. 라이브러리 `Tyres<T>`가 이 순서를 `RearLeft`·`RearRight`·`FrontLeft`·`FrontRight` 이름으로 풀고,
매퍼는 이름으로 게임 중립 `WheelSet(FrontLeft, FrontRight, RearLeft, RearRight)`에 옮긴다(순서로 옮기지 않는다).

### 5.1 Session (1) — `conditions`

| 필드 | 형 | 쓰임 |
|---|---|---|
| `Weather` | uint8 enum | 0 Clear · 1 LightCloud · 2 Overcast · 3 LightRain · 4 HeavyRain · 5 Storm. 그 밖 = null |
| `AirTemperature` · `TrackTemperature` | int8 | 기온·노면 온도(섭씨) |
| `TrackLength` | uint16 | 트랙 길이(m) — 프레임에만 싣는다(참고값) |
| `NumWeatherForecastSamples` · `WeatherForecastSamples[64]` | uint8 · 샘플 64칸 | 샘플 = `SessionType` · `TimeOffset`(분) · `Weather` · 온도 · `RainPercentage`(0~100). 개수를 넘는 칸은 쓰레기라 보지 않는다 |

**비 예보(`rainForecastPercent`):** 현재 `SessionType`과 같은 샘플 중 `TimeOffset > 0`인 가장 이른 샘플의 `RainPercentage`.
없으면 그 세션 종류의 첫 샘플, 그것도 없으면 null. (실제 Time Trial 캡처는 샘플이 0개 → null.)

### 5.2 Lap Data (2) — 트레이스 거리·시간

| 필드 | 형 | 쓰임 |
|---|---|---|
| `LapDistance` | float | 이번 랩 거리(m). 출발선 전이면 음수 → 트레이스가 버린다 |
| `CurrentLapTimeInMS` | uint32 | 이번 랩 경과 ms → 트레이스 `timeMs` |

랩 번호가 바뀌는 순간의 실제 캡처에서 시간은 0으로 돌아갔지만 거리는 아직 앞 랩 값이었다 — 트레이스는 칸 덮어쓰기라 새 랩에서 그 거리를 다시 지나며 고쳐진다.

### 5.3 Car Telemetry (6) — 트레이스 (1,352 B, 차 1대 60 B)

| 오프셋(차 안) | 필드 | 형 | 쓰임 |
|---|---|---|---|
| 0 | `Speed` | uint16 | km/h → `speedKph`(0~500) |
| 2 | `Throttle` | float 0~1 | × 100 → `throttle`(0~100) |
| 6 | `Steer` | float −1~1 | × 100 → `steer`(−100~100) |
| 10 | `Brake` | float 0~1 | × 100 → `brake`(0~100) |
| 15 | `Gear` | int8 | −1 = R, 0 = N, 1~8 → `gear` |
| 16 | `EngineRPM` | uint16 | → `rpm`(0~25,000) |

**표본 규칙(D-45):** Car Telemetry마다 가장 최근 Lap Data의 거리로 칸 `floor(거리 / 5m)`에 덮어쓴다. 랩이 바뀌면 LapFinished에 싣고 비운다.
길이 = 채워진 마지막 칸 + 1, 빈 칸은 앞 값(맨 앞은 첫 값)으로 채우고, 채워진 칸이 50% 미만이면 보내지 않는다. 값은 검증 범위로 다듬는다.

### 5.4 Car Status (7) — 스냅샷 연료·ERS·타이어 (1,239 B, 차 1대 55 B)

| 오프셋(차 안) | 필드 | 형 | 쓰임 |
|---|---|---|---|
| 5 | `FuelInTank` | float | kg → `fuelStartKg`·`fuelEndKg` |
| 13 | `FuelRemainingLaps` | float | MFD 값(음수 가능) → `fuelRemainingLaps` |
| 25 | `ActualTyreCompound` | uint8 | 원시 값 → `actualTyreCompound`(16=C5 … 20=C1, 21=C0, 22=C6, 7 Inter, 8 Wet) |
| 26 | `VisualTyreCompound` | uint8 | 원시 값 → `visualTyreCompound`(16 Soft, 17 Medium, 18 Hard, 7 Inter, 8 Wet) |
| 27 | `TyresAgeLaps` | uint8 | → `tyreAgeLaps` |
| 37 | `ErsStoreEnergy` | float | J(최대 4 MJ) → `ersStoreStartJ`·`ersStoreEndJ`(정수 J) |
| 42 · 46 | `ErsHarvestedThisLapMGUK` · `ErsHarvestedThisLapMGUH` | float | 합 → `ersHarvestedJ` |
| 50 | `ErsDeployedThisLap` | float | → `ersDeployedJ`. "이 랩" 값은 게임이 랩마다 0으로 되돌린다 |

### 5.5 Car Damage (10) — 스냅샷 마모·손상 (1,041 B, 차 1대 46 B)

| 오프셋(차 안) | 필드 | 형 | 쓰임 |
|---|---|---|---|
| 0 | `TyresWear[4]` | float × 4 (RL·RR·FL·FR) | % → `tyreWearStart`·`tyreWearEnd`(0~100으로 다듬음) |
| 16 | `TyresDamage[4]` | uint8 × 4 | % → `tyreDamage` |
| 20 | `BrakesDamage[4]` | uint8 × 4 | % → `brakeDamage` |
| 24 | `TyresBlisters[4]` | uint8 × 4 | `details.damage.tyreBlisters{FL…RR}`(D-49, §7) |
| 28 ~ 33 | `FrontLeftWingDamage` · `FrontRightWingDamage` · `RearWingDamage` · `FloorDamage` · `DiffuserDamage` · `SidepodDamage` | uint8 | % → 같은 이름의 `…Damage` |
| 36 · 37 | `GearBoxDamage` · `EngineDamage` | uint8 | % → `gearboxDamage` · `engineDamage` |

### 5.6 Participants (4) — 스냅샷 팀

헤더 `m_playerCarIndex` 칸의 `Team` → `teamId`(게임 원시 팀 ID). 플레이어 칸이 없으면(관전 등) null.

### 5.7 스냅샷 끝 값·시작 값 (D-44)

- **끝 값** = 이번 랩 동안 마지막으로 받은 Car Status·Car Damage(랩 번호가 바뀌는 Lap Data 직전). 팀·조건은 랩을 넘어 최신 값을 쓴다.
- **시작 값**(연료·ERS 저장량·타이어 마모) = 랩이 바뀐 뒤 처음 받은 값. 세션에서 처음 본 랩은 `CurrentLapTimeInMS` ≤ 1초일 때만 받는다
  (그보다 늦으면 Agent가 랩 중간에 시작한 것 → 시작 값 생략).
- 랩이 바뀌는 프레임에서 Lap Data(2)가 Car Status(7)보다 먼저 온다고 본다(게임은 한 프레임의 패킷을 대체로 ID 순서로 보낸다 — 실제 캡처로는 확인하지 못함).
  그래야 "이 랩" ERS가 0으로 되돌아간 Car Status가 새 랩의 시작 값이 되고 앞 랩의 끝 값을 덮지 않는다.

---

## 6. 트레이스 `extra` 채널 카탈로그 (D-49, docs/15 §8)

> 구현: `agent/src/SimCenter.Agent.Infrastructure/Mapping/F1ExtraChannels.cs`(채널 하나 = 한 줄). 이 표와 코드가 어긋나면 고친다 —
> `F1ExtraChannelsWireTests.AllExtraChannels_HaveValidNames_AndFitTheLimit`가 채널 수(**118**)를 고정한다.

**공통 규칙**
- `trace.extra = { 이름: number[] }` — 기본 7채널과 **같은 칸·같은 길이**. 칸에는 그 칸의 Car Telemetry 표본을 쓰는 순간의 각 채널 **최신 값**을 찍는다(덮어쓰기·플래시백 규칙 동일).
  Car Telemetry 패킷은 extra를 먼저 내 같은 패킷의 값이 같은 칸에 들어간다. 다른 패킷(Status·Motion·Motion Ex·Lap Data) 채널은 칸을 쓸 때까지 받은 최신 값이다.
- 빈 칸 = 앞 값, 맨 앞 = 첫 값. 랩 동안 값이 한 번도 없던 채널은 빠진다. 최신 값은 랩을 넘어 이어지고 세션이 바뀌면 잊는다.
- 값은 **유한 숫자**(NaN·±∞는 버리고 앞 값 유지), **소수 둘째 자리** 반올림(표의 "소수"가 더 작으면 그만큼). 불리언은 0/1, 열거형은 게임 원시 정수.
- 이름 `^[A-Za-z0-9]{1,40}$`, 채널 ≤ 150(Core `TraceExtraChannels`가 넘는 새 채널을 버린다). 바퀴 4개는 접미사 `FL·FR·RL·RR`(UDP 배열 RL·RR·FL·FR을 이름으로 옮김 — 테스트로 고정).
- 크기: Spa 1랩 5m(1,401칸) × 125채널 + 상세 ≈ **891KB** → 한도(768KiB) 초과라 **10m(≈459KB)**로 낮춰 보낸다(`OutboxTelemetrySinkCollectAllSizeTests`). 5km 안팎 트랙은 5m 그대로 들어간다.

**Car Telemetry (6) — 25채널**

| 채널 | 원천 필드 | 단위 | 소수 |
|---|---|---|---|
| `clutch` | `Clutch` | % (0~100) | 0 |
| `drs` | `IsDrsOn` | 0/1 | 0 |
| `revLightsPercent` | `RevLightsPercent` | % | 0 |
| `brakeTemp{FL,FR,RL,RR}` | `BrakesTemperature[4]` | °C | 0 |
| `tyreSurfaceTemp{FL,FR,RL,RR}` | `TyresSurfaceTemperature[4]` | °C | 0 |
| `tyreInnerTemp{FL,FR,RL,RR}` | `TyresInnerTemperature[4]` | °C | 0 |
| `engineTemp` | `EngineTemperature` | °C | 0 |
| `tyrePressure{FL,FR,RL,RR}` | `TyresPressure[4]` | PSI | 2 |
| `surfaceType{FL,FR,RL,RR}` | `SurfaceType[4]` | 열거(0 Tarmac·1 Rumble·2 Concrete·3 Rock·4 Gravel·5 Mud·6 Sand·7 Grass·8 Water·9 Cobble·10 Metal·11 Ridged) | 0 |
| `suggestedGear` | 패킷 `SuggestedGear` | 기어(0 = 없음) | 0 |

**Car Status (7) — 16채널** (랩 중 바뀌는 값. 연료·ERS 시작/끝 값은 `car` 본체에도 있다)

| 채널 | 원천 필드 | 단위 | 소수 |
|---|---|---|---|
| `tractionControl` | `TractionControl` | 0 Off · 1 Medium · 2 Full | 0 |
| `antiLockBrakes` | `AntiLockBrakes` | 0/1 | 0 |
| `fuelMix` | `FuelMix` | 0 Lean · 1 Standard · 2 Rich · 3 Max | 0 |
| `frontBrakeBias` | `FrontBrakeBias` | % | 0 |
| `pitLimiter` | `IsPitLimiterOn` | 0/1 | 0 |
| `fuelInTank` | `FuelInTank` | kg | 2 |
| `fuelRemainingLaps` | `FuelRemainingLaps` | 랩(MFD, 음수 가능) | 2 |
| `drsAllowed` | `DrsAllowed` | 0/1 | 0 |
| `vehicleFiaFlag` | `VehicleFiaFlags` | −1 모름 · 0 없음 · 1 Green · 2 Blue · 3 Yellow | 0 |
| `enginePowerIce` · `enginePowerMguk` | `EnginePowerICE` · `EnginePowerMGUK` | W | 0 |
| `ersStoreEnergy` | `ErsStoreEnergy` | J | 0 |
| `ersDeployMode` | `ErsDeployMode` | 0 None · 1 Medium · 2 Hotlap · 3 Overtake | 0 |
| `ersHarvestedThisLapMguk` · `ersHarvestedThisLapMguh` | `ErsHarvestedThisLapMGUK` · `…MGUH` | J(랩마다 0으로) | 0 |
| `ersDeployedThisLap` | `ErsDeployedThisLap` | J(랩마다 0으로) | 0 |

**Motion (0) 플레이어 칸 — 12채널** (다른 차 칸은 읽지 않는다)

| 채널 | 원천 필드 | 단위 | 소수 |
|---|---|---|---|
| `worldPosX` · `worldPosY` · `worldPosZ` | `WorldPosition{X,Y,Z}` | m(월드 좌표 — 트랙 지도) | 1 |
| `worldVelX` · `worldVelY` · `worldVelZ` | `WorldVelocity{X,Y,Z}` | m/s | 2 |
| `gForceLateral` · `gForceLongitudinal` · `gForceVertical` | `GForce{Lateral,Longitudinal,Vertical}` | G | 2 |
| `yawDeg` · `pitchDeg` · `rollDeg` | `Yaw` · `Pitch` · `Roll` | ° (rad × 180/π) | 2 |

**Motion Ex (13, 플레이어 전용) — 61채널**

| 채널 | 원천 필드 | 단위 | 소수 |
|---|---|---|---|
| `suspensionPosition{FL,FR,RL,RR}` | `SuspensionPosition[4]` | 게임 단위(mm 추정) | 2 |
| `suspensionVelocity{…}` | `SuspensionVelocity[4]` | 게임 단위/s | 2 |
| `suspensionAcceleration{…}` | `SuspensionAcceleration[4]` | 게임 단위/s² | 0 |
| `wheelSpeed{…}` | `WheelSpeed[4]` | m/s | 2 |
| `wheelSlipRatioPct{…}` | `WheelSlipRatio[4]` | % (비 × 100) | 2 |
| `wheelSlipAngleDeg{…}` | `WheelSlipAngle[4]` | ° | 2 |
| `wheelLatForce{…}` · `wheelLongForce{…}` · `wheelVertForce{…}` | `WheelLateralForce[4]` · `WheelLongitudinalForce[4]` · `WheelVerticalForce[4]` | N | 0 |
| `wheelCamberDeg{…}` · `wheelCamberGainDeg{…}` | `WheelsCamper[4]` · `WheelsCamperGain[4]`(라이브러리 철자) | ° | 2 |
| `heightOfCogMm` | `HeightOfCOGAboveGround` | mm (m × 1000) | 1 |
| `localVelX` · `localVelY` · `localVelZ` | `LocalVelocity{X,Y,Z}` | m/s | 2 |
| `angularVelX` · `angularVelY` · `angularVelZ` | `AngularVelocity{X,Y,Z}` | rad/s | 2 |
| `angularAccX` · `angularAccY` · `angularAccZ` | `AngularAcceleration{X,Y,Z}` | rad/s² | 2 |
| `frontWheelsAngleDeg` | `FrontWheelsAngle` | ° | 2 |
| `frontAeroHeightMm` · `rearAeroHeightMm` | `FrontAeroHeight` · `RearAeroHeight` | mm | 1 |
| `frontRollAngleDeg` · `rearRollAngleDeg` | `FrontRollAngle` · `RearRollAngle` | ° | 2 |
| `chassisYawDeg` · `chassisPitchDeg` | `ChassisYaw` · `ChassisPitch` | ° | 2 |

**Lap Data (2) 플레이어 칸 — 4채널**

| 채널 | 원천 필드 | 단위 | 소수 |
|---|---|---|---|
| `carPosition` | `CarPosition` | 순위 | 0 |
| `deltaToCarInFrontMs` | `DeltaToCarInFront{Minutes,InMS}` | ms(분 합산) | 0 |
| `deltaToRaceLeaderMs` | `DeltaToRaceLeader{Minutes,InMS}` | ms | 0 |
| `safetyCarDelta` | `SafetyCarDelta` | s | 2 |

**넣지 않은 값:** `RevLightsBitValue`(퍼센트와 중복), Motion `WorldForwardDir`·`WorldRightDir`(요·피치·롤과 중복), MFD 패널 상태(화면 상태).

---

## 7. 스냅샷 `car.details` 키 (D-49, docs/15 §8)

> 구현: `Mapping/F1DetailSections.cs`·`F1SessionDetails.cs`·`F1GameEvents.cs`, 조립·다듬기는 Core `LapDetailsTracker`·`DetailValues`.

**공통 규칙:** 묶음마다 **가장 최근 값**(랩을 넘어 유지 — 셋업·타이어 세트·타임 트라이얼은 랩마다 오지 않는다, 세션이 바뀌면 잊는다). 받은 묶음만 실린다.
값은 숫자·불리언·문자열·null·그런 값의 객체/배열, 열거형은 **게임 원시 정수**(뜻은 F1 25 UDP 스펙), 실수는 소수 **셋째 자리**, 유한하지 않으면 null.
바퀴 4개는 접미사 `FL·FR·RL·RR`. 묶음을 하나도 못 받았으면 `details` = null. 봉투 한도를 트레이스 없이도 넘으면 `details`를 뺀다.

| 키 | 원천 | 내용 |
|---|---|---|
| `setup` | Car Setups(5) 플레이어 칸 | `frontWing` `rearWing` `onThrottle` `offThrottle` `frontCamber` `rearCamber` `frontToe` `rearToe`(°) `frontSuspension` `rearSuspension` `frontAntiRollBar` `rearAntiRollBar` `frontSuspensionHeight` `rearSuspensionHeight` `brakePressure` `brakeBias` `engineBraking`(%) `tyrePressure{FL…RR}`(PSI) `ballast` `fuelLoad`(kg) `nextFrontWingValue`(패킷) |
| `damage` | Car Damage(10) 나머지 | `tyreBlisters{FL…RR}`(%) `drsFault` `ersFault` `engineMguhWear` `engineEsWear` `engineCeWear` `engineIceWear` `engineMgukWear` `engineTcWear`(%) `engineBlown` `engineSeized` |
| `status` | Car Status(7) 나머지 | `tractionControl` `antiLockBrakes` `fuelMix` `frontBrakeBias` `pitLimiter` `fuelCapacity`(kg) `maxRpm` `idleRpm` `maxGears` `drsAllowed` `drsActivationDistance`(m, 0 = 못 씀) `vehicleFiaFlag` `enginePowerIce` `enginePowerMguk`(W) `ersDeployMode` `networkPaused` |
| `tyreSets` | Tyre Sets(12), `CarIndex` = 플레이어일 때만 | `fittedIndex`, `sets[20]` = { `actualCompound` `visualCompound` `wearPercent` `available` `recommendedSession` `lifeSpanLaps` `usableLifeLaps` `lapDeltaTimeMs`(지금 세트 대비) `fitted` } |
| `timeTrial` | Time Trial(14) | `playerSessionBest` · `personalBest` · `rival` = { `carIndex` `teamId` `lapTimeMs` `sector1TimeMs` `sector2TimeMs` `sector3TimeMs` `tractionControl` `gearboxAssist` `antiLockBrakes` `equalCarPerformance` `customSetup` `valid` } |
| `session` | Session(1) 전체 | `trackId` `sessionType` `formula` `weather` `trackTemperature` `airTemperature` `totalLaps` `trackLength` `sessionTimeLeftS` `sessionDurationS` `pitSpeedLimitKph` `gamePaused` `spectating` `spectatorCarIndex` `sliProNativeSupport` `marshalZones[]`={`zoneStart`(랩 비율) `zoneFlag`} `safetyCarStatus` `networkGame` `forecastAccuracy` `weatherForecast[]`={`sessionType` `timeOffsetMin` `weather` `trackTemperature` `trackTemperatureChange` `airTemperature` `airTemperatureChange` `rainPercentage`} `aiDifficulty` `pitStopWindowIdealLap` `pitStopWindowLatestLap` `pitStopRejoinPosition` `steeringAssist` `brakingAssist` `gearboxAssist` `pitAssist` `pitReleaseAssist` `ersAssist` `drsAssist` `dynamicRacingLine` `dynamicRacingLineType` `gameMode` `ruleSet` `timeOfDayMin` `sessionLength` `speedUnits` `temperatureUnits` `numSafetyCarPeriods` `numVirtualSafetyCarPeriods` `numRedFlagPeriods` `equalCarPerformance` `recoveryMode` `flashbackLimit` `surfaceType` `lowFuelMode` `raceStarts` `tyreTemperature` `pitLaneTyreSim` `carDamage` `carDamageRate` `collisions` `collisionsOffForFirstLapOnly` `unsafePitRelease` `collisionsOffForGriefing` `cornerCuttingStringency` `parcFermeRules` `pitStopExperience` `safetyCar` `safetyCarExperience` `formationLap` `formationLapExperience` `redFlags` `affectsLicenceLevelSolo` `affectsLicenceLevelMp` `weekendStructure[]`(세션 종류) `sector2LapDistanceStart` `sector3LapDistanceStart`(m). 배열은 개수 칸까지만 |
| `participant` | Participants(4) 플레이어 칸(관전 중이면 없음) | `carIndex` `aiControlled` `driverId`(255 = 네트워크 사람) `networkId` `teamId` `myTeam` `raceNumber` `nationality` `name` `telemetryPublic` `showOnlineNames` `techLevel` `platform` (리버리 색은 넣지 않음) |
| `lapData` | Lap Data(2) 플레이어 칸 나머지 — 랩이 바뀌기 직전 값 | `carIndex`(이벤트의 차 번호와 맞춰 읽는 플레이어 번호) `lapDistance` `totalDistance` `carPosition` `currentLapNum` `pitStatus` `numPitStops` `sector` `currentLapInvalid` `penaltiesS` `totalWarnings` `cornerCuttingWarnings` `numUnservedDriveThroughPens` `numUnservedStopGoPens` `gridPosition` `driverStatus` `resultStatus` `pitLaneTimerActive` `pitLaneTimeInLaneMs` `pitStopTimerMs` `pitStopShouldServePen` `speedTrapFastestSpeedKph` `speedTrapFastestLap`(255 = 없음) `timeTrialPbCarIndex` `timeTrialRivalCarIndex`(패킷) |
| `events[]` | Event(3) — 그 랩 동안 받은 순서, 랩마다 비움, 최대 200 | `{ code, lapTimeMs(받은 순간 랩 경과), details }` — 아래 표. 다른 묶음이 있으면 이벤트가 없어도 `[]` |
| `droppedEvents` | — | 200개를 넘어 버린 이벤트 수(있을 때만) |
| `sessionHistory` | Session History(11) 플레이어의 이 랩 칸 | §8 `lapHistoryEntry`. 랩 끝 순간 값이라 `lapTimeMs`·`sector3TimeMs`가 0일 수 있다(세션 전체는 §8) |

**이벤트 `details` (차 번호 = 원시 carIndex, 시간 = ms 정수)**

| 코드 | 뜻 | details |
|---|---|---|
| `PENA` | 패널티 | `penaltyType` `infringementType` `vehicleIndex` `otherVehicleIndex` `timeS` `lapNumber` `placesGained` |
| `FTLP` | 최고 랩 | `vehicleIndex` `lapTimeMs` |
| `RTMT` | 리타이어 | `vehicleIndex` `reason` |
| `DRSD` · `DRSE` | DRS 꺼짐 · 켜짐 | `reason`(DRSD만) |
| `TMPT` | 팀 동료 피트 | `vehicleIndex` |
| `RCWN` | 레이스 우승 | `vehicleIndex` |
| `SPTP` | 스피드 트랩 | `vehicleIndex` `speedKph` `overallFastestInSession` `driverFastestInSession` `fastestVehicleIndexInSession` `fastestSpeedInSessionKph` |
| `STLG` · `LGOT` | 출발 신호등 · 소등 | `numLights`(STLG만) |
| `DTSV` · `SGSV` | 드라이브 스루 · 스톱 앤 고 수행 | `vehicleIndex`, `stopTimeMs`(SGSV) |
| `FLBK` | 플래시백 | `flashbackFrameIdentifier` `flashbackSessionTimeMs` |
| `OVTK` | 추월 | `overtakingVehicleIndex` `beingOvertakenVehicleIndex` |
| `SCAR` | 세이프티카 | `safetyCarType` `eventType` |
| `COLL` | 충돌 | `vehicle1Index` `vehicle2Index` |
| `CHQF` · `RDFL` | 체커기 · 적기 | (없음) |

`SSTA`·`SEND`는 세션 경계 마커로 쓰고 목록에 넣지 않는다. `BUTN`(버튼 상태)은 입력 장치 상태라 버린다. 라이브러리가 모르는 코드는 상세 없이 코드만 싣는다.

---

## 8. 순위표 랩 기록 — `SessionClassified` (D-49, docs/15 §8)

| 필드 | 원천 | 규칙 |
|---|---|---|
| `results[].lapHistory[]` | Session History(11), 차마다 돌아가며 옴 | 그 차의 최신 패킷 목록(`NumLaps`칸까지). `lapHistoryEntry` = { `lapNumber` `lapTimeMs` `sector1TimeMs` `sector2TimeMs` `sector3TimeMs`(분 칸 합산) `lapValid` `sector1Valid` `sector2Valid` `sector3Valid`(비트 0x01·0x02·0x04·0x08) }. 못 받은 차는 null |
| `lapPositions[]` | Lap Positions(15) | { `lapNumber`, `positions[carIndex]`(0 = 기록 없음) } 랩 번호 순. 랩 번호 = `StartingLap`(0부터) + 1 + i. 여러 패킷(50랩 구간)을 랩 번호로 합친다(같은 랩은 나중 값) |

세션이 바뀌면 비운다. 봉투 한도를 넘으면 **랩 기록 → 타이어 스틴트** 순으로 뺀다. 22대 × 78랩(모나코 100%) ≈ 324KB로 보통은 그대로 간다.
Session History의 타이어 스틴트 칸은 Final Classification의 `tyreStints`와 같아 싣지 않는다.
