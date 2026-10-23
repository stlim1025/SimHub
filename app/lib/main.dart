import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/application/theme_mode_provider.dart';

/// 서킷 윤곽 데이터(bacinger/f1-circuits)의 MIT 라이선스 고지 파일.
const String _trackOutlinesLicenseAsset = 'assets/track_outlines/LICENSE-f1-circuits.md';

/// 실측 트랙 폭 데이터(TUMFTM/racetrack-database)의 LGPL-3.0 라이선스 파일.
const String _trackWidthsLicenseAsset = 'assets/track_widths/LICENSE-racetrack-database.txt';

void main() {
  // MIT 조건: 앱에 넣은 서킷 윤곽 데이터의 저작권 고지를 라이선스 목록에 함께 싣는다.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['f1-circuits'], await rootBundle.loadString(_trackOutlinesLicenseAsset));
    yield LicenseEntryWithLineBreaks(['racetrack-database'], await rootBundle.loadString(_trackWidthsLicenseAsset));
  });
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
