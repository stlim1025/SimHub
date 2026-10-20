import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simcenter_app/features/profile/application/team_logos_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/core/shell/app_shell.dart';
import 'package:simcenter_app/core/shell/nav_items.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';

import 'support/fakes.dart';

const _wide = Size(1000, 800);
const _narrow = Size(600, 800);

/// `stop()`이 [stopGate]가 완료될 때까지 끝나지 않는 허브.
class _SlowStopHub extends FakeRankingHub {
  final stopGate = Completer<void>();

  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate.future;
  }
}

/// `stop()`이 항상 실패하는 허브.
class _FailingStopHub extends FakeRankingHub {
  @override
  Future<void> stop() async => throw StateError('hub down');
}

/// 셸 안에 메뉴별 자리표시 페이지를 올린 라우터.
GoRouter _router({String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (_, _) => const Text('body:dashboard')),
            GoRoute(path: '/seasons', builder: (_, _) => const Text('body:seasons')),
            GoRoute(
              path: '/seasons/:seasonId',
              builder: (_, state) => Text('body:season:${state.pathParameters['seasonId']}'),
            ),
            GoRoute(path: '/sessions', builder: (_, _) => const Text('body:sessions')),
            GoRoute(
              path: '/sessions/:sessionId',
              builder: (_, state) => Text('body:session:${state.pathParameters['sessionId']}'),
            ),
            GoRoute(path: '/laps', builder: (_, _) => const Text('body:laps')),
            GoRoute(path: '/leaderboard', builder: (_, _) => const Text('body:leaderboard')),
            GoRoute(path: '/telemetry-app', builder: (_, _) => const Text('body:telemetry-app')),
            GoRoute(path: '/settings', builder: (_, _) => const Text('body:settings')),
          ],
        ),
      ],
    );

Future<ProviderContainer> _pumpShell(
  WidgetTester tester,
  Size size, {
  FakeRankingHub? hub,
  String initialLocation = '/',
}) async {
  setViewSize(tester, size);
  final container = ProviderContainer(overrides: [
    fakeAuth(),
    if (hub != null) rankingHubClientProvider.overrideWithValue(hub),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: _router(initialLocation: initialLocation)),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// 사이드바 메뉴 라벨을 위에서 아래 순서로.
List<String?> _menuLabels(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) (tile.title as Text).data,
    ];

bool _isSelected(WidgetTester tester, String label) =>
    tester.widget<ListTile>(find.widgetWithText(ListTile, label)).selected;

void main() {
  testWidgets('900px 이상이면 사이드바와 메뉴 라벨이 보인다', (t) async {
    await _pumpShell(t, _wide);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Seasons'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Laps'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Telemetry App'), findsOneWidget);
    expect(find.byTooltip('메뉴 열기'), findsNothing);
    expect(find.text('body:dashboard'), findsOneWidget);
  });

  testWidgets('메뉴 순서는 Dashboard · Seasons · Sessions · Laps · Leaderboard · Telemetry App', (t) async {
    await _pumpShell(t, _wide);

    expect(_menuLabels(t), ['Dashboard', 'Seasons', 'Sessions', 'Laps', 'Leaderboard', 'Telemetry App']);
  });

  testWidgets('Seasons 메뉴를 누르면 /seasons로 이동하고 선택 상태가 된다', (t) async {
    await _pumpShell(t, _wide);

    await t.tap(find.widgetWithText(ListTile, 'Seasons'));
    await t.pumpAndSettle();

    expect(find.text('body:seasons'), findsOneWidget);
    expect(_isSelected(t, 'Seasons'), isTrue);
    expect(_isSelected(t, 'Dashboard'), isFalse);
    expect(_isSelected(t, 'Sessions'), isFalse);
  });

  testWidgets('/seasons/abc에서 Seasons 메뉴가 선택되어 있다', (t) async {
    await _pumpShell(t, _wide, initialLocation: '/seasons/abc');

    expect(find.text('body:season:abc'), findsOneWidget);
    expect(_isSelected(t, 'Seasons'), isTrue);
    for (final other in ['Dashboard', 'Sessions', 'Laps', 'Leaderboard', 'Telemetry App']) {
      expect(_isSelected(t, other), isFalse, reason: other);
    }
  });

  testWidgets('Sessions 메뉴를 누르면 /sessions로 이동하고, 세션 상세 경로에서도 선택 상태다', (t) async {
    await _pumpShell(t, _wide);

    await t.tap(find.widgetWithText(ListTile, 'Sessions'));
    await t.pumpAndSettle();
    expect(find.text('body:sessions'), findsOneWidget);
    expect(_isSelected(t, 'Sessions'), isTrue);
    expect(_isSelected(t, 'Dashboard'), isFalse);
  });

  testWidgets('/sessions/abc에서 Sessions 메뉴가 선택되어 있다', (t) async {
    await _pumpShell(t, _wide, initialLocation: '/sessions/abc');

    expect(find.text('body:session:abc'), findsOneWidget);
    expect(_isSelected(t, 'Sessions'), isTrue);
    for (final other in ['Dashboard', 'Seasons', 'Laps', 'Leaderboard', 'Telemetry App']) {
      expect(_isSelected(t, other), isFalse, reason: other);
    }
  });

  testWidgets('Telemetry App 메뉴를 누르면 /telemetry-app으로 이동하고 선택 표시가 된다', (t) async {
    await _pumpShell(t, _wide);

    await t.tap(find.text('Telemetry App'));
    await t.pumpAndSettle();

    expect(find.text('body:telemetry-app'), findsOneWidget);
    final tile = t.widget<ListTile>(find.widgetWithText(ListTile, 'Telemetry App'));
    expect(tile.selected, isTrue);
  });

  testWidgets('900px 미만이면 서랍 메뉴 버튼이 보인다', (t) async {
    await _pumpShell(t, _narrow);

    expect(find.byTooltip('메뉴 열기'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);

    await t.tap(find.byTooltip('메뉴 열기'));
    await t.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
  });

  testWidgets('사이드바 하단에 사용자 이름이 보이고 로그아웃하면 허브를 끊고 인증이 해제된다', (t) async {
    final hub = FakeRankingHub();
    final container = await _pumpShell(t, _wide, hub: hub);

    expect(find.text('홍길동'), findsOneWidget);

    await t.tap(find.byTooltip('로그아웃'));
    await t.pumpAndSettle();

    expect(hub.stopCalls, 1);
    expect(container.read(authControllerProvider).value, isNull);
  });

  testWidgets('사이드바 하단 프로필(이름 첫 글자·계정 설정)을 누르면 /settings로 이동하고 강조된다', (t) async {
    await _pumpShell(t, _wide);

    expect(find.text('홍'), findsOneWidget); // 사진이 없으면 이름 첫 글자.
    expect(find.text('계정 설정'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('account-settings')));
    await t.pumpAndSettle();

    expect(find.text('body:settings'), findsOneWidget);
    final footer = t.widget<Material>(
      find.ancestor(of: find.byKey(const ValueKey('account-settings')), matching: find.byType(Material)).first,
    );
    expect(footer.color, isNot(Colors.transparent));
    for (final label in ['Dashboard', 'Seasons', 'Sessions', 'Laps', 'Leaderboard', 'Telemetry App']) {
      expect(_isSelected(t, label), isFalse, reason: label);
    }
  });

  testWidgets('프로필 사진을 고른 사용자는 사이드바에 팀 코드 원이 보인다', (t) async {
    setViewSize(t, _wide);
    final user = testUser.copyWith(preferences: testUser.preferences.copyWith(avatarTeam: 'MCL'));
    // 서버 로고(네트워크)와 상관없이 코드 원을 본다.
    final container = ProviderContainer(overrides: [
      fakeAuth(user),
      teamLogoUrlProvider.overrideWithValue((_) => null),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: _router()),
    ));
    await t.pumpAndSettle();

    expect(find.text('MCL'), findsOneWidget);
    expect(find.text('홍'), findsNothing);
  });

  testWidgets('서랍에서 계정 설정을 누르면 이동하고 서랍이 닫힌다', (t) async {
    await _pumpShell(t, _narrow);

    await t.tap(find.byTooltip('메뉴 열기'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('account-settings')));
    await t.pumpAndSettle();

    expect(find.text('body:settings'), findsOneWidget);
    expect(find.text('계정 설정'), findsNothing); // 서랍이 닫혔다.
  });

  testWidgets('허브 종료를 기다리는 동안 사이드바가 사라져도 로그아웃은 끝까지 수행된다', (t) async {
    final hub = _SlowStopHub();
    final container = await _pumpShell(t, _wide, hub: hub);

    await t.tap(find.byTooltip('로그아웃'));
    await t.pump();
    expect(hub.stopCalls, 1);

    // 화면이 좁아지면 고정 사이드바가 트리에서 사라진다(서랍은 닫혀 있다).
    setViewSize(t, _narrow);
    await t.pumpAndSettle();
    expect(find.byTooltip('로그아웃'), findsNothing);

    hub.stopGate.complete();
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(container.read(authControllerProvider).value, isNull);
  });

  testWidgets('허브 종료가 실패해도 로그아웃은 수행된다', (t) async {
    final hub = _FailingStopHub();
    final container = await _pumpShell(t, _wide, hub: hub);

    await t.tap(find.byTooltip('로그아웃'));
    await t.pumpAndSettle();

    expect(container.read(authControllerProvider).value, isNull);
  });

  testWidgets('메뉴를 누르면 해당 경로로 이동한다', (t) async {
    await _pumpShell(t, _wide);

    await t.tap(find.text('Leaderboard'));
    await t.pumpAndSettle();

    expect(find.text('body:leaderboard'), findsOneWidget);
  });

  testWidgets('서랍에서 메뉴를 누르면 이동하고 서랍이 닫힌다', (t) async {
    await _pumpShell(t, _narrow);

    await t.tap(find.byTooltip('메뉴 열기'));
    await t.pumpAndSettle();
    await t.tap(find.text('Laps'));
    await t.pumpAndSettle();

    expect(find.text('body:laps'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing); // 서랍이 닫혀 메뉴가 사라졌다.
  });

  group('isNavItemSelected', () {
    final dashboard = navItems.firstWhere((i) => i.path == '/');
    final laps = navItems.firstWhere((i) => i.path == '/laps');
    final sessions = navItems.firstWhere((i) => i.path == '/sessions');
    final seasons = navItems.firstWhere((i) => i.path == '/seasons');

    test('루트 경로는 Dashboard만 선택한다', () {
      expect(isNavItemSelected(dashboard, '/'), isTrue);
      expect(isNavItemSelected(laps, '/'), isFalse);
    });

    test('시즌 상세 경로는 Seasons를 선택한다', () {
      expect(isNavItemSelected(seasons, '/seasons'), isTrue);
      expect(isNavItemSelected(seasons, '/seasons/abc'), isTrue);
      expect(isNavItemSelected(seasons, '/seasonsfoo'), isFalse);
      expect(isNavItemSelected(seasons, '/sessions/abc'), isFalse);
      expect(isNavItemSelected(sessions, '/seasons/abc'), isFalse);
    });

    test('세션 상세 경로는 Sessions를 선택한다', () {
      expect(isNavItemSelected(sessions, '/sessions'), isTrue);
      expect(isNavItemSelected(sessions, '/sessions/abc'), isTrue);
      expect(isNavItemSelected(sessions, '/sessionsfoo'), isFalse);
      expect(isNavItemSelected(laps, '/sessions/abc'), isFalse);
    });

    test('하위 경로는 상위 메뉴를 선택 상태로 둔다', () {
      expect(isNavItemSelected(laps, '/laps'), isTrue);
      expect(isNavItemSelected(laps, '/laps/tracks/abc'), isTrue);
      expect(isNavItemSelected(dashboard, '/laps/tracks/abc'), isFalse);
    });

    test('접두사만 같은 다른 경로는 선택하지 않는다', () {
      expect(isNavItemSelected(laps, '/lapsfoo'), isFalse);
    });
  });
}
