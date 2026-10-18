import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 새 행 강조가 옅어져 사라지는 시간(D-50, docs/15 §9 "잠깐 강조").
const Duration kFreshHighlightDuration = Duration(seconds: 3);

/// 처음 그려질 때 강조색([AppColors.freshRow])으로 칠했다가 [kFreshHighlightDuration] 동안 투명해지는 배경.
/// [child]의 바탕이 투명해야 보인다(표 행의 `Material`은 기본이 투명).
class FreshHighlight extends StatelessWidget {
  const FreshHighlight({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: kFreshHighlightDuration,
      curve: Curves.easeIn,
      builder: (context, strength, child) => ColoredBox(
        color: AppColors.freshRow.withValues(alpha: AppColors.freshRow.a * strength),
        child: child,
      ),
      child: child,
    );
  }
}
