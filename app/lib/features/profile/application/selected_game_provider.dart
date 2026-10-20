import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../auth/application/auth_controller.dart';

/// 앱이 보여 줄 게임(계정 설정의 "게임" = 저장된 프로필의 `preferredGame`). 설정이 없으면(로그아웃·복원 중) [AppConfig.defaultGameCode].
/// 리더보드·랩·내 트랙·시즌·세션 목록이 이 값을 watch하므로, 설정에서 다른 게임을 저장하면 그 게임의 데이터로 다시 읽는다.
final selectedGameProvider = Provider<String>((ref) {
  final preferred = ref.watch(authControllerProvider.select((auth) => auth.valueOrNull?.preferences.preferredGame));
  return preferred ?? AppConfig.defaultGameCode;
});
