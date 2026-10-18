import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_palette.dart';

/// 404(남의 것이거나 없는 대상) 상태. 다시 시도는 의미가 없으므로 목록으로 가는 링크만 둔다.
class NotFoundState extends StatelessWidget {
  const NotFoundState({
    super.key,
    required this.message,
    required this.backLabel,
    required this.backPath,
  });

  /// 예) `찾을 수 없는 세션입니다.`
  final String message;

  /// 목록 링크의 글자. 예) `Sessions`
  final String backLabel;

  /// 목록 링크가 여는 경로. 예) `/sessions`
  final String backPath;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: context.palette.textMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go(backPath),
              child: Text(backLabel),
            ),
          ],
        ),
      ),
    );
  }
}
