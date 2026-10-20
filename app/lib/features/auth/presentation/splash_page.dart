import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/widgets/page_loading_bar.dart';

/// 세션 복원 중 표시되는 스플래시. 라우터 redirect가 복원 완료 후 login 또는 Dashboard(/)로 보낸다.
/// 기다리는 동안 화면 맨 위 전체 폭에 얇은 로딩 막대가 지나간다(F1Laps).
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageLoadingBar(),
          Expanded(
            child: Center(
              child: Text(
                AppConfig.brandName,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
