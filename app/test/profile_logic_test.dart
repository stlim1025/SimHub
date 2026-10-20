import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/storage/token_store.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/data/auth_repository.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/profile/application/profile_form_controller.dart';
import 'package:simcenter_app/features/profile/application/theme_mode_provider.dart';
import 'package:simcenter_app/features/profile/data/profile_repository.dart';
import 'package:simcenter_app/features/profile/domain/avatar_teams.dart';
import 'package:simcenter_app/features/profile/domain/time_zones.dart';

import 'support/fakes.dart';

/// 메모리 토큰 보관소(secure storage 없이).
class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> save({required String token, required DateTime expiresAt}) async => this.token = token;

  @override
  Future<bool> hasValidToken() async => token != null;

  @override
  Future<void> clear() async => token = null;
}

/// 로그인은 요약 사용자만, `me()`는 전체 프로필(또는 오류)을 돌려주는 인증 저장소.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.meError});

  /// null이 아니면 me()가 이 오류로 실패한다. 테스트 도중에 바꿀 수 있다.
  Object? meError;
  int meCalls = 0;

  @override
  Future<LoginResult> login(String email, String password) async => LoginResult(
        accessToken: 'jwt',
        expiresAt: DateTime.utc(2026, 10, 19),
        user: const AppUser(userId: 'u1', displayName: '홍길동'),
      );

  @override
  Future<void> register(String email, String password, String displayName) async {}

  @override
  Future<AppUser> me() async {
    meCalls++;
    final error = meError;
    if (error != null) {
      throw error;
    }
    return AppUser.fromJson(_meJson);
  }
}

const _meJson = <String, dynamic>{
  'userId': 'u1',
  'email': 'driver@simcenter.test',
  'displayName': '홍길동',
  'showOnLeaderboard': false,
  'avatarTeam': 'MCL',
  'preferredGame': 'F1_25',
  'controller': 'Gamepad',
  'console': 'PlayStation',
  'units': 'Imperial',
  'timeZoneId': 'Europe/London',
  'theme': 'Light',
};

DioException _dioError(int status, Object data) {
  final options = RequestOptions(path: '/me/email');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: data),
  );
}

ProviderContainer _container({AppUser? user = settingsUser, FakeProfileRepository? repo}) {
  final container = ProviderContainer(overrides: [
    fakeAuth(user),
    profileRepositoryProvider.overrideWithValue(repo ?? FakeProfileRepository()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('UserPreferences', () {
    test('GET /me의 설정 필드를 읽고 PUT 본문으로 같은 값을 쓴다', () {
      final user = AppUser.fromJson(_meJson);
      final prefs = user.preferences;

      expect(user.email, 'driver@simcenter.test');
      expect(prefs.showOnLeaderboard, isFalse);
      expect(prefs.avatarTeam, 'MCL');
      expect(prefs.controller, ControllerType.gamepad);
      expect(prefs.console, ConsolePlatform.playStation);
      expect(prefs.units, UnitSystem.imperial);
      expect(prefs.timeZoneId, 'Europe/London');
      expect(prefs.theme, ThemePreference.light);
      expect(prefs.toJson(), {
        'showOnLeaderboard': false,
        'avatarTeam': 'MCL',
        'preferredGame': 'F1_25',
        'controller': 'Gamepad',
        'console': 'PlayStation',
        'units': 'Imperial',
        'timeZoneId': 'Europe/London',
        'theme': 'Light',
      });
    });

    test('필드가 없거나(로그인 요약) 모르는 값이면 기본값', () {
      final summary = AppUser.fromJson({'userId': 'u1', 'displayName': '홍길동'});
      expect(summary.preferences, UserPreferences.defaults);
      expect(summary.preferences.showOnLeaderboard, isTrue);
      expect(summary.preferences.controller, ControllerType.wheel);
      expect(summary.preferences.theme, ThemePreference.dark); // D-40: 기본은 어두운 테마.

      final odd = UserPreferences.fromJson({'controller': 'Joystick', 'theme': 'light'});
      expect(odd.controller, ControllerType.wheel);
      expect(odd.theme, ThemePreference.light); // 대소문자 무시.
    });

    test('copyWith(clearAvatar)로 사진을 지우고, 같은 값이면 == 이다', () {
      final withAvatar = UserPreferences.defaults.copyWith(avatarTeam: 'FER');
      expect(withAvatar == UserPreferences.defaults, isFalse);
      expect(withAvatar.copyWith(clearAvatar: true), UserPreferences.defaults);
      expect(withAvatar.copyWith(clearAvatar: true).hashCode, UserPreferences.defaults.hashCode);
    });
  });

  group('프로필 사진·타임존 목록', () {
    test('팀 코드는 백엔드 AvatarTeamCodes와 같은 10개다', () {
      expect(
        [for (final t in kAvatarTeams) t.code],
        ['MER', 'FER', 'RBR', 'MCL', 'AST', 'ALP', 'WIL', 'RB', 'AUD', 'HAA'],
      );
      expect(avatarTeamOf('MCL')!.name, 'McLaren');
      expect(avatarTeamOf('XYZ'), isNull);
      expect(avatarTeamOf(null), isNull);
    });

    test('타임존 목록은 필수 8개를 담고, 목록에 없는 현재 값도 잃지 않는다', () {
      for (final id in const [
        'Asia/Seoul', 'UTC', 'Europe/London', 'Europe/Berlin',
        'America/New_York', 'America/Los_Angeles', 'Asia/Tokyo', 'Australia/Sydney',
      ]) {
        expect(kTimeZoneIds, contains(id));
      }
      expect(timeZoneChoices('Asia/Seoul'), kTimeZoneIds);
      expect(timeZoneChoices('Africa/Cairo').first, 'Africa/Cairo');
    });
  });

  group('ApiException 필드 오류', () {
    test('검증 실패(400)는 필드별 첫 메시지를 담고 그 메시지를 쓴다', () {
      final e = ApiException.fromDio(_dioError(400, {
        'type': 'https://simcenter/errors/validation',
        'detail': 'Validation failed.',
        'errors': {
          'currentPassword': ['현재 비밀번호가 올바르지 않습니다.'],
        },
      }));

      expect(e.statusCode, 400);
      expect(e.fieldErrors, {'currentPassword': '현재 비밀번호가 올바르지 않습니다.'});
      expect(e.message, '현재 비밀번호가 올바르지 않습니다.');
    });

    test('필드 오류가 없으면 detail을 쓴다(409)', () {
      final e = ApiException.fromDio(_dioError(409, {
        'type': 'https://simcenter/errors/conflict',
        'detail': '이미 사용 중인 이메일입니다.',
      }));

      expect(e.fieldErrors, isEmpty);
      expect(e.message, '이미 사용 중인 이메일입니다.');
    });

    test('우리 서버 문서가 아닌 모델 바인딩 400은 키·.NET 타입 이름을 보이지 않고 일반 메시지를 쓴다', () {
      final e = ApiException.fromDio(_dioError(400, {
        'type': 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
        'title': 'One or more validation errors occurred.',
        'errors': {
          r'$.showOnLeaderboard': [r'The JSON value could not be converted to System.Nullable`1[System.Boolean].'],
        },
      }));

      expect(e.fieldErrors, isEmpty);
      expect(e.message, '요청이 올바르지 않아요.');
      expect(e.message, isNot(contains('System.')));
    });
  });

  group('ProfileFormController', () {
    test('편집하면 바뀐 상태가 되고 취소하면 저장된 값으로 돌아간다', () {
      final container = _container();
      final form = container.read(profileFormControllerProvider.notifier);
      final sub = container.listen(profileFormControllerProvider, (_, _) {});
      addTearDown(sub.close);

      form.setUnits(UnitSystem.imperial);
      form.setTimeZone('Asia/Tokyo');
      expect(container.read(profileFormControllerProvider).isDirty, isTrue);

      form.cancel();
      final state = container.read(profileFormControllerProvider);
      expect(state.isDirty, isFalse);
      expect(state.draft.preferences.units, UnitSystem.metric);
    });

    test('저장하면 서버 값이 저장된 값이 되고 인증 상태의 사용자도 바뀐다', () async {
      final repo = FakeProfileRepository();
      final container = _container(repo: repo);
      await container.read(authControllerProvider.future);
      final sub = container.listen(profileFormControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final form = container.read(profileFormControllerProvider.notifier);

      form.setDisplayName('  lemonary ');
      form.setTheme(ThemePreference.light);
      expect(await form.save(), isTrue);

      expect(repo.updates.single.displayName, 'lemonary');
      expect(container.read(profileFormControllerProvider).isDirty, isFalse);
      final user = container.read(authControllerProvider).value!;
      expect(user.displayName, 'lemonary');
      expect(user.preferences.theme, ThemePreference.light);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('저장하는 동안 더 고친 값은 저장 뒤에도 남고 다시 저장할 수 있다', () async {
      final repo = FakeProfileRepository()..updateGate = Completer<void>();
      final container = _container(repo: repo);
      await container.read(authControllerProvider.future);
      final sub = container.listen(profileFormControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final form = container.read(profileFormControllerProvider.notifier);

      form.setUnits(UnitSystem.imperial);
      final saving = form.save();
      expect(container.read(profileFormControllerProvider).saving, isTrue);
      form.setTimeZone('Asia/Tokyo'); // 요청 중 편집.
      repo.updateGate!.complete();
      expect(await saving, isTrue);

      final state = container.read(profileFormControllerProvider);
      expect(repo.updates.single.preferences.timeZoneId, 'Asia/Seoul'); // 보낸 값은 편집 전.
      expect(state.saved.preferences.units, UnitSystem.imperial);
      expect(state.draft.preferences.units, UnitSystem.imperial);
      expect(state.draft.preferences.timeZoneId, 'Asia/Tokyo');
      expect(state.canSave, isTrue);
    });

    test('바뀐 것이 없으면 저장 요청을 보내지 않는다', () async {
      final repo = FakeProfileRepository();
      final container = _container(repo: repo);
      final sub = container.listen(profileFormControllerProvider, (_, _) {});
      addTearDown(sub.close);

      expect(await container.read(profileFormControllerProvider.notifier).save(), isFalse);
      expect(repo.updates, isEmpty);
    });
  });

  group('테마 모드', () {
    test('설정 → ThemeMode', () {
      expect(themeModeOf(ThemePreference.light), ThemeMode.light);
      expect(themeModeOf(ThemePreference.dark), ThemeMode.dark);
      expect(themeModeOf(ThemePreference.system), ThemeMode.system);
      expect(themeModeOf(null), ThemeMode.dark); // D-40: 설정이 없으면 어두운 테마.
    });

    test('로그아웃 상태(로그인·스플래시)와 세션 복원 중은 어두운 테마다', () async {
      final container = _container(user: null);
      expect(container.read(themeModeProvider), ThemeMode.dark); // 복원 중(로딩).

      await container.read(authControllerProvider.future);
      expect(container.read(themeModeProvider), ThemeMode.dark); // 로그아웃.
    });

    test('기존·새 사용자(기본 설정)는 어두운 테마, 저장한 설정이 있으면 그 테마를 따른다', () async {
      final defaults = _container(user: settingsUser);
      await defaults.read(authControllerProvider.future);
      expect(defaults.read(themeModeProvider), ThemeMode.dark);

      final light = _container(user: AppUser.fromJson(_meJson));
      await light.read(authControllerProvider.future);
      expect(light.read(themeModeProvider), ThemeMode.light);
    });
  });

  group('AuthController 로그인', () {
    ProviderContainer authContainer(_FakeAuthRepository repo) {
      final container = ProviderContainer(overrides: [
        tokenStoreProvider.overrideWithValue(_MemoryTokenStore()),
        authRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('로그인 뒤 GET /me로 이메일·설정까지 읽는다', () async {
      final repo = _FakeAuthRepository();
      final container = authContainer(repo);
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).login('driver@simcenter.test', 'pw');

      final user = container.read(authControllerProvider).value!;
      expect(repo.meCalls, 1);
      expect(user.email, 'driver@simcenter.test');
      expect(user.preferences.avatarTeam, 'MCL');
    });

    test('로그인 뒤 프로필 조회가 실패하면 요약 사용자로 남고, 다시 읽기 전에는 기본값으로 저장하지 않는다', () async {
      final repo = _FakeAuthRepository(meError: ApiException('서버가 아파요.', statusCode: 500));
      final profiles = FakeProfileRepository();
      final container = ProviderContainer(overrides: [
        tokenStoreProvider.overrideWithValue(_MemoryTokenStore()),
        authRepositoryProvider.overrideWithValue(repo),
        profileRepositoryProvider.overrideWithValue(profiles),
      ]);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).login('driver@simcenter.test', 'pw');

      final partial = container.read(authControllerProvider).value!;
      expect(partial.displayName, '홍길동');
      expect(partial.isProfileLoaded, isFalse);

      // 요약 사용자의 기본값(공개 등)으로 실제 설정(비공개)을 덮어쓰지 않는다.
      final sub = container.listen(profileFormControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final form = container.read(profileFormControllerProvider.notifier);
      form.setUnits(UnitSystem.imperial);
      expect(container.read(profileFormControllerProvider).canSave, isFalse);
      expect(await form.save(), isFalse);
      expect(profiles.updates, isEmpty);

      // 다시 읽으면 서버의 실제 설정(비공개)이 들어오고 폼이 새로 열린다.
      repo.meError = null;
      await container.read(authControllerProvider.notifier).reloadProfile();

      final state = container.read(profileFormControllerProvider);
      expect(container.read(authControllerProvider).value!.isProfileLoaded, isTrue);
      expect(state.loaded, isTrue);
      expect(state.saved.preferences.showOnLeaderboard, isFalse);
      expect(state.isDirty, isFalse);
    });

    test('로그아웃 상태에서는 프로필 갱신을 무시한다', () async {
      final container = authContainer(_FakeAuthRepository());
      await container.read(authControllerProvider.future);

      container.read(authControllerProvider.notifier).applyProfile(settingsUser);

      expect(container.read(authControllerProvider).value, isNull);
    });
  });
}
