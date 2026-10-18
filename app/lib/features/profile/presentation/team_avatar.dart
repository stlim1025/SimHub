import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/avatar_teams.dart';

/// 프로필 사진(docs/14 §4): 고른 팀이 있으면 팀 색 원 + 팀 코드, 없으면 강조색 원 + 이름 첫 글자.
/// 실제 팀 로고는 상표라 쓰지 않는다.
class TeamAvatar extends StatelessWidget {
  const TeamAvatar({super.key, required this.teamCode, required this.displayName, this.size = 36});

  /// 팀 코드(모르는 코드·null이면 이름 첫 글자).
  final String? teamCode;
  final String displayName;
  final double size;

  /// 원 지름 대비 글자 크기 비율.
  static const double _fontScale = 0.36;

  @override
  Widget build(BuildContext context) {
    final team = avatarTeamOf(teamCode);
    final label = team?.code ?? _initialOf(displayName);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: team?.color ?? AppColors.accent),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: team?.onColor ?? AppColors.onAccent,
          fontSize: size * _fontScale,
          fontWeight: FontWeight.bold,
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
