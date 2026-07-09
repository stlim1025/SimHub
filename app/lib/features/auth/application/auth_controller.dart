import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/auth_events.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// 인증 상태(현재 사용자, null=로그아웃). 초기 build는 저장된 토큰으로 세션 복원.
/// login/register는 전역 로딩을 유발하지 않고(라우터가 splash로 튀지 않도록) 성공 시에만 상태를 갱신한다.
class AuthController extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    // 401 → 강제 로그아웃 구독.
    final sub = ref.watch(authEventsProvider).onUnauthorized.listen((_) {
      state = const AsyncData(null);
    });
    ref.onDispose(sub.cancel);

    final store = ref.watch(tokenStoreProvider);
    if (!await store.hasValidToken()) {
      return null;
    }

    try {
      return await ref.watch(authRepositoryProvider).me();
    } catch (_) {
      await store.clear();
      return null;
    }
  }

  Future<void> login(String email, String password) async {
    final result = await ref.read(authRepositoryProvider).login(email, password);
    await ref.read(tokenStoreProvider).save(token: result.accessToken, expiresAt: result.expiresAt);
    state = AsyncData(result.user);
  }

  Future<void> register(String email, String password, String displayName) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.register(email, password, displayName);
    final result = await repo.login(email, password);
    await ref.read(tokenStoreProvider).save(token: result.accessToken, expiresAt: result.expiresAt);
    state = AsyncData(result.user);
  }

  Future<void> logout() async {
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);
