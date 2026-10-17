import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/core/router/app_router.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';
import 'package:simcenter_app/features/devices/presentation/telemetry_app_page.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';

import 'support/fakes.dart';

Future<GoRouter> _pumpApp(WidgetTester tester, {AppUser? user = testUser}) async {
  setViewSize(tester, const Size(1000, 800));
  final container = ProviderContainer(overrides: [
    fakeAuth(user),
    lapsRepositoryProvider.overrideWithValue(FakeLapsRepository()),
    devicesRepositoryProvider.overrideWithValue(FakeDevicesRepository()),
    rankingRepositoryProvider.overrideWithValue(FakeRankingRepository(
      tracks: const [Track(trackId: 't1', gameCode: 'F1_25', name: 'Monaco')],
    )),
    rankingHubClientProvider.overrideWithValue(FakeRankingHub()),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

void main() {
  testWidgets('로그인 상태로 스플래시를 벗어나면 /의 Dashboard로 간다', (t) async {
    final router = await _pumpApp(t);

    expect(_location(router), '/');
    expect(find.text('Welcome 홍길동!'), findsOneWidget);
  });

  testWidgets('로그인 상태에서 /home은 /로 리다이렉트된다', (t) async {
    final router = await _pumpApp(t);

    router.go('/home');
    await t.pumpAndSettle();

    expect(_location(router), '/');
    expect(find.text('Welcome 홍길동!'), findsOneWidget);
  });

  testWidgets('로그인 상태에서 /login은 /로 리다이렉트된다', (t) async {
    final router = await _pumpApp(t);

    router.go('/login');
    await t.pumpAndSettle();

    expect(_location(router), '/');
  });

  testWidgets('로그아웃 상태면 /login으로 보낸다', (t) async {
    final router = await _pumpApp(t, user: null);

    expect(_location(router), '/login');
  });

  testWidgets('/leaderboard?trackId= 와 /laps는 셸 안에서 열린다', (t) async {
    final router = await _pumpApp(t);

    router.go('/leaderboard?trackId=t1');
    await t.pumpAndSettle();
    expect(_location(router), '/leaderboard?trackId=t1');
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
    expect(find.text('Monaco'), findsOneWidget);

    router.go('/laps');
    await t.pumpAndSettle();
    expect(_location(router), '/laps');
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('/telemetry-app은 셸 안에서 Telemetry App 화면을 연다', (t) async {
    final router = await _pumpApp(t);

    router.go('/telemetry-app');
    await t.pumpAndSettle();

    expect(_location(router), '/telemetry-app');
    expect(find.byType(TelemetryAppPage), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
  });

  testWidgets('사이드바의 Telemetry App 메뉴로 이동한다', (t) async {
    final router = await _pumpApp(t);

    await t.tap(find.text('Telemetry App'));
    await t.pumpAndSettle();

    expect(_location(router), '/telemetry-app');
    expect(find.byType(TelemetryAppPage), findsOneWidget);
  });

  testWidgets('/laps/tracks/:trackId도 셸 안에서 열린다', (t) async {
    final router = await _pumpApp(t);

    router.go('/laps/tracks/t1');
    await t.pumpAndSettle();

    expect(_location(router), '/laps/tracks/t1');
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
    expect(find.byTooltip('트랙 목록'), findsOneWidget);
  });
}
