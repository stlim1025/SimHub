import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_preferences.dart';

/// 사용자 테마 설정 → [ThemeMode](docs/14 §7). 설정이 없으면(로그아웃·스플래시·세션 복원 중) 어두운 테마다(D-40).
/// 사용자가 System을 고른 경우에만 기기 밝기를 따른다.
ThemeMode themeModeOf(ThemePreference? preference) => switch (preference) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.system => ThemeMode.system,
      ThemePreference.dark || null => ThemeMode.dark,
    };

/// 앱 전체 테마 모드. 저장된 프로필의 테마만 따른다(편집 중인 값은 저장해야 바뀐다).
final themeModeProvider = Provider<ThemeMode>((ref) {
  final preference = ref.watch(authControllerProvider.select((auth) => auth.valueOrNull?.preferences.theme));
  return themeModeOf(preference);
});
