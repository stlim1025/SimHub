import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

const double _cardPadding = 32;
const double _messageActionGap = 12;

/// 목록이 비었을 때의 안내 카드. [actionLabel]·[actionPath]를 함께 주면 그 경로로 가는 링크 버튼을 붙인다.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.message, this.actionLabel, this.actionPath})
      : assert(
          (actionLabel == null) == (actionPath == null),
          'actionLabel과 actionPath는 함께 주거나 함께 생략해야 합니다.',
        );

  final String message;
  final String? actionLabel;
  final String? actionPath;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final path = actionPath;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              if (label != null && path != null) ...[
                const SizedBox(height: _messageActionGap),
                TextButton(onPressed: () => context.go(path), child: Text(label)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
