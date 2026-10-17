import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../util/hex_color.dart';

const double _barWidth = 4;
const double _barHeight = 24;

/// 이름 왼쪽에 놓는 팀 색 막대. [colorHex]는 API의 `#RRGGBB`이고, 잘못된 값이면 `textMuted`로 칠한다.
class TeamColorBar extends StatelessWidget {
  const TeamColorBar({super.key, required this.colorHex});

  final String colorHex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _barWidth,
      height: _barHeight,
      decoration: BoxDecoration(
        color: parseHexColor(colorHex, fallback: AppColors.textMuted),
        borderRadius: BorderRadius.circular(_barWidth / 2),
      ),
    );
  }
}
