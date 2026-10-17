# 04 · REST API Design

> Status: **Design (미승인)** · Last Updated: 2026-10-17 (P6 개인 모드 반영)
> 계약 원본: `shared/openapi/openapi.yaml`. JSON body는 **camelCase**.
> P6에서 `/sessions/*`(체크인)를 제거하고 Agent 연결·장치·내 트랙 API를 추가했다(D-25·D-26, [11](./11-personal-mode.md) §8).

---

## 1. 설계 규약

| 항목 | 규약 |
|---|---|
| 프로토콜 | HTTPS only (로컬 개발은 http 프로파일 허용) |
| 형식 | JSON, 요청/응답 필드 camelCase |
| 버저닝 | 경로 prefix `/api/v1` |
| 인증 | JWT Bearer (`Authorization: Bearer <token>`). 예외: `POST /agent/pair`는 익명(연결 코드가 자격) |
| 시간 | ISO-8601 UTC (`2026-07-06T09:00:00Z`) |
| 역할 분리 | **REST = 조회/명령(요청-응답)**, 실시간 갱신은 SignalR([05](./05-signalr-design.md)) |
| 문서화 | Swagger/OpenAPI 필수 |

### 표준 에러 응답 (RFC 7807 Problem Details 기반)

```json
{
  "type": "https://simcenter/errors/validation",
  "title": "Validation failed",
  "status": 400,
  "detail": "Validation failed.",
  "traceId": "00-abc...-01",
  "errors": { "code": ["유효하지 않거나 만료된 코드입니다."] }
}
```

> 검증 실패(400)의 `detail`은 항상 `"Validation failed."`이고, 필드별 메시지는 `errors.<필드>[0]`에 담긴다
> (위 예: `POST /agent/pair`의 잘못된 연결 코드 → `errors.code[0]`).

| 코드 | 사용 |
|---|---|
| 200 / 201 / 204 | 성공 / 생성 / 본문 없는 성공(장치 해제) |
| 400 | 검증 실패 (연결 코드가 틀림·만료·사용됨·무효화됨도 모두 같은 400) |
| 401 | 미인증 (토큰 없음/만료) |
| 403 | 권한 없음 (남의 장치 해제 시도 등) |
| 404 | 리소스 없음 |
| 409 | 상태 충돌 (예: 이미 가입된 이메일) |
| 429 | 요청 제한 초과 (`POST /agent/pair` IP당 분당 10회, 코드 발급 사용자당 분당 10회) |
| 500 | 서버 오류 (상세 미노출, traceId만) |

---

## 2. 엔드포인트 요약

| Method | Path | 인증 | 설명 |
|---|---|---|---|
| POST | `/api/v1/auth/register` | ❌ | 회원가입 |
| POST | `/api/v1/auth/login` | ❌ | 로그인 → JWT 발급 |
| GET | `/api/v1/me` | ✅ | 내 프로필 |
| POST | `/api/v1/me/agent-pairing-codes` | ✅ | Agent 연결 코드 발급(10분·1회용) |
| POST | `/api/v1/agent/pair` | ❌ (요청 제한) | 연결 코드 → 장치 키 교환 |
| GET | `/api/v1/me/agent-devices` | ✅ | 내 연결된 PC 목록 |
| DELETE | `/api/v1/me/agent-devices/{deviceId}` | ✅ | PC 연결 해제 |
| GET | `/api/v1/me/tracks` | ✅ | 내 기록이 있는 트랙 요약 |
| GET | `/api/v1/me/laps` | ✅ | 내 랩 기록 (정렬 `recent`/`fastest`) |
| GET | `/api/v1/rankings` | ✅ | TOP10 (트랙 · 기간 daily/monthly/yearly) |
| GET | `/api/v1/tracks` | ✅ | 트랙 목록(마스터) |

> **Telemetry 인입은 REST가 아니라 SignalR**로 처리한다(Agent→Backend). [05](./05-signalr-design.md) 참조.
> 제거: `POST /sessions/check-in`, `POST /sessions/{id}/check-out`, `GET /sessions/active` (D-25).

---

## 3. 엔드포인트 상세

### 3.1 POST `/auth/register`
```jsonc
// Request
{ "email": "a@b.com", "password": "P@ssw0rd!", "displayName": "홍길동" }
// 201 Response
{ "userId": "guid", "displayName": "홍길동" }
```
검증: email 형식, password 정책(길이 등), displayName 1~50자.

### 3.2 POST `/auth/login`
```jsonc
// Request
{ "email": "a@b.com", "password": "P@ssw0rd!" }
// 200 Response
{
  "accessToken": "jwt...",
  "expiresAt": "2026-07-06T10:00:00Z",
  "user": { "userId": "guid", "displayName": "홍길동" }
}
```
> Refresh Token은 도입하지 않는다(D-9). 만료 시 재로그인.

### 3.3 GET `/me`
```jsonc
// 200
{ "userId": "guid", "email": "a@b.com", "displayName": "홍길동" }
```

### 3.4 POST `/me/agent-pairing-codes`
웹 Telemetry App에서 Agent 연결 코드를 발급한다(D-26). 요청 본문 없음.
```jsonc
// 201
{ "code": "K7F2-9QXM", "expiresAt": "2026-10-17T09:10:00Z" }
```
- 코드: 8자(`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, 헷갈리는 `0`·`O`·`1`·`I` 제외), 표시 `XXXX-XXXX`. 유효 10분, 1회용.
- 새 코드를 발급하면 같은 사용자의 **미사용 코드는 모두 무효화**된다. 코드 원문은 이 응답에서만 보인다(서버는 해시만 저장).
- 사용자당 분당 10회 제한(초과 시 429).

### 3.5 POST `/agent/pair`
Agent가 연결 코드를 **장치 키**로 교환한다. 인증 없음(코드가 자격). IP당 분당 10회 제한(초과 시 429).
```jsonc
// Request — deviceName은 앞뒤 공백 제거 후 1~50자, 비어 있으면 "Windows PC"
{ "code": "k7f2 9qxm", "deviceName": "승댕이컴터" }
// 200 Response — 키 원문은 이 응답에서 딱 한 번만 내려간다
{ "deviceId": "guid", "deviceKey": "43자 base64url" }
```
- 코드 입력은 정규화(대문자, 하이픈·공백 제거)한 뒤 해시로 조회한다.
- 코드 소비는 조건부 UPDATE로 **원자적**이다(동시에 같은 코드로 두 번 연결해도 하나만 성공).
- 코드가 없음·만료·사용됨·무효화됨이면 **모두 같은 400**("유효하지 않거나 만료된 코드입니다.") — 어느 경우인지 알려주면 추측 공격에 힌트가 된다.
- 로그에는 코드·키 원문을 남기지 않는다.

### 3.6 GET `/me/agent-devices`
```jsonc
// 200 — 연결 해제된 장치는 제외, createdAt 내림차순
{ "items": [ { "deviceId": "guid", "name": "승댕이컴터", "lastSeenAt": null, "createdAt": "2026-10-17T08:02:42Z" } ] }
```
`lastSeenAt`은 마지막 이벤트 수신 시각(없으면 `null`). 웹이 이 값으로 Connection Status를 계산한다([11](./11-personal-mode.md) §7.3).

### 3.7 DELETE `/me/agent-devices/{deviceId}`
```
204 — 연결 해제(soft delete)
403 — 본인의 장치가 아님 · 404 — 없는 장치
```
해제된 장치의 키로는 새 SignalR 연결이 401로 거절되고, 이미 열린 연결로 오는 이벤트는 Reject된다([05](./05-signalr-design.md)).

### 3.8 GET `/rankings?trackId={guid}&period=monthly&gameCode=F1_25&date=2026-07-06`
트랙·기간별 TOP10 (**Time Trial 세션만**, 랭킹적격 랩). 실시간 갱신은 SignalR가 담당하고,
이 REST는 **초기 로드/새로고침**용.

쿼리 파라미터:
- `trackId` (필수)
- `period` = `daily` | `monthly`(**기본**) | `yearly` (D-8). **실시간 랭킹 화면 기본값은 monthly**(D-8a);
  daily/yearly는 조회 옵션. 모두 동일 응답 형태.
- `gameCode` (기본 `F1_25`)
- `date` (선택, 기간 기준일. 미지정 시 오늘)

```jsonc
// 200
{
  "trackId": "guid",
  "trackName": "Silverstone",
  "gameCode": "F1_25",
  "period": "monthly",
  "periodKey": "2026-07",             // daily: "2026-07-06", yearly: "2026"
  "entries": [
    { "rank": 1, "displayName": "홍길동", "bestLapTimeMs": 83452, "setAt": "..." },
    { "rank": 2, "displayName": "김레이", "bestLapTimeMs": 84010, "setAt": "..." }
  ]
}
```
> 기간 경계는 서버 설정 타임존 `Ranking:TimeZoneId`(기본 `Asia/Seoul`)로 계산한다(D-8 · D-27). 잘못된 값이면 서버 시작이 실패한다.

### 3.9 GET `/tracks`
```jsonc
// 200
{ "items": [ { "trackId": "guid", "gameCode": "F1_25", "name": "Silverstone" } ] }
```

### 3.10 GET `/me/tracks`
내 랩이 1개 이상 있는 트랙만, 마지막 주행일 내림차순. Laps 화면의 트랙 목록.
```jsonc
// 200
{
  "items": [
    { "trackId": "guid", "trackName": "Silverstone", "gameCode": "F1_25",
      "lapCount": 76, "bestValidLapTimeMs": 83452, "lastSetAt": "..." }
  ]
}
```
- `bestValidLapTimeMs`: 그 트랙에서 `IsValid`인 랩 중 최소 랩타임(세션 유형 무관). 랭킹용 PB(Time Trial 적격 랩)와 다른 값이다. 유효 랩이 없으면 `null`.

### 3.11 GET `/me/laps?trackId={guid}&sessionType={opt}&sort=recent&page=1&pageSize=20`
My Lap Record. **모든 세션·무효 랩까지 조회 가능**(D-15/D-16). `sessionType` 미지정 시 전체.
- `sort=recent`(기본): `SetAt` 내림차순.
- `sort=fastest`: 유효 랩 먼저, 랩타임 오름차순, 동률이면 `SetAt` 오름차순(무효 랩은 맨 뒤).
```jsonc
// 200
{
  "personalBest": { "trackId": "guid", "lapTimeMs": 83452, "setAt": "..." },  // 랭킹적격 기준
  "laps": {
    "page": 1, "pageSize": 20, "total": 57,
    "items": [
      {
        "lapId": "guid", "trackName": "Silverstone",
        "gameCode": "F1_25", "sessionType": "TimeTrial",
        "lapTimeMs": 83452,
        "sectors": [                              // 가변 섹터(D-7)
          { "sectorNumber": 1, "sectorTimeMs": 27010 },
          { "sectorNumber": 2, "sectorTimeMs": 30110 },
          { "sectorNumber": 3, "sectorTimeMs": 26332 }
        ],
        "isValid": true, "isRankingEligible": true, "setAt": "..."
      }
    ]
  }
}
```

---

## 4. 인증/인가 설계

- **사용자(REST · RankingHub):** 로그인 성공 → JWT(HS256) 발급. Claims: `sub`(userId), `name`(displayName), `exp`.
  `[Authorize]` 기본 적용, `register`/`login`/`agent/pair`만 `[AllowAnonymous]`.
- **Agent(TelemetryHub):** 사용자 JWT와 분리된 `AgentApiKey` 스킴. 헤더 `X-Agent-Key`(대체 수단으로 `access_token` 쿼리)의 장치 키를
  SHA-256 해시로 `AgentDevice`와 대조한다. 클레임은 `deviceId`·`sub`(장치 주인)이다. 연결 해제된 장치는 401(D-26).
- 토큰 검증은 Infrastructure의 인증 미들웨어에서 처리(Api 레이어 조립).
- 요청 제한은 ASP.NET Core 내장 Rate Limiting(새 패키지 없음). 인증 뒤에 둬서 사용자 파티션이 주체를 읽고, 401 요청이 한도를 소모하지 않는다.
- Secrets(서명 키)는 코드에 두지 않고 환경변수/User-Secrets/Config Provider로 주입(헌장 Security).

---

## 5. 페이징/정렬 공통 규약

- 페이징: `page`(1-base), `pageSize`(기본 20, 최대 100). 웹 트랙별 랩 표는 15개씩 요청한다.
- 응답 래퍼: `{ page, pageSize, total, items[] }`.
- 정렬: 랭킹은 항상 lapTimeMs ASC. 내 기록은 `sort`로 선택(기본 `recent` = `setAt DESC`).

---

## 6. 확정된 결정 (반영 완료)

- **D-25 ✅** 개인 모드 — 체크인 API 제거 (~~D-10 중복 세션 정책~~ 불필요)
- **D-26 ✅** Agent 연결 = 1회용 코드 → 장치 키 (`/me/agent-pairing-codes`, `/agent/pair`)
- **D-27 ✅** 랭킹 타임존 = 서버 설정 `Ranking:TimeZoneId`
- **D-9 ✅** Refresh Token = 제외 (access token만)
- **D-11 ✅** 회원가입 = 앱에서 직접 가입(self-signup) → `/auth/register` 유지
- **D-8 ✅** 랭킹 = 일/월/연 기간 파라미터 (`/rankings?period=`)
- **D-16 ✅** 랭킹 = Time Trial만, 개별 랩 조회는 전 세션·무효 랩 포함
