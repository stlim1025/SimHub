import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session_repository.dart';
import '../domain/session_models.dart';

/// 내 활성 세션 상태. 체크인/체크아웃으로 갱신한다.
class SessionController extends AsyncNotifier<DriveSession?> {
  @override
  Future<DriveSession?> build() => ref.watch(sessionRepositoryProvider).getActive();

  Future<void> checkIn(String rigCode, String gameCode) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(sessionRepositoryProvider).checkIn(rigCode, gameCode),
    );
  }

  Future<void> checkOut() async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    await ref.read(sessionRepositoryProvider).checkOut(current.sessionId);
    state = const AsyncData(null);
  }
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, DriveSession?>(SessionController.new);
