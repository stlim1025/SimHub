import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// AI가 모는 차 이름 옆에 붙이는 작은 `AI` 배지.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'AI',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.palette.textMuted),
      ),
    );
  }
}
