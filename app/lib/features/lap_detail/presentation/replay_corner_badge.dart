import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/lap_corners.dart';

const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 8, vertical: 3);
const double _radius = 4;
const double _fontSize = 12;
const double _opacity = 0.85;

/// 다시보기 구석에 띄우는 지금 코너 이름(`T7`). 직선이면 아무것도 그리지 않는다.
class ReplayCornerBadge extends StatelessWidget {
  const ReplayCornerBadge({super.key, required this.corner});

  final LapCorner? corner;

  @override
  Widget build(BuildContext context) {
    final c = corner;
    if (c == null) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('replay-corner'),
      padding: _padding,
      decoration: BoxDecoration(
        color: AppColors.replayBroadcastPanel.withValues(alpha: _opacity),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Text(
        c.label,
        style: DefaultTextStyle.of(context).style.copyWith(
              color: AppColors.replayHudText,
              fontSize: _fontSize,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.none,
            ),
      ),
    );
  }
}
