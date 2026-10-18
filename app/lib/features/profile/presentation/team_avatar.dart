import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/team_logos_provider.dart';
import '../domain/avatar_teams.dart';

/// 프로필 사진(docs/14 §4, D-48): 고른 팀이 있으면 팀 색 원 — `assets/team_logos/{코드}.png`가 있으면 그 로고, 없으면 팀 코드.
/// 팀을 고르지 않았으면 강조색 원 + 이름 첫 글자. 로고 파일은 상표라 저장소에 넣지 않는다(사용자가 넣는다).
class TeamAvatar extends ConsumerWidget {
  const TeamAvatar({super.key, required this.teamCode, required this.displayName, this.size = 36});

  /// 팀 코드(모르는 코드·null이면 이름 첫 글자).
  final String? teamCode;
  final String displayName;
  final double size;

  /// 원 지름 대비 글자 크기 비율.
  static const double _fontScale = 0.36;

  /// 원 지름 대비 로고 둘레 여백 비율.
  static const double _logoPaddingScale = 0.14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = avatarTeamOf(teamCode);
    final logo = team == null ? null : ref.watch(teamLogoPathsProvider).valueOrNull?[team.code];
    final label = Text(
      team?.code ?? _initialOf(displayName),
      maxLines: 1,
      style: TextStyle(
        color: team?.onColor ?? AppColors.onAccent,
        fontSize: size * _fontScale,
        fontWeight: FontWeight.bold,
      ),
    );
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: team?.color ?? AppColors.accent),
      child: logo == null
          ? label
          : Padding(
              padding: EdgeInsets.all(size * _logoPaddingScale),
              // 파일을 읽지 못하면(손상 등) 코드로 대신한다. 로고에는 읽기 도구용 팀 이름을 붙인다.
              child: Image.asset(
                logo,
                fit: BoxFit.contain,
                semanticLabel: team?.name,
                errorBuilder: (_, _, _) => label,
              ),
            ),
    );
  }
}

/// 이름의 첫 글자(대문자). 이름이 비면 `?`.
String _initialOf(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}
