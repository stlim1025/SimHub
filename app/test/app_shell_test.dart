import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simcenter_app/features/profile/application/team_logos_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/core/shell/app_shell.dart';
import 'package:simcenter_app/core/shell/command_palette.dart';
import 'package:simcenter_app/core/shell/nav_items.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/time/clock_provider.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/devices/application/devices_providers.dart';
import 'package:simcenter_app/features/devices/domain/device_models.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';

import 'support/fakes.dart';

/// 위쪽 가로 메뉴가 모두 화면 안에 들어오는 넓은 화면(테스트 글꼴은 글자마다 폭이 넓다).
const _wide = Size(1920, 1080);
const _narrow = Size(600, 800);
final _now = DateTime.utc(2026, 10, 18, 11);
const _australia = Track(trackId: 'au', gameCode: 'F1_25', name: 'Australia');

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
            GoRoute(path: '/setups/:trackId/:setupId', builder: (_, _) => const Text('body:setup')),
            GoRoute(path: '/tracks', builder: (_, _) => const Text('body:tracks')),
            GoRoute(
              path: '/tracks/:trackId',
              builder: (_, state) => Text('body:track:${state.pathParameters['trackId']}'),
            ),
            GoRoute(path: '/telemetry-app', builder: (_, _) => const Text('body:telemetry-app')),
            GoRoute(path: '/settings', builder: (_, _) => const Text('body:settings')),
          ],
        ),
      ],
    );

/// 셸을 올린다. Agent 칩(장치 목록)·검색 창(트랙 목록)·허브는 네트워크 없이 고정값으로 바꾼다.
Future<ProviderContainer> _pumpShell(
  WidgetTester tester,
  Size size, {
  FakeRankingHub? hub,
  String initialLocation = '/',
  AppUser user = testUser,
  List<AgentDevice> devices = const [],
  List<Track> tracks = const [],
  List<Override> overrides = const [],
}) async {
  setViewSize(tester, size);
  final container = ProviderContainer(overrides: [
    fakeAuth(user),
    rankingHubClientProvider.overrideWithValue(hub ?? FakeRankingHub()),
    agentDevicesProvider.overrideWith((ref) async => devices),
    rankingRepositoryProvider.overrideWithValue(FakeRankingRepository(tracks: tracks)),
    clockProvider.overrideWithValue(() => _now),
    ...overrides,
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

/// 위쪽 가로 메뉴 항목.
Finder _menu(String path) => find.byKey(ValueKey('nav-$path'));

/// 위쪽 가로 메뉴 라벨을 왼쪽에서 오른쪽 순서로.
List<String?> _topMenuLabels(WidgetTester tester) => [
      for (final element in find
          .byWidgetPredicate((w) => w is InkWell && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('nav-'))
          .evaluate())
        tester.widget<Text>(find.descendant(of: find.byWidget(element.widget), matching: find.byType(Text))).data,
    ];

/// 위쪽 가로 메뉴 항목의 선택 상태(접근성 `selected`).
bool _isMenuSelected(WidgetTester tester, String path) =>
    tester.widget<Semantics>(find.ancestor(of: _menu(path), matching: find.byType(Semantics)).first).properties.selected ??
    false;

/// 위쪽 가로 메뉴 항목 아래 막대 색(선택 = 앰버).
Color _menuBarColor(WidgetTester tester, String path) {
  final box = tester.widget<Container>(find.descendant(of: _menu(path), matching: find.byType(Container)).first);
  return ((box.decoration! as BoxDecoration).border! as Border).bottom.color;
}

/// [key] 위젯 바로 아래 Container의 테두리 색(Agent 칩·계정 사진 강조).
Color _borderColorUnder(WidgetTester tester, String key) {
  final box = tester.widget<Container>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Container)).first);
  return ((box.decoration! as BoxDecoration).border! as Border).top.color;
}

/// 서랍 메뉴 라벨을 위에서 아래 순서로.
List<String?> _drawerLabels(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) (tile.title as Text).data,
    ];

bool _isDrawerSelected(WidgetTester tester, String label) =>
    tester.widget<ListTile>(find.widgetWithText(ListTile, label)).selected;

Future<void> _openAccountMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('account-menu')));
  await tester.pumpAndSettle();
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('메뉴 열기'));
  await tester.pumpAndSettle();
}

const _menuPaths = ['/', '/seasons', '/sessions', '/laps', '/trends', '/tracks'];

void main() {
  testWidgets('1100px 이상이면 위쪽 가로 메뉴·검색·Agent 칩·계정 메뉴가 보이고 서랍 버튼은 없다', (t) async {
    await _pumpShell(t, _wide);

    for (final path in _menuPaths) {
      expect(_menu(path), findsOneWidget, reason: path);
    }
    for (final label in ['Dashboard', 'Seasons', 'Sessions', 'Laps', 'Trends', 'Tracks']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(_menu('/telemetry-app'), findsNothing); // Telemetry App은 메뉴가 아니라 Agent 칩·계정 메뉴에서 연다.
    expect(find.byKey(const ValueKey('command-palette-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-status-chip')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-menu')), findsOneWidget);
    expect(find.byTooltip('메뉴 열기'), findsNothing);
    expect(find.text('body:dashboard'), findsOneWidget);
  });

  testWidgets('위쪽 가로 메뉴 경계는 1100px이다(1099px은 서랍, 1100px은 가로 메뉴)', (t) async {
    await _pumpShell(t, const Size(1099, 800));
    expect(find.byTooltip('메뉴 열기'), findsOneWidget);
    expect(_menu('/'), findsNothing);

    setViewSize(t, const Size(1100, 800));
    await t.pumpAndSettle();
    expect(find.byTooltip('메뉴 열기'), findsNothing);
    expect(_menu('/'), findsOneWidget);
  });

  testWidgets('메뉴 순서는 Dashboard · Seasons · Sessions · Laps · Trends · Tracks(Leaderboard는 혼자 쓰는 동안 뺐다)', (t) async {
    await _pumpShell(t, _wide);

    expect(_topMenuLabels(t), ['Dashboard', 'Seasons', 'Sessions', 'Laps', 'Trends', 'Tracks']);
  });

  testWidgets('/setups/au/s1에서는 셋업을 합친 Tracks 메뉴가 선택되어 있다', (t) async {
    await _pumpShell(t, _wide, initialLocation: '/setups/au/s1');

    expect(find.text('body:setup'), findsOneWidget);
    expect(_isMenuSelected(t, '/tracks'), isTrue);
    for (final other in ['/', '/seasons', '/sessions', '/laps']) {
      expect(_isMenuSelected(t, other), isFalse, reason: other);
    }
  });

  testWidgets('/tracks/au에서 Tracks 메뉴가 선택되어 있다', (t) async {
    await _pumpShell(t, _wide, initialLocation: '/tracks/au');

    expect(_isMenuSelected(t, '/tracks'), isTrue);
    expect(_isMenuSelected(t, '/laps'), isFalse);
  });

  testWidgets('Seasons 메뉴를 누르면 /seasons로 이동하고 선택 상태(앰버 막대)가 된다', (t) async {
    await _pumpShell(t, _wide);
    expect(_isMenuSelected(t, '/'), isTrue);

    await t.tap(_menu('/seasons'));
    await t.pumpAndSettle();

    expect(find.text('body:seasons'), findsOneWidget);
    expect(_isMenuSelected(t, '/seasons'), isTrue);
    expect(_isMenuSelected(t, '/'), isFalse);
    expect(_isMenuSelected(t, '/sessions'), isFalse);
    expect(_menuBarColor(t, '/seasons'), AppColors.accent);
    expect(_menuBarColor(t, '/'), Colors.transparent);
  });

  testWidgets('/seasons/abc에서 Seasons 메뉴가 선택되어 있다', (t) async {
    await _pumpShell(t, _wide, initialLocation: '/seasons/abc');

    expect(find.text('body:season:abc'), findsOneWidget);
    expect(_isMenuSelected(t, '/seasons'), isTrue);
    for (final other in ['/', '/sessions', '/laps', '/tracks']) {
      expect(_isMenuSelected(t, other), isFalse, reason: other);
    }
  });

  testWidgets('Sessions 메뉴를 누르면 /sessions로 이동하고 선택 상태가 된다', (t) async {
    await _pumpShell(t, _wide);

    await t.tap(_menu('/sessions'));
    await t.pumpAndSettle();
    expect(find.text('body:sessions'), findsOneWidget);
    expect(_isMenuSelected(t, '/sessions'), isTrue);
    expect(_isMenuSelected(t, '/'), isFalse);
  });

  testWidgets('/sessions/abc에서 Sessions 메뉴가 선택되어 있다', (t) async {
    await _pumpShell(t, _wide, initialLocation: '/sessions/abc');

    expect(find.text('body:session:abc'), findsOneWidget);
    expect(_isMenuSelected(t, '/sessions'), isTrue);
    for (final other in ['/', '/seasons', '/laps', '/tracks']) {
      expect(_isMenuSelected(t, other), isFalse, reason: other);
    }
  });

  testWidgets('메뉴를 누르면 해당 경로로 이동한다(Laps · Tracks)', (t) async {
    await _pumpShell(t, _wide);

    await t.tap(_menu('/laps'));
    await t.pumpAndSettle();
    expect(find.text('body:laps'), findsOneWidget);

    await t.tap(_menu('/tracks'));
    await t.pumpAndSettle();
    expect(find.text('body:tracks'), findsOneWidget);
    expect(_isMenuSelected(t, '/tracks'), isTrue);
  });

  group('Agent 칩', () {
    testWidgets('연결된 PC가 없으면 연결 필요로 보이고, 누르면 /telemetry-app으로 이동해 칩이 강조된다', (t) async {
      await _pumpShell(t, _wide);
      expect(find.text('Agent 연결 필요'), findsOneWidget);
      expect(_borderColorUnder(t, 'agent-status-chip'), isNot(AppColors.accent));

      await t.tap(find.byKey(const ValueKey('agent-status-chip')));
      await t.pumpAndSettle();

      expect(find.text('body:telemetry-app'), findsOneWidget);
      expect(_borderColorUnder(t, 'agent-status-chip'), AppColors.accent);
      for (final path in _menuPaths) {
        expect(_isMenuSelected(t, path), isFalse, reason: path);
      }
    });

    testWidgets('방금 데이터를 받은 PC가 있으면 수신 중으로 보인다', (t) async {
      await _pumpShell(t, _wide, devices: [
        deviceOf('d1', 'Rig PC', lastSeenAt: _now.subtract(const Duration(minutes: 1))),
      ]);

      expect(find.text('Agent 수신 중'), findsOneWidget);
    });
  });

  group('계정 메뉴', () {
    testWidgets('사용자 이름이 보이고 로그아웃하면 허브를 끊고 인증이 해제된다', (t) async {
      final hub = FakeRankingHub();
      final container = await _pumpShell(t, _wide, hub: hub);

      await _openAccountMenu(t);
      expect(find.text('홍길동'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('account-logout')));
      await t.pumpAndSettle();

      expect(hub.stopCalls, 1);
      expect(container.read(authControllerProvider).value, isNull);
    });

    testWidgets('프로필 사진(이름 첫 글자)을 눌러 계정 설정을 고르면 /settings로 이동하고 사진이 강조된다', (t) async {
      await _pumpShell(t, _wide);

      expect(find.text('홍'), findsOneWidget); // 사진이 없으면 이름 첫 글자.
      expect(_borderColorUnder(t, 'account-menu'), Colors.transparent);

      await _openAccountMenu(t);
      expect(find.text('계정 설정'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('account-settings')));
      await t.pumpAndSettle();

      expect(find.text('body:settings'), findsOneWidget);
      expect(find.text('계정 설정'), findsNothing); // 메뉴가 닫혔다.
      expect(_borderColorUnder(t, 'account-menu'), AppColors.accent);
      for (final path in _menuPaths) {
        expect(_isMenuSelected(t, path), isFalse, reason: path);
      }
    });

    testWidgets('계정 메뉴의 Telemetry App을 누르면 /telemetry-app으로 이동한다', (t) async {
      await _pumpShell(t, _wide);

      await _openAccountMenu(t);
      await t.tap(find.byKey(const ValueKey('account-telemetry-app')));
      await t.pumpAndSettle();

      expect(find.text('body:telemetry-app'), findsOneWidget);
    });

    testWidgets('프로필 사진을 고른 사용자는 위쪽 바에 팀 코드 원이 보인다', (t) async {
      final user = testUser.copyWith(preferences: testUser.preferences.copyWith(avatarTeam: 'MCL'));
      // 서버 로고(네트워크)와 상관없이 코드 원을 본다.
      await _pumpShell(t, _wide, user: user, overrides: [teamLogoUrlProvider.overrideWithValue((_) => null)]);

      expect(find.text('MCL'), findsOneWidget);
      expect(find.text('홍'), findsNothing);
    });

    testWidgets('허브 종료가 실패해도 로그아웃은 수행된다', (t) async {
      final hub = _FailingStopHub();
      final container = await _pumpShell(t, _wide, hub: hub);

      await _openAccountMenu(t);
      await t.tap(find.byKey(const ValueKey('account-logout')));
      await t.pumpAndSettle();

      expect(container.read(authControllerProvider).value, isNull);
    });
  });

  group('서랍 메뉴(1100px 미만)', () {
    testWidgets('서랍 버튼만 보이고, 열면 모든 메뉴와 Telemetry App이 순서대로 있다', (t) async {
      await _pumpShell(t, _narrow);

      expect(find.byTooltip('메뉴 열기'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(_menu('/'), findsNothing);

      await _openDrawer(t);

      expect(
        _drawerLabels(t),
        ['Dashboard', 'Seasons', 'Sessions', 'Laps', 'Trends', 'Tracks', 'Telemetry App'],
      );
      expect(_isDrawerSelected(t, 'Dashboard'), isTrue);
    });

    testWidgets('/setups/au/s1에서는 서랍에서도 Tracks가 선택되어 있다', (t) async {
      await _pumpShell(t, _narrow, initialLocation: '/setups/au/s1');

      await _openDrawer(t);

      expect(_isDrawerSelected(t, 'Tracks'), isTrue);
      expect(_isDrawerSelected(t, 'Dashboard'), isFalse);
    });

    testWidgets('서랍에서 메뉴를 누르면 이동하고 서랍이 닫힌다', (t) async {
      await _pumpShell(t, _narrow);

      await _openDrawer(t);
      await t.tap(find.text('Laps'));
      await t.pumpAndSettle();

      expect(find.text('body:laps'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing); // 서랍이 닫혀 메뉴가 사라졌다.
    });

    testWidgets('서랍의 Telemetry App을 누르면 이동하고, 다시 열면 선택 표시가 된다', (t) async {
      await _pumpShell(t, _narrow);

      await _openDrawer(t);
      await t.tap(find.text('Telemetry App'));
      await t.pumpAndSettle();
      expect(find.text('body:telemetry-app'), findsOneWidget);

      await _openDrawer(t);
      expect(_isDrawerSelected(t, 'Telemetry App'), isTrue);
      expect(_isDrawerSelected(t, 'Dashboard'), isFalse);
    });

    testWidgets('서랍 아래 프로필(이름·계정 설정)을 누르면 /settings로 이동하고 서랍이 닫히며, 다시 열면 강조된다', (t) async {
      await _pumpShell(t, _narrow);

      await _openDrawer(t);
      expect(find.text('홍길동'), findsOneWidget);
      expect(find.text('계정 설정'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('drawer-account-settings')));
      await t.pumpAndSettle();

      expect(find.text('body:settings'), findsOneWidget);
      expect(find.text('계정 설정'), findsNothing); // 서랍이 닫혔다.

      await _openDrawer(t);
      final footer = t.widget<Material>(
        find.ancestor(of: find.byKey(const ValueKey('drawer-account-settings')), matching: find.byType(Material)).first,
      );
      expect(footer.color, isNot(Colors.transparent));
      for (final label in ['Dashboard', 'Seasons', 'Sessions', 'Laps', 'Trends', 'Tracks', 'Telemetry App']) {
        expect(_isDrawerSelected(t, label), isFalse, reason: label);
      }
    });

    testWidgets('서랍의 로그아웃 버튼으로 허브를 끊고 로그아웃한다', (t) async {
      final hub = FakeRankingHub();
      final container = await _pumpShell(t, _narrow, hub: hub);

      await _openDrawer(t);
      await t.tap(find.byTooltip('로그아웃'));
      await t.pumpAndSettle();

      expect(hub.stopCalls, 1);
      expect(container.read(authControllerProvider).value, isNull);
    });

    testWidgets('허브 종료를 기다리는 동안 서랍이 사라져도 로그아웃은 끝까지 수행된다', (t) async {
      final hub = _SlowStopHub();
      final container = await _pumpShell(t, _narrow, hub: hub);

      await _openDrawer(t);
      await t.tap(find.byTooltip('로그아웃'));
      await t.pump();
      expect(hub.stopCalls, 1);

      // 화면이 넓어지면 서랍이 트리에서 사라진다(위쪽 가로 메뉴로 바뀐다).
      setViewSize(t, _wide);
      await t.pumpAndSettle();
      expect(find.byTooltip('로그아웃'), findsNothing);
      expect(find.byKey(const ValueKey('drawer-account-settings')), findsNothing);

      hub.stopGate.complete();
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(container.read(authControllerProvider).value, isNull);
    });
  });

  group('검색 창', () {
    testWidgets('검색 버튼을 누르면 검색 창이 열리고, 항목을 고르면 그 주소로 이동하고 닫힌다', (t) async {
      await _pumpShell(t, _wide);
      expect(find.byKey(const ValueKey('command-palette')), findsNothing);

      await t.tap(find.byKey(const ValueKey('command-palette-button')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('command-palette-input')), 'sessions');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('command-/sessions')));
      await t.pumpAndSettle();

      expect(find.text('body:sessions'), findsOneWidget);
      expect(find.byKey(const ValueKey('command-palette')), findsNothing);
      expect(_isMenuSelected(t, '/sessions'), isTrue);
    });

    testWidgets('트랙 이름으로 찾아 Enter를 누르면 그 트랙 화면으로 간다', (t) async {
      await _pumpShell(t, _wide, tracks: const [_australia]);

      await t.tap(find.byKey(const ValueKey('command-palette-button')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('command-palette-input')), 'australia 셋업');
      await t.pump();
      expect(find.byKey(const ValueKey('command-/tracks/au')), findsOneWidget);

      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();

      expect(find.text('body:track:au'), findsOneWidget);
      expect(find.byKey(const ValueKey('command-palette')), findsNothing);
      expect(_isMenuSelected(t, '/tracks'), isTrue);
    });

    testWidgets('좁은 화면에서도 Ctrl+K로 검색 창을 열고 Esc로 닫는다', (t) async {
      await _pumpShell(t, _narrow);

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('command-palette')), findsNothing);
    });
  });

  group('isNavItemSelected', () {
    final dashboard = navItems.firstWhere((i) => i.path == '/');
    final laps = navItems.firstWhere((i) => i.path == '/laps');
    final sessions = navItems.firstWhere((i) => i.path == '/sessions');
    final seasons = navItems.firstWhere((i) => i.path == '/seasons');
    final tracks = navItems.firstWhere((i) => i.path == '/tracks');

    test('메뉴는 Dashboard · Seasons · Sessions · Laps · Trends · Tracks이고 Telemetry App은 따로 있다', () {
      expect([for (final i in navItems) i.label], ['Dashboard', 'Seasons', 'Sessions', 'Laps', 'Trends', 'Tracks']);
      expect([for (final i in navItems) i.path], isNot(contains('/telemetry-app')));
      expect(telemetryAppNavItem.path, '/telemetry-app');
      expect(isNavItemSelected(telemetryAppNavItem, '/telemetry-app'), isTrue);
      expect(isNavItemSelected(telemetryAppNavItem, '/'), isFalse);
    });

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

    test('Tracks는 별칭인 예전 /setups 경로와 그 하위 경로도 선택한다', () {
      expect(tracks.aliases, contains('/setups'));
      expect(isNavItemSelected(tracks, '/tracks'), isTrue);
      expect(isNavItemSelected(tracks, '/tracks/au'), isTrue);
      expect(isNavItemSelected(tracks, '/setups'), isTrue);
      expect(isNavItemSelected(tracks, '/setups/au/s1'), isTrue);
      expect(isNavItemSelected(tracks, '/setupsfoo'), isFalse);
      expect(isNavItemSelected(laps, '/setups/au'), isFalse);
      expect(isNavItemSelected(dashboard, '/setups'), isFalse);
    });
  });

  group('commandEntries · filterCommands', () {
    final entries = commandEntries(const [_australia]);
    List<String> locations(List<CommandEntry> list) => [for (final e in list) e.location];

    test('메뉴 · Telemetry App · 계정 설정 다음에 트랙마다 개요 · 내 랩 항목을 둔다(리더보드는 혼자 쓰는 동안 뺐다)', () {
      expect(locations(entries), [
        '/',
        '/seasons',
        '/sessions',
        '/laps',
        '/trends',
        '/tracks',
        '/telemetry-app',
        '/settings',
        '/tracks/au',
        '/laps/tracks/au',
      ]);
      expect([for (final e in entries.take(7)) e.label],
          ['Dashboard', 'Seasons', 'Sessions', 'Laps', 'Trends', 'Tracks', 'Telemetry App']);
      expect([for (final e in entries.take(8)) e.detail], everyElement(isNull));
      final trackEntries = entries.skip(8).toList();
      expect([for (final e in trackEntries) e.label], everyElement('Australia'));
      expect([for (final e in trackEntries) e.detail], everyElement(isNotNull));
    });

    test('트랙이 없으면 메뉴 · Telemetry App · 계정 설정만', () {
      expect(locations(commandEntries(const [])), [
        '/',
        '/seasons',
        '/sessions',
        '/laps',
        '/trends',
        '/tracks',
        '/telemetry-app',
        '/settings',
      ]);
    });

    test('빈 검색(공백만)이면 모든 항목', () {
      expect(filterCommands(entries, ''), entries);
      expect(filterCommands(entries, '   '), entries);
    });

    test('대소문자를 무시하고 이름 · 부제 · 함께 찾을 말 어디서든 찾는다', () {
      expect(locations(filterCommands(entries, 'DASH')), ['/']);
      expect(locations(filterCommands(entries, '대시보드')), ['/']);
      expect(filterCommands(entries, '리더보드'), isEmpty);
    });

    test('예전 Setups를 찾으면 Tracks 메뉴와 트랙 개요가 나온다', () {
      expect(locations(filterCommands(entries, 'setup')), ['/tracks', '/tracks/au']);
    });

    test('낱말이 여럿이면 모두 들어 있는 항목만', () {
      expect(locations(filterCommands(entries, 'australia 랩')), ['/laps/tracks/au']);
      expect(locations(filterCommands(entries, '  Australia   셋업 ')), ['/tracks/au']);
    });

    test('맞는 항목이 없으면 빈 목록', () {
      expect(filterCommands(entries, 'zzz'), isEmpty);
    });
  });
}
