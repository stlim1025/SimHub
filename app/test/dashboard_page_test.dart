import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/time/clock_provider.dart';
import 'package:simcenter_app/features/dashboard/presentation/dashboard_page.dart';
import 'package:simcenter_app/features/devices/application/devices_providers.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';
import 'package:simcenter_app/features/devices/domain/device_models.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';

import 'support/fakes.dart';

final _now = DateTime.utc(2026, 10, 17, 12);

Future<FakeLapsRepository> _pumpDashboard(
  WidgetTester tester,
  List<Lap> laps, {
  List<AgentDevice> devices = const [],
}) async {
  setViewSize(tester, const Size(1000, 900));
  final repo = FakeLapsRepository(laps: laps);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
    GoRoute(path: '/laps', builder: (_, _) => const Text('body:laps')),
    GoRoute(path: '/laps/:lapId', builder: (_, state) => Text('body:lap:${state.pathParameters['lapId']}')),
    GoRoute(path: '/telemetry-app', builder: (_, _) => const Text('body:telemetry-app')),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      fakeAuth(),
      lapsRepositoryProvider.overrideWithValue(repo),
      devicesRepositoryProvider.overrideWithValue(FakeDevicesRepository(devices: devices)),
      clockProvider.overrideWithValue(() => _now),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('환영 문구에 표시 이름이 들어간다', (t) async {
    await _pumpDashboard(t, const []);

    expect(find.text('Welcome 홍길동!'), findsOneWidget);
  });

  testWidgets('최근 랩을 5개만 요청해 트랙명과 랩타임을 보여준다', (t) async {
    final repo = await _pumpDashboard(t, [
      lapOf('l1', 'Silverstone', 83452),
      lapOf('l2', 'Monaco', 71000, isValid: false),
    ]);

    expect(repo.pageSizes, [5]);
    expect(find.text('Silverstone'), findsOneWidget);
    expect(find.text('1:23.452'), findsOneWidget);
    expect(find.text('Monaco'), findsOneWidget);
    expect(find.text('1:11.000'), findsOneWidget);
    expect(find.text('무효'), findsOneWidget);
  });

  testWidgets('랩이 없으면 안내 문구를 보여준다', (t) async {
    await _pumpDashboard(t, const []);

    expect(find.textContaining('아직 기록된 랩이 없어요'), findsOneWidget);
  });

  testWidgets('최근 랩을 누르면 그 랩의 상세(/laps/:lapId)로 가고, 모드는 표시 라벨로 보인다', (t) async {
    await _pumpDashboard(t, [lapOf('l1', 'Silverstone', 83452, gameMode: 'GrandPrix')]);

    expect(find.textContaining('Grand Prix · '), findsOneWidget);

    await t.tap(find.text('1:23.452'));
    await t.pumpAndSettle();

    expect(find.text('body:lap:l1'), findsOneWidget);
  });

  testWidgets('View all lap times를 누르면 /laps로 이동한다', (t) async {
    await _pumpDashboard(t, [lapOf('l1', 'Silverstone', 83452)]);

    await t.tap(find.text('View all lap times'));
    await t.pumpAndSettle();

    expect(find.text('body:laps'), findsOneWidget);
  });

  group('연결 상태 카드', () {
    testWidgets('장치가 없으면 안내와 Telemetry App 이동 버튼을 보여준다', (t) async {
      await _pumpDashboard(t, const []);

      expect(find.text('연결된 PC가 없습니다'), findsOneWidget);

      await t.tap(find.text('연결하러 가기'));
      await t.pumpAndSettle();

      expect(find.text('body:telemetry-app'), findsOneWidget);
    });

    testWidgets('최근에 데이터를 받았으면 수신 중이라 표시하고 이동 버튼은 없다', (t) async {
      await _pumpDashboard(t, const [], devices: [
        deviceOf('d1', 'RIG-PC', lastSeenAt: _now.subtract(const Duration(minutes: 2))),
      ]);

      expect(find.text('데이터 수신 중'), findsOneWidget);
      expect(find.text('연결하러 가기'), findsNothing);
    });

    testWidgets('오래전이면 마지막 수신 시점을 알려준다', (t) async {
      await _pumpDashboard(t, const [], devices: [
        deviceOf('d1', 'RIG-PC', lastSeenAt: _now.subtract(const Duration(days: 82))),
      ]);

      expect(find.text('최근 데이터 없음 · 마지막 수신 82일 전'), findsOneWidget);
    });

    testWidgets('장치 조회가 실패해도 최근 랩은 그대로 보인다', (t) async {
      setViewSize(t, const Size(1000, 900));
      await t.pumpWidget(ProviderScope(
        overrides: [
          fakeAuth(),
          lapsRepositoryProvider.overrideWithValue(
            FakeLapsRepository(laps: [lapOf('l1', 'Silverstone', 83452)]),
          ),
          agentDevicesProvider.overrideWith((ref) async => throw StateError('boom')),
          clockProvider.overrideWithValue(() => _now),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const DashboardPage())]),
        ),
      ));
      await t.pumpAndSettle();

      expect(find.text('Silverstone'), findsOneWidget);
      expect(find.text('연결 상태를 불러오지 못했어요.'), findsOneWidget);
    });
  });
}
