# 팀 로고 (프로필 사진, D-48)

이 폴더에 팀 로고 이미지를 넣으면 프로필 사진(사이드바·계정 설정의 "프로필 사진")이 팀 색 원 + 코드 대신 **팀 색 원 안의 로고**로 보입니다.
파일이 없는 팀은 지금처럼 팀 색 원 + 코드(`FER` 등)로 그립니다. 자세한 설계는 `docs/15-lap-detail-telemetry.md` §2.4.

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

- 이 폴더 바로 아래의 `.png`만 로고로 씁니다. 이 `README.md`·하위 폴더·다른 확장자는 무시합니다.
- 일부 팀만 넣어도 됩니다.

## 권장 형식

- **배경이 투명한 PNG**, 정사각형 약 **128 × 128px**(원 안에 여백을 두고 맞춰 그립니다).
- 밝은 팀 색(Mercedes·McLaren·Williams·Sauber·Haas) 위에서도 보이도록 로고 색을 고릅니다.

## 넣는 방법

1. 이 폴더에 파일을 복사합니다(예: `app/assets/team_logos/FER.png`).
2. 앱을 다시 빌드합니다(`flutter run` / `flutter build web`). 앱은 시작할 때 자산 목록(AssetManifest)에서 이 폴더의 파일을 읽어
   "로고가 있는 팀"을 정하므로, 없는 파일을 요청하지 않습니다.

## 저장소에 넣지 않는 이유

팀 로고는 각 팀의 **상표**입니다. 그래서 로고 파일은 저장소에 커밋하지 않습니다(이 폴더의 `.gitignore`가 `*.png`를 막습니다).
사용 승인을 받아 저장소에 넣기로 하면 `.gitignore`를 지우고 결정 기록(`docs/08`)을 갱신합니다.
