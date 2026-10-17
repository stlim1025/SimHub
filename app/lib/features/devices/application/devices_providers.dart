import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/devices_repository.dart';
import '../domain/device_models.dart';

/// 내 Agent 장치 목록. 화면을 다시 열면 새로 불러온다.
final agentDevicesProvider = FutureProvider.autoDispose<List<AgentDevice>>(
  (ref) => ref.watch(devicesRepositoryProvider).getDevices(),
);

/// 발급한 연결 코드(null=아직 발급 전). 발급이 실패하면 [AsyncError]가 되며, Riverpod은 이때
/// 직전 값(예: 만료된 코드)을 `valueOrNull`에 그대로 남긴다. 그래서 화면은 `value`보다 먼저
/// `hasError`를 확인해 오류를 보여줘야 한다(그렇지 않으면 실패가 만료된 코드 뒤에 가려진다).
/// 화면을 오가도 코드는 유지되지만, 사용자가 바뀌면(로그아웃·다른 계정) 지운다.
class PairingCodeController extends AsyncNotifier<PairingCode?> {
  @override
  FutureOr<PairingCode?> build() {
    // 로그인한 사용자가 바뀌면 이 notifier가 다시 build되어 이전 사용자의 코드가 사라진다.
    ref.watch(authControllerProvider.select((auth) => auth.valueOrNull?.userId));
    return null;
  }

  /// 새 코드를 발급한다. 발급 중에 다시 호출하면 무시한다(중복 요청 방지).
  Future<void> issue() async {
    if (state.isLoading) {
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(devicesRepositoryProvider).issuePairingCode());
  }
}

final pairingCodeControllerProvider =
    AsyncNotifierProvider<PairingCodeController, PairingCode?>(PairingCodeController.new);
