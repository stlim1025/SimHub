# 04 · REST API Design (MVP)

> Status: **Design (미승인)** · Last Updated: 2026-07-06
> 계약 원본: `shared/openapi/openapi.yaml` (구현 시 생성). JSON body는 **camelCase**.

---

## 1. 설계 규약

| 항목 | 규약 |
|---|---|
| 프로토콜 | HTTPS only |
| 형식 | JSON, 요청/응답 필드 camelCase |
| 버저닝 | 경로 prefix `/api/v1` |
| 인증 | JWT Bearer (`Authorization: Bearer <token>`) |
| 시간 | ISO-8601 UTC (`2026-07-06T09:00:00Z`) |
| 역할 분리 | **REST = 조회/명령(요청-응답)**, 실시간 갱신은 SignalR([05](./05-signalr-design.md)) |
| 문서화 | Swagger/OpenAPI 필수 |

### 표준 에러 응답 (RFC 7807 Problem Details 기반)

```json
{
  "type": "https://simcenter/errors/validation",
  "title": "Validation failed",
  "status": 400,
  "detail": "rigCode is required.",
  "traceId": "00-abc...-01",
  "errors": { "rigCode": ["required"] }
}
```

| 코드 | 사용 |
|---|---|
| 200 / 201 | 성공 / 생성 |
| 400 | 검증 실패 |
| 401 | 미인증 (토큰 없음/만료) |
| 403 | 권한 없음 |
| 404 | 리소스 없음 |
| 409 | 상태 충돌 (예: 이미 활성 세션 존재) |
| 500 | 서버 오류 (상세 미노출, traceId만) |

---

## 2. MVP 엔드포인트 요약

| Method | Path | 인증 | 설명 |
|---|---|---|---|
| POST | `/api/v1/auth/register` | ❌ | 회원가입 (MVP 최소) |
| POST | `/api/v1/auth/login` | ❌ | 로그인 → JWT 발급 |
| GET | `/api/v1/me` | ✅ | 내 프로필 |
| POST | `/api/v1/sessions/check-in` | ✅ | SimRig 체크인 → DrivingSession 생성 |
| POST | `/api/v1/sessions/{id}/check-out` | ✅ | 세션 종료 |
| GET | `/api/v1/sessions/active` | ✅ | 내 활성 세션 조회 |
| GET | `/api/v1/rankings` | ✅ | TOP10 (트랙 · 기간 daily/monthly/yearly) |
| GET | `/api/v1/tracks` | ✅ | 트랙 목록(마스터) |
| GET | `/api/v1/me/laps` | ✅ | 내 랩 기록 (My Lap Record) |

> **Telemetry 인입은 REST가 아니라 SignalR**로 처리한다(Agent→Backend). [05](./05-signalr-design.md) 참조.

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
> Refresh Token 도입 여부 → D-9 (MVP는 단순 access token 권장).

### 3.3 GET `/me`
```jsonc
// 200
{ "userId": "guid", "email": "a@b.com", "displayName": "홍길동" }
```

### 3.4 POST `/sessions/check-in`
사용자가 좌석 QR/코드로 체크인. 랩-사용자 귀속의 시작점(D-2).
```jsonc
// Request
{ "rigCode": "A-01", "gameCode": "F1_24" }
// 201 Response
{
  "sessionId": "guid",
  "rigCode": "A-01",
  "status": "Active",
  "startedAt": "2026-07-06T09:00:00Z"
}
// 409 — 해당 Rig에 (다른 사용자의) 활성 세션이 이미 존재
```
규칙(D-10 확정): 체크인하는 **사용자 본인의** 다른 활성 세션은 서버가 **자동 종료**한 뒤 신규 생성.
단, 대상 Rig가 **다른 사용자**의 활성 세션으로 점유 중이면 409 반환.

### 3.5 POST `/sessions/{id}/check-out`
```jsonc
// 200
{ "sessionId": "guid", "status": "Ended", "endedAt": "..." }
```
본인 세션만 종료 가능(403 otherwise).

### 3.6 GET `/sessions/active`
```jsonc
// 200 (없으면 null 데이터)
{ "sessionId": "guid", "rigCode": "A-01", "startedAt": "..." }
```

### 3.7 GET `/rankings?trackId={guid}&period=monthly&gameCode=F1_25&date=2026-07-06`
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
> 기간 경계는 매장 로컬 타임존 기준으로 서버가 계산한다(D-8).

### 3.8 GET `/tracks`
```jsonc
// 200
{ "items": [ { "trackId": "guid", "gameCode": "F1_24", "name": "Silverstone" } ] }
```

### 3.9 GET `/me/laps?trackId={guid}&sessionType={opt}&page=1&pageSize=20`
My Lap Record. **모든 세션·무효 랩까지 조회 가능**(D-15/D-16). `sessionType` 미지정 시 전체.
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

- 로그인 성공 → JWT(HS256 또는 RS256) 발급. Claims: `sub`(userId), `name`(displayName), `exp`.
- `[Authorize]` 기본 적용, `register`/`login`만 `[AllowAnonymous]`.
- 토큰 검증은 Infrastructure의 인증 미들웨어에서 처리(Api 레이어 조립).
- Secrets(서명 키)는 코드에 두지 않고 환경변수/User-Secrets/Config Provider로 주입(헌장 Security).

---

## 5. 페이징/정렬 공통 규약

- 페이징: `page`(1-base), `pageSize`(기본 20, 최대 100).
- 응답 래퍼: `{ page, pageSize, total, items[] }`.
- 정렬: 랭킹은 항상 lapTimeMs ASC. 내 기록은 `setAt DESC` 기본.

---

## 6. 확정된 결정 (반영 완료)

- **D-9 ✅** Refresh Token = MVP 제외 (access token만)
- **D-10 ✅** 중복 활성 세션 = 이전 세션 자동 종료 (check-in 시 서버가 처리)
- **D-11 ✅** 회원가입 = 앱에서 직접 가입(self-signup) → `/auth/register` 유지
- **D-8 ✅** 랭킹 = 일/월/연 기간 파라미터 (`/rankings?period=`)
- **D-16 ✅** 랭킹 = Time Trial만, 개별 랩 조회는 전 세션·무효 랩 포함
