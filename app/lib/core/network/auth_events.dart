import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 인증 이벤트 버스. 네트워크 계층(401 감지)과 인증 컨트롤러의 결합을 끊는다(core는 feature를 import하지 않음).
class AuthEvents {
  final _controller = StreamController<void>.broadcast();

  /// 서버가 401을 반환해 세션이 무효화됐음을 알린다.
  Stream<void> get onUnauthorized => _controller.stream;

  void signalUnauthorized() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  void dispose() => _controller.close();
}

final authEventsProvider = Provider<AuthEvents>((ref) {
  final events = AuthEvents();
  ref.onDispose(events.dispose);
  return events;
});
