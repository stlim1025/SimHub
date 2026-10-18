import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/avatar_teams.dart';
import 'team_avatar.dart';

const double _choiceSize = 52;
const double _ringWidth = 3;
const double _ringGap = 3;
const double _spacing = 12;

/// 프로필 사진 고르기(docs/14 §4): "사진 없음"(이름 첫 글자) + 팀 색 원 10개. 고른 원에 강조색 테두리를 두른다.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({super.key, required this.selected, required this.displayName, required this.onSelected});

  /// 고른 팀 코드. null이면 "사진 없음".
  final String? selected;
  final String displayName;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: _spacing,
      runSpacing: _spacing,
      children: [
        _AvatarChoice(
          key: const ValueKey('avatar-none'),
          tooltip: '사진 없음(이름 첫 글자)',
          selected: selected == null,
          onTap: () => onSelected(null),
          child: TeamAvatar(teamCode: null, displayName: displayName, size: _choiceSize),
        ),
        for (final team in kAvatarTeams)
          _AvatarChoice(
            key: ValueKey('avatar-${team.code}'),
            tooltip: team.name,
            selected: selected == team.code,
            onTap: () => onSelected(team.code),
            child: TeamAvatar(teamCode: team.code, displayName: displayName, size: _choiceSize),
          ),
      ],
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    super.key,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(_ringGap),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.accent : Colors.transparent,
                width: _ringWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
