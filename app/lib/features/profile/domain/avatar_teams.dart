import 'package:flutter/painting.dart';

import '../../../core/theme/app_colors.dart';

/// 프로필 사진으로 고를 수 있는 팀 하나(docs/14 §4). 실제 팀 로고는 상표라 쓰지 않고, 팀 색 원 + [code]로 그린다.
class AvatarTeam {
  const AvatarTeam({required this.code, required this.name, required this.color, this.lightColor = false});

  /// 서버 계약 코드(2~3자, 백엔드 `AvatarTeamCodes`·OpenAPI `AvatarTeamCode`와 같다).
  final String code;

  /// 화면 툴팁에 쓰는 팀 이름.
  final String name;
  final Color color;

  /// 밝은 팀 색이라 코드 글자를 어둡게 써야 하는지.
  final bool lightColor;

  /// 원 위 코드 글자색.
  Color get onColor => lightColor ? AppColors.onTeamLight : AppColors.onAccent;
}

/// 고를 수 있는 팀 전체(화면 표시 순서). 코드 목록은 이곳 한 곳에만 둔다.
const List<AvatarTeam> kAvatarTeams = [
  AvatarTeam(code: 'MER', name: 'Mercedes', color: AppColors.teamMercedes, lightColor: true),
  AvatarTeam(code: 'FER', name: 'Ferrari', color: AppColors.teamFerrari),
  AvatarTeam(code: 'RBR', name: 'Red Bull Racing', color: AppColors.teamRedBull),
  AvatarTeam(code: 'MCL', name: 'McLaren', color: AppColors.teamMcLaren, lightColor: true),
  AvatarTeam(code: 'AST', name: 'Aston Martin', color: AppColors.teamAstonMartin),
  AvatarTeam(code: 'ALP', name: 'Alpine', color: AppColors.teamAlpine),
  AvatarTeam(code: 'WIL', name: 'Williams', color: AppColors.teamWilliams, lightColor: true),
  AvatarTeam(code: 'RB', name: 'Racing Bulls', color: AppColors.teamRacingBulls),
  AvatarTeam(code: 'SAU', name: 'Sauber', color: AppColors.teamSauber, lightColor: true),
  AvatarTeam(code: 'HAA', name: 'Haas', color: AppColors.teamHaas, lightColor: true),
];

/// 코드 → 팀. 모르는 코드(서버가 먼저 추가한 경우 등)나 null이면 null(이름 첫 글자를 보인다).
AvatarTeam? avatarTeamOf(String? code) {
  if (code == null) {
    return null;
  }
  for (final team in kAvatarTeams) {
    if (team.code == code) {
      return team;
    }
  }
  return null;
}
