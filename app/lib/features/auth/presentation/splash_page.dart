import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../application/auth_controller.dart';

/// 서버에 끝내 닿지 못해 세션 복원이 멈췄을 때 문구(저장된 로그인은 그대로 둔다).
const String _restoreFailedMessage = '서버에 연결하지 못했어요. 로그인은 그대로 유지돼요.';

/// 세션 복원 중 표시되는 스플래시. 라우터 redirect가 복원 완료 후 login 또는 Dashboard(/)로 보낸다.
/// 기다리는 동안 화면 맨 위 전체 폭에 얇은 로딩 막대가 지나간다(F1Laps).
/// 서버가 401이 아닌 이유로 계속 응답하지 않으면(복원이 오류로 끝나면) 다시 시도를 띄운다 — 토큰은 지우지 않았다.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final error = auth.hasError && !auth.isLoading ? auth.error : null;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error == null) const PageLoadingBar(),
          Expanded(
            child: Center(
              child: error == null
                  ? Text(
                      AppConfig.brandName,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    )
                  : ErrorRetry(
                      error: error,
                      fallbackMessage: _restoreFailedMessage,
                      onRetry: () => ref.invalidate(authControllerProvider),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
