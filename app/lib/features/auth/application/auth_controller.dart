import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/auth_events.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// 세션 복원 때 `GET /me`가 401이 아닌 이유(서버 재시작·네트워크 끊김·응답 지연)로 실패하면 이 간격으로 다시 묻는다.
/// 그동안 토큰은 지우지 않는다 — 배포로 서버가 잠깐 내려간 사이 새로고침해도 로그인이 풀리지 않게. 테스트는 짧게 덮어쓴다.
final authRestoreRetryDelaysProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ],
);

/// 인증 상태(현재 사용자, null=로그아웃). 초기 build는 저장된 토큰으로 세션 복원.
/// 토큰을 지우고 로그아웃하는 건 서버가 401(토큰이 무효)을 줄 때뿐이다. 그 밖의 실패는 [authRestoreRetryDelaysProvider] 간격으로
/// 다시 묻고, 끝내 실패하면 오류 상태로 남아 스플래시가 다시 시도를 띄운다(토큰은 그대로).
/// login/register는 전역 로딩을 유발하지 않고(라우터가 splash로 튀지 않도록) 성공 시에만 상태를 갱신한다.
/// 상태의 사용자는 `GET /me`의 프로필(이메일·설정 포함)이다 — 사이드바 사진·테마가 이 값을 따른다(docs/14 §8).
class AuthController extends AsyncNotifier<AppUser?> {
  static const int _unauthorized = 401;

  @override
  Future<AppUser?> build() async {
    // 401 → 강제 로그아웃 구독.
    final sub = ref.watch(authEventsProvider).onUnauthorized.listen((_) {
      state = const AsyncData(null);
    });
    ref.onDispose(sub.cancel);

    final store = ref.watch(tokenStoreProvider);
    final repo = ref.watch(authRepositoryProvider);
    final delays = ref.watch(authRestoreRetryDelaysProvider);
    if (!await store.hasValidToken()) {
      return null;
    }

    for (var attempt = 0;; attempt++) {
      try {
        return await repo.me();
      } on ApiException catch (e) {
        if (e.statusCode == _unauthorized) {
          await store.clear();
          return null;
        }
        if (attempt >= delays.length) {
          rethrow;
        }
      } catch (_) {
        if (attempt >= delays.length) {
          rethrow;
        }
      }
      await Future<void>.delayed(delays[attempt]);
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

  /// 전체 프로필(`GET /me`)을 다시 읽는다 — 로그인 직후 조회가 실패해 요약 사용자만 있을 때 설정 화면이 부른다.
  /// 인증 상태를 로딩으로 바꾸지 않는다(라우터가 스플래시로 튀지 않게). 실패하면 [ApiException] 등을 그대로 던진다.
  Future<void> reloadProfile() async {
    if (state.valueOrNull == null) {
      return;
    }
    applyProfile(await ref.read(authRepositoryProvider).me());
  }

  Future<void> logout() async {
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(null);
  }

  /// 로그인 직후 전체 프로필(`GET /me`)을 읽는다. 로그인 응답에는 이메일·설정이 없다.
  /// 이미 로그인은 성공했으므로 프로필 조회가 실패해도 요약 사용자로 진행한다. 요약 사용자는 [AppUser.isProfileLoaded]가 false라
  /// 설정 화면이 프로필을 다시 읽기 전에는 저장할 수 없다(기본값으로 실제 설정을 덮어쓰지 않게).
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
