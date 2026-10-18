import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/profile/data/profile_repository.dart';
import 'package:simcenter_app/features/profile/presentation/settings_page.dart';

import 'support/fakes.dart';

const _wide = Size(1000, 1600);
const _phone = Size(375, 1600);

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  FakeProfileRepository? repo,
  FakeRankingHub? hub,
  AppUser user = settingsUser,
  Size size = _wide,
}) async {
  setViewSize(tester, size);
  final container = ProviderContainer(overrides: [
    fakeAuth(user),
    profileRepositoryProvider.overrideWithValue(repo ?? FakeProfileRepository(user: user)),
    rankingHubClientProvider.overrideWithValue(hub ?? FakeRankingHub()),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: SettingsPage())),
  ));
  await tester.pumpAndSettle();
  return container;
}

Finder get _save => find.byKey(const ValueKey('settings-save'));
Finder get _cancel => find.widgetWithText(OutlinedButton, '취소');

bool _enabled(WidgetTester tester, Finder button) => tester.widget<ButtonStyleButton>(button).onPressed != null;

bool _privacyChecked(WidgetTester tester) =>
    tester.widget<Checkbox>(find.byKey(const ValueKey('privacy-checkbox'))).value!;

/// 프로필 사진 선택지([code], null = 사진 없음)의 테두리 색. 고른 원만 강조색이다.
Color _avatarRing(WidgetTester tester, String? code) {
  final key = ValueKey(code == null ? 'avatar-none' : 'avatar-$code');
  final ring = tester.widgetList<Container>(find.descendant(of: find.byKey(key), matching: find.byType(Container))).first;
  return ((ring.decoration as BoxDecoration).border as Border).top.color;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('저장된 프로필 값이 보이고 바뀐 것이 없으면 저장·취소가 꺼져 있다', (t) async {
    await _pumpSettings(t);

    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('driver@simcenter.test'), findsOneWidget);
    expect(find.text('홍길동'), findsWidgets);
    expect(_privacyChecked(t), isTrue);
    expect(find.text('Asia/Seoul'), findsOneWidget);
    expect(find.text('F1 25'), findsOneWidget);
    expect(_avatarRing(t, null), AppColors.accent);
    expect(_avatarRing(t, 'MCL'), Colors.transparent);
    expect(_enabled(t, _save), isFalse);
    expect(_enabled(t, _cancel), isFalse);
    expect(find.text('모든 변경 사항이 저장됐어요.'), findsOneWidget);
  });

  testWidgets('공개 설정을 끄면 저장할 수 있고, 취소하면 저장된 값으로 돌아간다', (t) async {
    final repo = FakeProfileRepository();
    await _pumpSettings(t, repo: repo);

    await _tap(t, find.byKey(const ValueKey('privacy-checkbox')));

    expect(_privacyChecked(t), isFalse);
    expect(_enabled(t, _save), isTrue);
    expect(find.text('저장하지 않은 변경 사항이 있어요.'), findsOneWidget);

    await _tap(t, _cancel);

    expect(_privacyChecked(t), isTrue);
    expect(_enabled(t, _save), isFalse);
    expect(repo.updates, isEmpty);
  });

  testWidgets('같은 값으로 되돌리면 다시 바뀐 것이 없는 상태가 된다', (t) async {
    await _pumpSettings(t);

    await _tap(t, find.byKey(const ValueKey('choice-gamepad')));
    expect(_enabled(t, _save), isTrue);
    await _tap(t, find.byKey(const ValueKey('choice-wheel')));

    expect(_enabled(t, _save), isFalse);
  });

  testWidgets('프로필 사진을 누르면 그 원에 강조 테두리가 생기고 저장하면 사이드바용 사용자 정보도 바뀐다', (t) async {
    final repo = FakeProfileRepository();
    final container = await _pumpSettings(t, repo: repo);

    await _tap(t, find.byKey(const ValueKey('avatar-MCL')));

    expect(_avatarRing(t, 'MCL'), AppColors.accent);
    expect(_avatarRing(t, null), Colors.transparent);

    await _tap(t, find.byKey(const ValueKey('privacy-checkbox')));
    await _tap(t, find.byKey(const ValueKey('choice-gamepad')));
    await _tap(t, find.byKey(const ValueKey('choice-dark')));
    await _tap(t, _save);

    final sent = repo.updates.single;
    expect(sent.preferences.avatarTeam, 'MCL');
    expect(sent.preferences.showOnLeaderboard, isFalse);
    expect(sent.preferences.controller, ControllerType.gamepad);
    expect(sent.preferences.theme, ThemePreference.dark);
    expect(sent.toJson()['controller'], 'Gamepad');

    final user = container.read(authControllerProvider).value!;
    expect(user.preferences.avatarTeam, 'MCL');
    expect(user.preferences.theme, ThemePreference.dark);
    expect(_enabled(t, _save), isFalse);
    expect(find.text('변경 사항을 저장했어요.'), findsOneWidget);
  });

  testWidgets('사진 없음을 고르면 저장할 때 avatarTeam이 null이다', (t) async {
    const user = AppUser(
      userId: 'u1',
      displayName: '홍길동',
      email: 'driver@simcenter.test',
      preferences: UserPreferences(
        showOnLeaderboard: true,
        avatarTeam: 'FER',
        preferredGame: 'F1_25',
        controller: ControllerType.wheel,
        console: ConsolePlatform.pc,
        units: UnitSystem.metric,
        timeZoneId: 'Asia/Seoul',
        theme: ThemePreference.system,
      ),
    );
    final repo = FakeProfileRepository(user: user);
    await _pumpSettings(t, repo: repo, user: user);
    expect(_avatarRing(t, 'FER'), AppColors.accent);

    await _tap(t, find.byKey(const ValueKey('avatar-none')));
    await _tap(t, _save);

    expect(repo.updates.single.preferences.avatarTeam, isNull);
    expect(repo.updates.single.toJson()['avatarTeam'], isNull);
  });

  testWidgets('닉네임 변경은 폼에만 반영되고 저장해야 서버로 간다', (t) async {
    final repo = FakeProfileRepository();
    await _pumpSettings(t, repo: repo);

    await _tap(t, find.byKey(const ValueKey('change-display-name')));
    await t.enterText(find.byKey(const ValueKey('display-name-field')), '  lemonary  ');
    await _tap(t, find.byKey(const ValueKey('display-name-confirm')));

    expect(find.text('lemonary'), findsOneWidget);
    expect(repo.updates, isEmpty);
    expect(_enabled(t, _save), isTrue);

    await _tap(t, _save);
    expect(repo.updates.single.displayName, 'lemonary');
  });

  testWidgets('빈 닉네임은 대화상자에서 막는다', (t) async {
    await _pumpSettings(t);

    await _tap(t, find.byKey(const ValueKey('change-display-name')));
    await t.enterText(find.byKey(const ValueKey('display-name-field')), '   ');
    await _tap(t, find.byKey(const ValueKey('display-name-confirm')));

    expect(find.text('닉네임을 입력해 주세요.'), findsOneWidget);
    expect(_enabled(t, _save), isFalse);
  });

  testWidgets('이메일 변경은 대화상자에서 바로 저장되고 화면의 이메일이 바뀐다', (t) async {
    final repo = FakeProfileRepository();
    final container = await _pumpSettings(t, repo: repo);

    await _tap(t, find.byKey(const ValueKey('change-email')));
    await t.enterText(find.byKey(const ValueKey('email-new')), ' new@simcenter.test ');
    await t.enterText(find.byKey(const ValueKey('email-password')), 'P@ssw0rd!');
    await _tap(t, find.byKey(const ValueKey('email-submit')));

    expect(repo.emailChanges.single.newEmail, 'new@simcenter.test');
    expect(repo.emailChanges.single.currentPassword, 'P@ssw0rd!');
    expect(find.byKey(const ValueKey('email-new')), findsNothing); // 대화상자가 닫혔다.
    expect(find.text('new@simcenter.test'), findsOneWidget);
    expect(container.read(authControllerProvider).value!.email, 'new@simcenter.test');
    expect(_enabled(t, _save), isFalse); // 이메일은 폼 저장과 따로다.
  });

  testWidgets('현재 비밀번호가 틀리면 대화상자의 비밀번호 칸에 오류가 보인다', (t) async {
    final repo = FakeProfileRepository(
      emailError: ApiException(
        '현재 비밀번호가 올바르지 않습니다.',
        statusCode: 400,
        fieldErrors: const {'currentPassword': '현재 비밀번호가 올바르지 않습니다.'},
      ),
    );
    await _pumpSettings(t, repo: repo);

    await _tap(t, find.byKey(const ValueKey('change-email')));
    await t.enterText(find.byKey(const ValueKey('email-new')), 'new@simcenter.test');
    await t.enterText(find.byKey(const ValueKey('email-password')), 'wrong-pw');
    await _tap(t, find.byKey(const ValueKey('email-submit')));

    expect(find.text('현재 비밀번호가 올바르지 않습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('email-new')), findsOneWidget); // 대화상자가 열려 있다.
    expect(find.text('driver@simcenter.test'), findsOneWidget);
  });

  testWidgets('이미 쓰는 이메일(409)은 대화상자 아래에 메시지로 보인다', (t) async {
    final repo = FakeProfileRepository(emailError: ApiException('이미 사용 중인 이메일입니다.', statusCode: 409));
    await _pumpSettings(t, repo: repo);

    await _tap(t, find.byKey(const ValueKey('change-email')));
    await t.enterText(find.byKey(const ValueKey('email-new')), 'taken@simcenter.test');
    await t.enterText(find.byKey(const ValueKey('email-password')), 'P@ssw0rd!');
    await _tap(t, find.byKey(const ValueKey('email-submit')));

    expect(find.text('이미 사용 중인 이메일입니다.'), findsOneWidget);
  });

  testWidgets('저장이 실패하면 오류를 보이고 편집 중인 값은 그대로다', (t) async {
    final repo = FakeProfileRepository(updateError: ApiException('지원하지 않는 값입니다.', statusCode: 400));
    await _pumpSettings(t, repo: repo);

    await _tap(t, find.byKey(const ValueKey('privacy-checkbox')));
    await _tap(t, _save);

    expect(find.text('지원하지 않는 값입니다.'), findsOneWidget);
    expect(_privacyChecked(t), isFalse);
    expect(_enabled(t, _save), isTrue);
  });

  testWidgets('로그아웃 버튼은 허브를 끊고 인증을 해제한다', (t) async {
    final hub = FakeRankingHub();
    final container = await _pumpSettings(t, hub: hub);

    await _tap(t, find.byKey(const ValueKey('settings-logout')));

    expect(hub.stopCalls, 1);
    expect(container.read(authControllerProvider).value, isNull);
  });

  testWidgets('휴대폰 폭에서도 넘치지 않는다', (t) async {
    await _pumpSettings(t, size: _phone);

    expect(t.takeException(), isNull);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(_save, findsOneWidget);
  });
}
