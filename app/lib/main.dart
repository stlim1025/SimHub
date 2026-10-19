import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/application/theme_mode_provider.dart';

void main() {
  runApp(const ProviderScope(child: SimCenterApp()));
}

class SimCenterApp extends ConsumerWidget {
  const SimCenterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConfig.brandName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // 사용자 테마 설정(docs/14 §7). 기본·로그아웃·스플래시·세션 복원 중은 Dark(D-40), System을 고르면 기기 밝기를 따른다.
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
    );
  }
}
