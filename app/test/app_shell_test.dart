import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 셸 안에 세 메뉴의 자리표시 페이지를 올린 라우터.
GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (_, _) => const Text('body:dashboard')),
            GoRoute(path: '/laps', builder: (_, _) => const Text('body:laps')),
            GoRoute(path: '/leaderboard', builder: (_, _) => const Text('body:leaderboard')),
            GoRoute(path: '/telemetry-app', builder: (_, _) => const Text('body:telemetry-app')),
          ],
        ),
      ],
    );

Future<ProviderContainer> _pumpShell(WidgetTester tester, Size size, {FakeRankingHub? hub}) async {
  setViewSize(tester, size);
  final container = ProviderContainer(overrides: [
    fakeAuth(),
    if (hub != null) rankingHubClientProvider.overrideWithValue(hub),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('900px 이상이면 사이드바와 메뉴 라벨이 보인다', (t) async {
    await _pumpShell(t, _wide);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Laps'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Telemetry App'), findsOneWidget);
    expect(find.byTooltip('메뉴 열기'), findsNothing);
    expect(find.text('body:dashboard'), findsOneWidget);
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

    test('루트 경로는 Dashboard만 선택한다', () {
      expect(isNavItemSelected(dashboard, '/'), isTrue);
      expect(isNavItemSelected(laps, '/'), isFalse);
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
