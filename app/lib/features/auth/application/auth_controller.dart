import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/auth_events.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// 인증 상태(현재 사용자, null=로그아웃). 초기 build는 저장된 토큰으로 세션 복원.
/// login/register는 전역 로딩을 유발하지 않고(라우터가 splash로 튀지 않도록) 성공 시에만 상태를 갱신한다.
/// 상태의 사용자는 `GET /me`의 프로필(이메일·설정 포함)이다 — 사이드바 사진·테마가 이 값을 따른다(docs/14 §8).
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
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.login(email, password);
    await ref.read(tokenStoreProvider).save(token: result.accessToken, expiresAt: result.expiresAt);
    state = AsyncData(await _profileOr(repo, result.user));
  }

  Future<void> register(String email, String password, String displayName) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.register(email, password, displayName);
    final result = await repo.login(email, password);
    await ref.read(tokenStoreProvider).save(token: result.accessToken, expiresAt: result.expiresAt);
    state = AsyncData(await _profileOr(repo, result.user));
  }

  /// 프로필 저장·이메일 변경 뒤 서버가 돌려준 최신 프로필로 바꾼다(로그아웃 상태면 무시).
  void applyProfile(AppUser user) {
    if (state.valueOrNull == null) {
      return;
    }
    state = AsyncData(user);
  }

  Future<void> logout() async {
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(null);
  }

  /// 로그인 직후 전체 프로필(`GET /me`)을 읽는다. 로그인 응답에는 이메일·설정이 없다.
  /// 이미 로그인은 성공했으므로 프로필 조회가 실패해도 요약 사용자(기본 설정)로 진행하고, 다음 세션 복원 때 다시 읽는다.
  Future<AppUser> _profileOr(AuthRepository repo, AppUser summary) async {
    try {
      return await repo.me();
    } catch (e) {
      debugPrint('로그인 후 프로필 조회 실패(기본 설정으로 계속): $e');
      return summary;
    }
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);
