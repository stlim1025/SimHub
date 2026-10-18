# 14 · 프로필·계정 설정 (Edit Profile)

> Status: **Implemented (2026-10-18, 리뷰 반영)** · Last Updated: 2026-10-18
> 사용자 요청: "내 프로필 누르면 설정화면이 나와야 해" — F1Laps의 Edit Profile 화면을 본뜬다.
> 결정은 [08](./08-open-decisions.md) D-39(프로필·설정)·D-40(기본 테마 = Dark)에 기록한다. API 계약은 [04](./04-api-design.md) §3.3·3.3a·3.3b와 `shared/openapi/openapi.yaml`.
> 문서 번호: 요청은 `13-profile-settings.md`였으나 13번을 이미 [13](./13-outbox-dead-letter.md)이 써서 14번으로 둔다.

---

## 1. 범위 (R1)

| 포함 | 제외(헌장·요청) |
|---|---|
| 이메일 변경, 닉네임(= `displayName`) 변경 | 결제·구독(Billing) — 헌장 MVP 제외 |
| 랭킹 이름 공개 설정(Privacy) | 비밀번호 변경, 계정 삭제 |
| 게임 · 컨트롤러 · 플랫폼 · 단위 · 타임존 · 테마 | 타임존 기준 시각 표시(저장만) |
| 프로필 사진(팀 색 원) | 실제 팀 로고 |
| 저장/취소(바뀐 것 추적), 로그아웃 | 화면을 떠날 때 저장 안 한 변경 확인 |

## 2. 화면 흐름 (R8·R9)

- 사이드바 하단: 프로필 사진(고른 팀 원, 없으면 이름 첫 글자) + 이름 + "계정 설정". 누르면 셸 안의 `/settings`(NoTransitionPage, 다른 메뉴와 같다).
  설정 화면을 보는 동안 하단 프로필이 강조된다. 오른쪽 로그아웃 아이콘은 그대로 둔다.
- 화면(위 → 아래): 제목 `Edit Profile` + [로그아웃] · **프로필**(이메일 [변경] · 닉네임 [변경] · 공개 설정 체크박스) ·
  **설정**(게임 · 컨트롤러 · 플랫폼 · 단위 · 타임존 · 테마) · **프로필 사진**(사진 없음 + 팀 원 10개) · 아래 고정 바([변경 사항 저장] 초록 · [취소]).
- 저장/취소: 편집 중인 값(`ProfileDraft`)이 저장된 값과 다를 때만 켜진다. 취소는 저장된 값으로 되돌린다. 화면을 떠나면 편집 값은 버린다(확인 없음).
- **닉네임 변경 대화상자** → 폼에만 반영, [변경 사항 저장]으로 함께 저장한다(한 번에 저장하는 다른 값과 같은 흐름).
- **이메일 변경 대화상자**(새 이메일 + 현재 비밀번호) → 바로 `POST /me/email`. 필드 오류는 해당 칸 아래, 409 등은 대화상자 아래에 보인다.
  편집 중인 다른 값은 그대로 남는다.
- 반응형: 520px 미만이면 이름표를 값 위에 쌓고, 선택 버튼은 가로 스크롤, 드롭다운은 폭에 맞춰 줄임표로 줄인다(375px에서 넘침 없음 — 위젯 테스트).

## 3. 저장 값 (R2·R7)

`User`에 직접 둔다(소유 값 객체 대신 — 열이 평평해 단순하다). enum은 이름 문자열로 저장한다.

| 필드 | 타입 · 값 | 기본값 | 쓰임 |
|---|---|---|---|
| `ShowOnLeaderboard` | bool | `true` | 랭킹 익명화(§6) |
| `AvatarTeam` | string? (`AvatarTeamCodes`) | null | 사이드바·설정 사진 |
| `PreferredGame` | string (`GameCodes.Supported`) | `F1_25` | 저장만(이후 Phase) |
| `Controller` | `Gamepad` · `Wheel` | `Wheel` | 저장만(이후 Phase) |
| `Console` | `Pc` · `Xbox` · `PlayStation` | `Pc` | 저장만(이후 Phase) |
| `Units` | `Metric`(km/h) · `Imperial`(mph) | `Metric` | 저장만(텔레메트리 화면 P9에서 쓴다) |
| `TimeZoneId` | IANA ID | `Asia/Seoul` | 저장만 — 랭킹 기간 경계는 서버 설정(D-27) |
| `Theme` | `Light` · `Dark` · `System` | `Dark`(D-40) | 앱 테마(§7) |

- 기본값은 `UserProfileDefaults` 한 곳에 둔다(엔티티 초기값). 마이그레이션 `AddUserProfileSettings`(가산적)는 기존 사용자를 백필하고(당시 테마 System),
  `DefaultThemeDark`가 테마를 Dark로 바꾸고 열 기본값도 `Dark`로 맞춘다(D-40 — `AddUserProfileSettings`는 이미 개발 DB에 적용돼 고치지 않았다).
  모델에는 DB 기본값을 두지 않는다 — bool의 CLR 기본값(false)이 DB 기본값(true)으로 바뀌어 들어가는 EF 함정을 피하기 위해서다.
- 타임존 선택지는 앱의 `kTimeZoneIds` 한 곳(필수 8개 + 6개). 목록에 없는 저장 값은 드롭다운 맨 앞에 그대로 보인다. 새 패키지 없음.
- 게임 선택지는 앱의 `kGameLabels`(`F1_25` → "F1 25"), 서버는 `GameCodes.Supported`로 검증한다.

## 4. 프로필 사진 (R5)

- 실제 팀 로고는 상표라 쓰지 않는다. **팀 색 원 + 2~3자 코드**: `MER FER RBR MCL AST ALP WIL RB SAU HAA`.
- 코드 목록: 백엔드 `AvatarTeamCodes.All`(검증) · 앱 `kAvatarTeams`(색·이름) · OpenAPI `AvatarTeamCode` enum — 같은 순서·값. 테스트가 양쪽 목록을 고정한다.
- 색은 `AppColors.team*` 토큰(값은 백엔드 `TeamCatalog`과 같다). 밝은 팀 색(MER·MCL·WIL·SAU·HAA)은 코드 글자를 어둡게 쓴다.
- 고른 원에 강조색 테두리. "사진 없음"을 고르면 `avatarTeam = null` → 이름 첫 글자 원.

## 5. API (R3)

| Method | Path | 본문 | 성공 | 오류 |
|---|---|---|---|---|
| GET | `/me` | — | 200 `UserProfile`(계정 + 설정) | 401 |
| PUT | `/me/profile` | `{ displayName, showOnLeaderboard, avatarTeam, preferredGame, controller, console, units, timeZoneId, theme }` | 200 `UserProfile` | 400(필드별), 401 |
| POST | `/me/email` | `{ newEmail, currentPassword }` | 200 `UserProfile` | 400(`newEmail`·`currentPassword`), 401, 409 |

- `PUT /me/profile`은 **전체 교체**다. `avatarTeam`만 null 허용, 나머지는 필수(빠지면 `필수 항목입니다.`). 틀린 필드를 모두 모아 한 번의 400으로 알린다.
  - `displayName`: trim 후 1~50자 — 가입과 같은 규칙(`UserInputRules`).
  - enum: 이름만, 대소문자 무시(`EnumNames.TryParse`) — 숫자("1")·모르는 값은 400.
  - `avatarTeam`: trim + 대문자 후 `AvatarTeamCodes`에 있어야 한다. `preferredGame`: `GameCodes.Supported`.
  - `timeZoneId`: `TimeZoneInfo.TryFindSystemTimeZoneById` 성공 **그리고** `HasIanaId`(Windows ID "Korea Standard Time"은 거부), 64자 이하.
    저장 값은 런타임이 돌려준 정식 ID다(`asia/seoul` → `Asia/Seoul`). 런타임의 대소문자 처리가 캐시에 따라 달라서, 그대로 못 찾으면 구간 첫 글자만 대문자로 바꾼 후보로 한 번 더 찾는다(`IanaTimeZones`).
- `POST /me/email`: 새 이메일은 가입과 같이 정규화(trim + 소문자)·검증 → 현재 비밀번호 확인 → 같은 이메일이면 그대로 200 → 다른 계정이 쓰면 409.
  비밀번호가 틀리면 **401이 아니라 400**(`errors.currentPassword`) — 앱 인터셉터는 401을 세션 만료로 보고 로그아웃시킨다.
  발급된 JWT의 email 클레임은 다음 로그인 때 갱신된다(지금은 email 클레임을 읽는 곳이 없다). 로그에는 사용자 ID만 남긴다.
  비밀번호 추측을 늦추도록 **사용자당 분당 10회**로 제한한다(`RateLimitPolicies.EmailChange`, 연결 API와 같은 한도·창 공유, 넘으면 429).
- 로그인 응답의 `user`는 요약(`UserSummary`: userId·displayName)이라 앱은 로그인 직후 `GET /me`로 프로필을 읽는다. 실패하면 요약 사용자로 로그인은 계속하되
  `AppUser.isProfileLoaded`(= 이메일이 있음)가 false다. 설정 화면은 이때 폼 대신 `GET /me`를 다시 읽고(진행 표시 · 오류 + 다시 시도), 읽기 전에는 저장 바가 없고
  폼 컨트롤러도 저장을 거부한다 — 요약의 기본값(공개 등)으로 실제 설정(예: 비공개)을 덮어쓰지 않게.
- 앱 `ApiException`은 우리 서버 문서(`type`이 `https://simcenter/errors/`로 시작)일 때만 `errors.<필드>[0]`을 `fieldErrors`로 담고 메시지로도 쓴다("Validation failed." 대신).
  그 밖의 본문(ASP.NET 모델 바인딩의 `$.필드` 키·.NET 타입 이름)은 보이지 않고 상태 코드별 일반 메시지를 쓴다. 이메일 대화상자는 자기 칸(`newEmail`·`currentPassword`)에
  맞는 오류만 칸 아래에, 그 밖에는 일반 메시지를 아래에 보인다.

## 6. 랭킹 이름 비공개 (R4)

- `ShowOnLeaderboard = false`면 랭킹 항목의 표시 이름이 **`익명 드라이버`**(`RankingPrivacy.AnonymousDisplayName`)로 바뀐다. 순위·랩타임·시각은 그대로다.
- 적용 지점은 `RankingService.GetRankingAsync` 한 곳이다 — REST `GET /rankings`와 RankingHub `RankingUpdated` 스냅샷(인입 후 같은 메서드로 만든다)이 모두 따른다.
- `/me/*`(내 기록·트랙·시즌·세션)는 영향이 없다. 사용자 행이 없으면(soft delete 등) 익명으로 보인다.
  리포지토리 행(`RankingLapRow.ShowOnLeaderboard`)에는 기본값이 없다 — 만드는 쪽이 공개 여부를 빠뜨려 이름이 새는 일을 막는다.
- **한계(알려진 동작):** 공개 설정을 바꾸거나 닉네임을 바꿔도 이미 열린 Leaderboard는 바로 바뀌지 않는다. 그 트랙의 다음 `RankingUpdated`(새 적격 랩)나
  화면을 다시 열 때(`GET /rankings`) 반영된다. 설정 저장 때 브로드캐스트는 하지 않는다(트랙마다 재계산이 필요하고, 드문 변경이라 비용 대비 효과가 작다).
- "익명 드라이버"를 닉네임으로 쓰는 것은 막지 않는다(예약어 없음) — 공개 사용자가 그 이름을 쓰면 익명 항목과 구분되지 않지만 순위·기록은 그대로라 허용한다.

## 7. 테마 (R6)

- **기본 테마 = Dark(D-40).** 기존 사용자는 지금까지의 어두운 화면을 그대로 보고, 로그아웃·스플래시·세션 복원 중도 Dark다. 사용자가 System을 고르면 기기 밝기를 따른다.
- 밝은 팔레트: `AppColors.light*` 토큰(배경 `#F5F6FA` · 표면 `#FFFFFF` · 테두리 `#E2E5EC` · 글자 `#111827` · 보조 글자 `#646B78`,
  오류 `#B91C1C` · 정상 `#15803D` · 시상대 금 `#8A6500` · 은 `#5B6472` · 동 `#8C4A12`). 밝은 배경·표면 위 글자 대비 4.5:1 이상(테스트). 강조·팀 색은 두 테마 공통.
- 테마마다 다른 색은 `AppPalette`(ThemeExtension)로 묶고, 위젯은 `context.palette.*`로 읽는다(앱 테마가 없는 위젯 테스트에서는 어두운 팔레트).
  어두운 테마 값은 바꾸지 않았다(P6 화면 그대로). 타이어 글자처럼 밝은 색 위 대비가 필요한 곳은 어두운 토큰을 그대로 쓴다.
- 오류·정상·시상대 글자색과 `ColorScheme.error`도 팔레트(`context.palette.danger` 등)로 읽는다. 배경으로만 쓰는 초록 저장 버튼은 두 테마 공통(`AppColors.success` + 어두운 글자).
- `themeModeProvider`: 저장된 프로필의 `theme` → `ThemeMode`. 설정이 없으면(로그아웃·스플래시·복원 중) Dark, `System`만 기기 밝기를 따른다. 편집 중인 값은 저장해야 반영된다.

## 8. 앱 구조

- `features/auth/domain/user_preferences.dart` — 설정 enum(서버 문자열 ↔ 표시 이름, 모르는 값은 기본값)·`UserPreferences`(불변, `==`). `AppUser.preferences`.
- `features/auth/domain/user_input_rules.dart` — 가입·설정 공용 입력 검증. `features/auth/application/sign_out.dart` — 허브 종료 + 로그아웃(사이드바·설정 공용).
- `AuthController.applyProfile(user)` — 저장·이메일 변경 결과를 인증 상태에 반영 → 사이드바 사진·이름·테마가 따라온다. `reloadProfile()` — 요약 사용자의 `GET /me` 재조회(`profileReloadProvider`).
- `features/profile/` — `domain`(`ProfileDraft`·`kAvatarTeams`·`kTimeZoneIds`·`kGameLabels`), `data/ProfileRepository`(PUT·POST),
  `application/ProfileFormController`(autoDispose: 저장된 값·편집 값·전체 프로필 여부·저장 중·오류. 저장 요청 중에 더 고친 값은 저장 뒤에도 남는다)·`themeModeProvider`,
  `presentation`(설정 화면·구획·대화상자·사진 고르기·`TeamAvatar`).
- 공용 `SectionCard`는 `features/devices`에서 `core/widgets`로 옮겼다(Telemetry App·설정 공용).

## 9. 테스트

- **Backend 단위:** 엔티티 기본값(테마 Dark)·팀 코드 목록·**OpenAPI `AvatarTeamCode`·nullable `avatarTeam` enum 계약**(Domain), `ProfileServiceTests`(전 필드 저장·정규화·사진 지우기·팀 코드 10개·필드별 400·50자 초과·Windows 타임존 거부·필수 8개 타임존·정식 타임존 ID 저장·빠진 필드 전부 보고·404·이메일 정규화·틀린 비밀번호 400·비밀번호 없음·이메일 형식·중복 409·같은 이메일 무저장),
  `EnumNamesTests`, 랭킹 익명화(`RankingServiceTests`), `GetMe` 기본 설정(`AuthServiceTests`).
- **Backend 통합(`ProfileApiE2ETests`, 테스트 DB):** 기본 설정, 저장 → `GET /me` 반영, 잘못된 값 400 + 필드 키 + 미저장, 토큰 없음 401, 틀린 비밀번호 400,
  중복 409, 이메일 변경 후 새 이메일 로그인, 이메일 변경 사용자당 한도 429, 소문자 타임존 → 정식 ID, **비공개 사용자의 랩 → RankingHub `RankingUpdated`와 REST `/rankings` 모두 `익명 드라이버`, 다시 공개하면 이름**.
- **App 위젯·단위:** 설정 화면(저장된 값 표시·공개 설정 → 저장 켜짐 → 취소로 복원·같은 값이면 다시 꺼짐·사진 고르면 테두리·저장 내용·사진 지우기·닉네임은 폼만·빈 닉네임 차단·이메일 즉시 저장·틀린 비밀번호 칸 오류·409 메시지·저장 실패 메시지·로그아웃·375px 넘침 없음·
  요약 사용자 → 프로필 재조회 오류 + 다시 시도 → 실제 설정·저장 바 없음, 대화상자에 없는 필드 오류 → 일반 메시지),
  사이드바 하단 → `/settings`(넓은 화면·서랍·강조·팀 코드 원), 라우터(`/settings` 셸 안·로그아웃 시 `/login`), 모델·`ApiException`(필드 오류·모델 바인딩 본문 숨김)·
  폼 컨트롤러(요청 중 편집 유지·요약 사용자 저장 거부)·테마 모드(기본·로그아웃 Dark)·로그인 뒤 프로필 조회, **테마**(`AppTheme.dark` 고정·`AppTheme.light`의 밝은 팔레트·밝은 글자 대비 4.5:1),
  **팀 코드 계약**(앱 `kAvatarTeams` ↔ OpenAPI enum).

## 10. 남은 일

- 브라우저 육안 확인(밝은 테마 포함)은 서버 재시작 뒤 컨트롤러 확인 대상. 위젯 테스트와 골든 렌더(임시)로 배치만 확인했다.
- 컨트롤러·플랫폼·단위·타임존·선호 게임은 저장만 한다. 쓰는 곳은 해당 Phase(분석·필터 P10, 텔레메트리 단위 P9)에서 정한다.
- 이메일 동시 변경 경합(같은 이메일을 두 계정이 동시에)은 unique index가 막고 500이 된다 — 가입과 같은 기존 동작.
