# F1 25 UDP Telemetry Specification (MVP)

> ⚠️ **역할 전환 (D-20, 2026-07-07):** 바이트 파싱은 NuGet **F1Game.UDP(26.0.0)**에 위임한다.
> 따라서 이 문서의 **오프셋 표는 더 이상 구현 계약이 아니라 참고/이해용**이다(값이 어긋나면 라이브러리가 정답).
> 유지되는 것은 **도메인 이벤트 의미론**(어떤 패킷/필드가 세션·랩·섹터·완주 판정에 쓰이는지)이다.
> 신규 오프셋을 손으로 관리하지 말 것 — 상세: [08-open-decisions.md#D-20](../../docs/08-open-decisions.md).
>
> **참조용 스펙 문서**
> F1 25 게임에서 송출되는 UDP Telemetry 패킷 중, **SimCenter MVP의 랩타임 측정 및 랭킹 정립**에 필요한 핵심 패킷 3종에 대한 세부 바이트 구조와 오프셋을 명세합니다.
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
- `1`: **Session Packet** (세션 환경, 트랙 및 세션 타입 확인)
- `2`: **Lap Data Packet** (플레이어의 현재 주행 랩 수치 및 시간)
- `3`: **Event Packet** (세션 시작/종료 등의 마커 수신)

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
