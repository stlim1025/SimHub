# 팀 로고 (프로필 사진, D-48)

팀 로고는 이제 **앱에 넣지 않고 서버에서 내보냅니다.** 이 폴더는 안내용으로만 남겨 둡니다(`pubspec.yaml`의 자산 목록에서도 뺐습니다).

서버 PC의 로고 폴더에 이미지를 넣으면 프로필 사진(사이드바·계정 설정의 "프로필 사진")이 팀 색 원 + 코드 대신 **팀 색 원 안의 로고**로 보입니다.
파일이 없는 팀·로고를 읽는 중·읽지 못했을 때는 지금처럼 팀 색 원 + 코드(`FER` 등)로 그립니다.

## 서버 설정

- 설정 키: `TeamLogos:Directory`(절대 경로). 운영 값은 `backend/src/SimCenter.Api/appsettings.Production.json`
  (`D:\Toy\SimCenterServer\team_logos`).
- 서버는 그 폴더의 `.png`를 `GET {API 주소}/team-logos/{코드}.png`로 로그인 없이 내보냅니다(하루 캐시, CORS 허용 오리진만).
- 설정이 없거나 폴더가 없으면 아무것도 내보내지 않고(앱은 코드 원), 서버는 그대로 뜹니다.
- 파일을 넣거나 바꾼 뒤 서버를 다시 시작할 필요는 없습니다(앱 빌드도 필요 없음). 브라우저 캐시 때문에 바뀐 로고는 최대 하루 뒤에 보일 수 있습니다.

## 파일 이름

파일 이름은 **팀 코드 + `.png`** 입니다(코드는 `lib/features/profile/domain/avatar_teams.dart`의 `kAvatarTeams`).

| 파일 | 팀 |
|---|---|
| `MER.png` | Mercedes |
| `FER.png` | Ferrari |
| `RBR.png` | Red Bull Racing |
| `MCL.png` | McLaren |
| `AST.png` | Aston Martin |
| `ALP.png` | Alpine |
| `WIL.png` | Williams |
| `RB.png` | Racing Bulls |
| `SAU.png` | Sauber |
| `HAA.png` | Haas |

- 일부 팀만 넣어도 됩니다.
- 앱은 코드를 대문자로 요청합니다(`FER.png`). 서버 PC(Windows)는 파일 이름의 대소문자를 가리지 않습니다.

## 권장 형식

- **배경이 투명한 PNG**, 정사각형 약 **128 × 128px**(원 안에 여백을 두고 맞춰 그립니다).
- 밝은 팀 색(Mercedes·McLaren·Williams·Sauber·Haas) 위에서도 보이도록 로고 색을 고릅니다.

## 저장소에 넣지 않는 이유

팀 로고는 각 팀의 **상표**이고 저장소는 공개입니다. 그래서 로고 파일은 저장소에 커밋하지 않습니다
(이 폴더의 `.gitignore`가 `*.png`를 막습니다 — 예전처럼 여기에 넣어 둔 파일이 실수로 올라가지 않게 그대로 둡니다).
사용 승인을 받아 저장소에 넣기로 하면 `.gitignore`를 지우고 결정 기록(`docs/08`)을 갱신합니다.
