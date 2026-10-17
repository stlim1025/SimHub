# 13 · Agent Outbox 독성 항목 — 항목별 미루기 + dead-letter

> Status: **Design (2026-10-17, 리뷰 반영 재설계)** · Last Updated: 2026-10-17
> 서버가 특정 Outbox 항목에 매번 같은 오류로 답할 때, 그 항목 하나 때문에 뒤의 랩·이벤트가 영원히 올라가지 못하는 문제를 없앤다.
> 결정은 [08](./08-open-decisions.md)에 D-35~D-38로 기록한다(D-28~D-34는 P7 [12](./12-seasons-sessions.md)가 쓴다).
> 업로드 동작의 나머지는 [11](./11-personal-mode.md) §6.4, Outbox 구조는 [06](./06-telemetry-design.md) §5를 따른다. 리뷰 반영 내역은 §8.

---

## 0. 문제

- `TelemetryUploadService`는 Outbox 항목을 `occurred_at, seq` 순서로 하나씩 보낸다. 서버가 답하면(Ack/Reject) 항목을 지우고,
  `SubmitAsync`가 예외를 던지면 일시 장애로 보고 **같은 첫 항목**을 지수 백오프(최대 30초)로 다시 보낸다.
- 서버가 그 항목에 **매번 같은 예외**를 던지면(구현 버그, DB 제약 위반, 메시지 크기 초과 등) 재시도가 끝나지 않고, 뒤에 쌓인 항목도 전혀 올라가지 않는다.
- Outbox의 payload가 손상돼 JSON으로 읽히지 않아도 같은 일이 생긴다(예외 → 같은 항목 재시도).
- 401과 연결 해제 Reject는 이미 따로 다룬다(11 §6.4).

## 1. 원칙과 목표

- **허브 계약상 영구 무효인 입력은 이미 Reject**다(파싱 실패·트랙 매핑 없음 → Agent가 지운다). 따라서 서버 **예외**는 언제나 서버 쪽 문제(버그·장애)이고,
  서버를 고치면 그 항목은 성공해야 한다. → 서버 오류는 **항목을 버리거나 격리할 근거가 아니다.** 막힘만 풀면 된다.

| 목표 | 비목표 |
|---|---|
| 서버 오류가 반복되는 항목 하나가 뒤 항목을 막지 않는다 | 서버 쪽 오류 처리·허브 계약 변경 |
| 서버 전체 장애·잘못된 배포·네트워크 단절로 **어떤 항목도 잃거나 격리되지 않는다.** 서버가 고쳐지면 저절로 올라간다 | 실패 횟수의 영속화 |
| 읽을 수 없는 payload는 따로 보관하고 다음으로 넘어간다 | dead-letter 항목 재전송 기능(§7 후속) |
| 로그와 Tray로 알린다 | |

## 2. 대안

| 안 | 내용 | 판단 |
|---|---|---|
| A | 같은 항목이 서버 오류로 연속 N번 실패하면 dead-letter | 서버 전체 장애 동안 항목이 하나씩 격리된다(N=5, 백오프 30초면 약 2.5분에 1건). 장애가 끝나도 돌아오지 않는다 |
| B | A + "서버가 다른 항목은 처리한다"는 증거가 있을 때만 dead-letter | **기각(리뷰 C1).** 백엔드는 `LapStarted`·`SectorCompleted`를 저장하지 않고 즉시 Ack하므로(`TelemetryIngestService` 4단계) 랩마다 증거가 생긴다. 랩 저장 경로만 깨진 배포가 나가면 **모든 랩이 격리**된다 |
| C | 서버 허브가 모든 예외를 Reject로 바꿔 답한다 | 일시 장애도 Reject가 되어 Agent가 지운다 = 데이터 손실. 허브 계약 변경 |
| D | 항목에 최대 나이(TTL) | 오래 오프라인이었던 정상 항목과 구분하지 못한다 |
| **E (채택)** | 서버 오류가 N번 난 항목은 **그 항목만 시각 기준으로 미루고**(30초 → 최대 5분) 뒤 항목을 먼저 보낸다. 격리하지 않고 계속 다시 시도한다. **읽을 수 없는 payload만** dead-letter | 잃는 데이터가 없다. 서버를 고치면 최대 5분 안에 올라간다. 대가: 고쳐지지 않는 항목은 5분마다 계속 시도된다(하루 약 288회 — 사용자 한 명이라 감당 가능) |

## 3. 동작 (채택안 E)

### 3.1 실패 분류

| 실패 | 판정 | 처리 |
|---|---|---|
| 허브 연결 실패(`StartAsync`: DNS·연결 거부·시간 초과·503) | 네트워크 | 기존 백오프. 항목 기록에 손대지 않는다 |
| 401 · 연결 해제 Reject | 키 거부 | 기존대로(11 §6.4). 항목 기록을 비운다(§3.2) |
| 전송 중 연결 끊김 · 끊긴 상태에서 전송(`TaskCanceledException`·`IOException`·`InvalidOperationException`·`TimeoutException`) | 네트워크 | **세지 않고 초기화하지도 않는다.** 같은 첫 항목을 그대로 다시 보낸다(순서 유지) |
| 서버가 처리 중 오류로 답함 — 허브 메서드 예외(`HubException`), 서버가 오류와 함께 연결을 닫음(메시지 크기 초과 등), 빈 응답, **60초 안에 응답 없음** | **서버 오류** | 그 항목의 실패 횟수 +1 (§3.2), 기존 백오프 |
| Outbox payload를 JSON으로 읽지 못함(로컬 손상) | 로컬 손상 | **즉시 dead-letter**(§3.4) 후 다음 항목 |

- 분류는 **세션 경계**(`ITelemetryHubSession`)가 맡는다. SignalR 구현은 위의 서버 오류를 `TelemetryHubServerException`으로 바꿔 던지고, 업로더는 **이 예외만 센다.**
  업로더는 SignalR 타입을 모른다(기존 경계 유지). 변환 규칙은 순수 함수 `HubSubmitInvoker`로 떼어 단위 테스트한다.
- "연결이 아직 열려 있는가"로 판정하지 않는다. SignalR은 연결이 닫힐 때 진행 중인 호출을 먼저 실패시키고 상태를 나중에 바꾸므로 경합에 약하다.
- 응답 시간 제한(`HubSubmitInvoker.SubmitTimeout = 60초`)은 SignalR 기본 `ServerTimeout`(30초)보다 **일부러 길다.** 네트워크가 반쯤 끊기면 30초 쪽이 먼저 연결을 닫아
  네트워크로 분류되고, 연결은 살아 있는데 허브 메서드가 멈춘 경우만 서버 오류가 된다. 이 분류가 틀려도 항목이 미뤄질 뿐 잃지 않는다.
- `ct`(종료)에서 온 취소는 감싸지 않고 그대로 올린다.

### 3.2 항목별 미루기

- 상수(업로더): `ItemDeferThreshold = 5`, `ItemRetryBaseDelay = 30초`, `ItemRetryMaxDelay = 5분`.
- 업로더는 서버 오류가 난 항목마다 **실패 횟수**와 **다음 시도 시각**을 메모리에 둔다(`ServerFailureTracker`, 순수 로직, 시각은 `IClock`).
- 실패 횟수가 5 미만이면 지금처럼 같은 첫 항목을 전역 백오프로 다시 보낸다(잠깐의 오류에는 순서를 지킨다).
- 5번째 실패부터 그 항목은 **미뤄진다**: 다음 시도 시각 = 지금 + `min(5분, 30초 × 2^(실패 − 5))` (30초, 1분, 2분, 4분, 5분, 5분…).
  묶음을 보낼 때 아직 때가 안 된 항목은 건너뛰고 뒤 항목을 보낸다. 때가 되면 순서대로 다시 시도한다.
- 서버 오류 뒤에는 항목과 상관없이 **전역 백오프로 한 번 쉰다**(서버가 아플 때 요청을 몰아 보내지 않는다).
- 묶음이 전부 미뤄진 항목이면 폴링 주기(1초)마다 Outbox만 다시 읽는다. 새 항목이 들어오거나 시각이 되면 보낸다(굶주림 없음).
- 조회 개수 = `BatchSize(50) + 기록 중인 항목 수` — 미뤄진 항목이 50건을 넘어도 새 항목이 조회된다(리뷰 H1).
- 서버가 그 항목에 답하면(Ack/Reject) 기록을 지운다. **장치 키가 바뀌거나 거부되면 기록을 모두 비운다**(키 A에서의 실패가 키 B로 이어지지 않게, 리뷰 M3).
- 기록은 메모리에만 있다. 다시 켜면 처음부터 센다.
- 남은 시간이 최대 지연(5분)보다 길면 벽시계가 뒤로 간 것으로 보고 미루지 않는다(시각을 되돌려도 "늦어도 5분 안에 다시 시도"를 지킨다).

| 상황 | 흐름 | 결과 |
|---|---|---|
| 독성 X, 정상 B·C | X 실패×5(약 31초) → X 미룸 → B·C 전송 → X는 30초·1분·2분…마다 재시도 | 뒤 항목 정상. 서버가 고쳐지면 X도 최대 5분 안에 전송 |
| 잘못된 배포(랩 경로만 깨짐) | 랩마다 5번 실패 후 미뤄지고, `LapStarted`·`SectorCompleted`는 정상 전송 | 랩은 Outbox에 남는다. 배포를 고치면 최대 5분 안에 전부 전송 |
| 서버 전체 장애 | 첫 항목 실패×5 → 미룸 → 다음 항목 … (요청은 전역 백오프로 최대 30초에 1번) | 잃는 항목 없음. 복구 후 순서대로·때가 된 대로 전송 |
| 네트워크 단절 | 횟수 0, 첫 항목을 그대로 재시도 | 순서 그대로 |
| 손상 payload | 즉시 dead-letter → 다음 항목 | 그 항목만 따로 보관 |

### 3.3 순서

- 정상 상태와 네트워크 장애에서는 순서가 그대로다. **5번 이상 서버 오류가 난 항목만** 뒤 항목보다 늦게 간다.
- 저장 결과는 순서와 무관하다. `eventId` 멱등이고, `LapFinished`는 항목마다 저장되며 정렬은 `OccurredAt` 기준이다. 순서를 타는 부분은 다음 두 가지다(리뷰 M2):
  - **PB 판정·랭킹 브로드캐스트**(`TelemetryIngestService` 7단계)는 도착 순서로 계산한다. 미뤄진 랩보다 나중 랩이 먼저 도착하면, 그 시점에 PB 알림이 한 번 잘못 나갈 수 있다(저장된 랩·랭킹 조회는 그대로다).
  - P7 `SessionClassified`가 **트랙·종류가 다른 세션끼리 같은 링크 키**를 다투는 경우(12 §6.2-6)는 먼저 도착한 쪽이 키를 가진다.
- 이 둘을 **D-13(이벤트 순서 = 세션 단위)의 예외**로 기록한다(D-38). 순서에 기대는 이벤트를 새로 만들면 이 예외를 다시 검토한다.

### 3.4 dead-letter (읽을 수 없는 payload만)

같은 `outbox.db`에 테이블을 하나 더 둔다. 기존 DB에는 처음 열 때 새 테이블만 생긴다(`CREATE TABLE IF NOT EXISTS`, 마이그레이션 불필요).

```sql
CREATE TABLE IF NOT EXISTS outbox_dead_letter(
    event_id TEXT PRIMARY KEY,
    occurred_at TEXT NOT NULL,
    payload TEXT NOT NULL,
    reason TEXT NOT NULL,
    dead_lettered_at TEXT NOT NULL
);
```

- `TelemetryOutbox.MoveToDeadLetterAsync(eventId, reason, deadLetteredAt)` — 세마포어 안에서 **한 트랜잭션**으로 `INSERT OR REPLACE … SELECT … FROM outbox` 후 `DELETE`.
  Outbox에 없는 id면 아무것도 하지 않고 false.
- `reason` = 파싱 오류 메시지. `dead_lettered_at`은 `IClock`(헌장). 자동 삭제·보존 기간은 두지 않는다.

### 3.5 알림

- 로그: 서버 오류마다 `Warning`(eventId, 횟수, 서버 문구 — 스택 없이). 미룰 때는 다음 시도 시각을 함께 남긴다. dead-letter는 `Error`.
- `UploadStatusTracker`에 `DeferredCount`(5번 이상 실패해 미뤄진 항목 수)와 `DeadLetterCount`(시작할 때 DB에서 읽고, 옮길 때마다 다시 셈)를 둔다.
  바뀌면 `StateChanged`가 발생한다. `DeadLetterCount`는 업로드가 꺼진(Disabled) 경우에도 읽는다.
- Tray "계정 연결" 영역(0건이면 숨김):
  - `서버가 처리하지 못한 기록 N건 — 자동으로 다시 보냅니다`
  - `읽을 수 없어 따로 보관한 기록 N건 — 로그를 확인하세요`
- 연결 상태(`UploadState`)는 그대로 둔다(연결과 별개라 상태 값을 늘리지 않는다).

## 4. 바뀌는 파일

| 영역 | 파일 |
|---|---|
| 세션 경계 | `Upload/ITelemetryHubSession.cs`(문서), `Upload/TelemetryHubServerException.cs`·`Upload/HubSubmitInvoker.cs`(신규), `Upload/SignalRTelemetryHubSessionFactory.cs` |
| 판정 | `Upload/ServerFailureTracker.cs`(신규), `Upload/TelemetryUploadService.cs`(생성자에 `IClock`, 테스트용 `maxBackoff` 주입) |
| 저장 | `Outbox/TelemetryOutbox.cs` |
| 알림 | `Upload/UploadStatusTracker.cs`, Tray `UploadStateText.cs`·`MainWindow.xaml(.cs)` |

P7 Task 7이 고치는 `TelemetryPipeline`·`OutboxTelemetrySink`·`DependencyInjection`과 그 테스트 파일은 건드리지 않는다(`IClock`은 이미 등록돼 있다).

## 5. 테스트

- `ServerFailureTrackerTests`: 5번 미만은 미루지 않음 · 5번째부터 30초·1분…·최대 5분 · 시각이 지나면 다시 보낼 수 있음 · 답하면 기록 삭제 · 비우기.
- `HubSubmitInvokerTests`: `HubException`·빈 응답·시간 초과 → 서버 오류 · 연결 종료 취소·`IOException`·종료 취소 → 그대로 · 정상 응답.
- `TelemetryOutboxDeadLetterTests`: 옮기면 Outbox에서 빠지고 payload·사유·시각이 남음 · 없는 id는 false · 옛 스키마 DB 파일에도 동작.
- `TelemetryUploadServiceTests`(조절 가능한 시계):
  - 독성 항목 → 5번 뒤 미뤄지고 뒤 항목이 먼저 전송됨, `DeferredCount` 1, 시각이 지나면 다시 시도, 서버가 고쳐지면 전송되고 0.
  - 모든 항목 서버 오류(전체 장애) → 아무것도 잃지 않음(dead-letter 0, Outbox 그대로), 복구 후 전부 전송.
  - **전송 중 연결 끊김 → 횟수에 세지 않음(미루지 않음), 뒤 항목을 먼저 보내지 않음, 복구 후 순서대로 전송, dead-letter 0.**
  - 손상 payload → 즉시 dead-letter, 뒤 항목 전송, `DeadLetterCount` 1.
  - 키가 바뀌면 미룸이 풀려 새 키로 바로 다시 시도.
  - 시작 시 기존 dead-letter 건수 표시.

## 6. 남는 위험

- 고쳐지지 않는 서버 오류 항목은 5분마다 영원히 다시 시도된다(서버 오류 로그도 5분마다 생긴다). Tray에 건수가 보이므로 사용자가 알 수 있다.
- 서버 `EnableDetailedErrors`가 꺼져 있어 Agent 로그의 서버 문구는 대개 "An unexpected error occurred…"다. 원인은 서버 로그에서 찾는다(§7).
- `GetPendingAsync`의 `event_id`가 손상되면(`Guid.Parse` 실패) 항목 단위 처리 전에 실패한다. SQLite 파일 자체의 손상이라 이 설계 범위 밖이다(§7).

## 7. 후속

- 서버: 허브 메서드 예외 로그에 `eventId`를 남겨 Agent 로그와 맞춰 볼 수 있게(백엔드 `TelemetryHub`).
- dead-letter 재전송·내보내기(Cli 명령) — 손상 payload를 사람이 고쳐 다시 넣을 일이 생기면.
- Outbox 행 자체 손상(`event_id` 해석 실패) 처리.

## 8. 리뷰 반영 (2026-10-17, 설계 리뷰 1회 + 구현 리뷰 1회)

| 지적 | 반영 |
|---|---|
| C1 증거 규칙이 `LapStarted`·`SectorCompleted` 즉시 Ack로 충족돼, 랩 경로만 깨진 배포에서 모든 랩이 격리됨 | B안 기각. 서버 오류는 최종 판정하지 않고 항목별로 미룬다(E안) |
| C2 "한 번 더 실패하면 이동" 상태가 만료되지 않아 장애 직후 흔들림에 대량 이동 | 이동 자체가 없어져 해소 |
| H1 전부 보류일 때 첫 항목만 재시도 → 정상 항목 굶주림, 보류 50건 초과 시 `LIMIT 50`으로 영구 정체 | 시각 기준 재시도 + 조회 개수 `50 + 기록 수` |
| H2 서버 오류·이동 뒤 흐름 미정, `MaxBackoff` 고정이라 테스트 불가 | §3.2에 흐름 명시, 테스트용 `maxBackoff`·시계 주입 |
| M1 허브 메서드가 멈추면 무한 대기 | 60초 응답 제한(`ServerTimeout`보다 길게) → 서버 오류 |
| M2 순서가 바뀌면 PB 알림·P7 링크 키 다툼이 달라짐 | §3.3에 명시, D-38에 D-13 예외로 기록 |
| M3 키가 바뀌어도 실패 기록이 남음 | 키 변경·거부 시 기록 비우기 |
| LOW 트랜잭션 지정, 손상 JSON catch 범위, Disabled에서도 건수 읽기, 반복 로그 스택 | §3.4·§3.5에 반영 |
| (구현 리뷰) 벽시계가 뒤로 가면 미룸이 그만큼 길어짐 | 남은 시간 > 최대 지연이면 미루지 않음(§3.2) + 테스트 |
| (구현 리뷰) 조회 개수 `50 + 기록 수`에 회귀 테스트 없음 | 테스트용 묶음 크기 주입 + "미룬 항목이 묶음을 채워도 뒤 항목 전송" 테스트(수정 전 RED 확인) |
| (구현 리뷰) dead-letter 이동 실패가 연결 문제처럼 기록됨, 항상 참인 단언, 매직 넘버 | 이동 실패 시 eventId와 함께 `Error` 로그, 단언 강화, 상수 제거 |

## 9. 결정 목록 (08에 기록)

| ID | 결정 |
|---|---|
| D-35 | 서버 오류가 반복되는 항목 = **격리하지 않고 그 항목만 미룬다**: 5번(`ItemDeferThreshold`) 실패하면 30초부터 최대 5분 간격으로 다시 시도하고 뒤 항목을 먼저 보낸다. 서버 예외는 서버 쪽 문제라 고쳐지면 저절로 올라간다 |
| D-36 | 실패 분류 = 세션 경계가 서버 오류(허브 메서드 예외·오류와 함께 연결 종료·빈 응답·60초 무응답)를 `TelemetryHubServerException`으로 알리고 업로더는 그것만 센다. 연결 실패·전송 중 끊김은 세지도 초기화하지도 않는다. 키가 바뀌면 기록을 비운다. 기록은 메모리 |
| D-37 | dead-letter = **읽을 수 없는 payload만**, 같은 SQLite 파일의 `outbox_dead_letter` 테이블(자동 삭제 없음) |
| D-38 | 알림 = 로그 + Tray 두 줄(미뤄진 건수 · 보관한 건수). 미뤄진 항목에 한해 D-13 순서의 예외(PB 알림, P7 링크 키 다툼) |
