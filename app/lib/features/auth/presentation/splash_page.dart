import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';

/// 세션 복원 중 표시되는 스플래시. 라우터 redirect가 복원 완료 후 login 또는 Dashboard(/)로 보낸다.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppConfig.brandName, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
