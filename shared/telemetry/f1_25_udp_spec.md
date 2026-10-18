# F1 25 UDP Telemetry Specification (MVP)

> ⚠️ **역할 전환 (D-20, 2026-07-07):** 바이트 파싱은 NuGet **F1Game.UDP(25.1.1, D-41)**에 위임한다.
> 따라서 이 문서의 **오프셋 표는 더 이상 구현 계약이 아니라 참고/이해용**이다(값이 어긋나면 라이브러리가 정답).
> 유지되는 것은 **도메인 이벤트 의미론**(어떤 패킷/필드가 세션·랩·섹터·완주 판정에 쓰이는지)이다.
> 신규 오프셋을 손으로 관리하지 말 것 — 상세: [08-open-decisions.md#D-20](../../docs/08-open-decisions.md).
>
> **참조용 스펙 문서**
> F1 25 게임에서 송출되는 UDP Telemetry 패킷 중, **SimCenter MVP의 랩타임 측정 및 랭킹 정립**에 필요한 핵심 패킷 3종에 대한 세부 바이트 구조와 오프셋을 명세합니다.
> 랩 상세(차량 스냅샷·텔레메트리 트레이스, [docs/15](../../docs/15-lap-detail-telemetry.md) §3, D-44·D-45)에 새로 쓰는 패킷·필드는 **§5**에 모았습니다.
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
| 24 | `TyresBlisters[4]` | uint8 × 4 | (F1 25 신규, 쓰지 않음) |
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
