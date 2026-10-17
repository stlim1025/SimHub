import 'package:flutter/material.dart';

import '../network/api_exception.dart';

/// 조회 실패 안내 + 다시 시도 버튼. [error]가 [ApiException]이면 그 메시지를, 아니면 [fallbackMessage]를 보여준다.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.error,
    required this.fallbackMessage,
    required this.onRetry,
  });

  final Object error;
  final String fallbackMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException ? (error as ApiException).message : fallbackMessage;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
