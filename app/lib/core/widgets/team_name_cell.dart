import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

const double _dotSize = 10;
const double _dotGap = 8;

/// 팀 이름 글자에 들어 있으면 그 팀 색으로 보는 낱말(소문자). 앞에서부터 맞춰 본다 —
/// `Racing Bulls`·`Visa Cash App RB`가 `Red Bull`보다 먼저 와야 한다. 색 값은 [AppColors]의 팀 색(백엔드 `TeamCatalog`)과 같다.
const List<(String, Color)> _teamNameColors = [
  ('racing bulls', AppColors.teamRacingBulls),
  ('visa', AppColors.teamRacingBulls),
  ('red bull', AppColors.teamRedBull),
  ('mercedes', AppColors.teamMercedes),
  ('ferrari', AppColors.teamFerrari),
  ('mclaren', AppColors.teamMcLaren),
  ('aston', AppColors.teamAstonMartin),
  ('alpine', AppColors.teamAlpine),
  ('williams', AppColors.teamWilliams),
  ('kick', AppColors.teamSauber),
  ('sauber', AppColors.teamSauber),
  ('audi', AppColors.teamAudi),
  ('cadillac', AppColors.teamCadillac),
  ('haas', AppColors.teamHaas),
];

/// `RB` 한 낱말로 오는 팀 이름(Racing Bulls).
const String _racingBullsShort = 'rb';

/// 팀 이름 글자(예: `Aston Martin`, `Red Bull Racing`) → 팀 색. 모르는 이름·null이면 null(순수 함수).
/// 셋업 모음·트랙 화면처럼 서버가 팀을 이름 글자로만 줄 때 쓴다.
Color? teamColorOfName(String? teamName) {
  final name = teamName?.trim().toLowerCase();
  if (name == null || name.isEmpty) {
    return null;
  }
  if (name == _racingBullsShort) {
    return AppColors.teamRacingBulls;
  }
  for (final (word, color) in _teamNameColors) {
    if (name.contains(word)) {
      return color;
    }
  }
  return null;
}

/// 팀 색 점 + 팀 이름(한 줄 말줄임). 색을 모르면 흐린 점. 이름이 없으면 `-`.
class TeamNameCell extends StatelessWidget {
  const TeamNameCell({super.key, required this.teamName});

  final String? teamName;

  static const String _noValue = '-';

  @override
  Widget build(BuildContext context) {
    final name = teamName;
    if (name == null || name.trim().isEmpty) {
      return const Text(_noValue);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(shape: BoxShape.circle, color: teamColorOfName(name) ?? context.palette.textMuted),
        ),
        const SizedBox(width: _dotGap),
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
