import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/devices_repository.dart';
import '../domain/device_models.dart';

/// 내 Agent 장치 목록. 화면을 다시 열면 새로 불러온다.
final agentDevicesProvider = FutureProvider.autoDispose<List<AgentDevice>>(
  (ref) => ref.watch(devicesRepositoryProvider).getDevices(),
);

/// 발급한 연결 코드(null=아직 발급 전). 오류는 [AsyncError]로 남아 화면이 메시지를 보여준다.
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
