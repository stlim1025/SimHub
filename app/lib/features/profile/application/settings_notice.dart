import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 계정 설정 화면 위쪽 성공 배너 문구(변경 사항 저장·이메일 변경). null = 배너 없음.
/// 화면을 떠나면 사라지고(autoDispose), 다시 수정하기 시작하면 화면이 감춘다.
class SettingsNotice extends AutoDisposeNotifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}

final settingsNoticeProvider = AutoDisposeNotifierProvider<SettingsNotice, String?>(SettingsNotice.new);
