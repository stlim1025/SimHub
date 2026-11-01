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
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';

import 'support/fakes.dart';

final _now = DateTime.utc(2026, 10, 17, 12);

Future<FakeLapsRepository> _pumpDashboard(
  WidgetTester tester,
  List<Lap> laps, {
  List<AgentDevice> devices = const [],
  FakeSeasonsRepository? seasons,
}) async {
  setViewSize(tester, const Size(1000, 900));
  final repo = FakeLapsRepository(laps: laps);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
    GoRoute(path: '/laps', builder: (_, _) => const Text('body:laps')),
    GoRoute(path: '/laps/:lapId', builder: (_, state) => Text('body:lap:${state.pathParameters['lapId']}')),
    GoRoute(path: '/telemetry-app', builder: (_, _) => const Text('body:telemetry-app')),
    GoRoute(path: '/seasons/:id', builder: (_, state) => Text('body:season:${state.pathParameters['id']}')),
    GoRoute(path: '/sessions/:id', builder: (_, state) => Text('body:session:${state.pathParameters['id']}')),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      fakeAuth(),
      lapsRepositoryProvider.overrideWithValue(repo),
      devicesRepositoryProvider.overrideWithValue(FakeDevicesRepository(devices: devices)),
      seasonsRepositoryProvider.overrideWithValue(seasons ?? FakeSeasonsRepository()),
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
          seasonsRepositoryProvider.overrideWithValue(FakeSeasonsRepository()),
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

  group('시즌 영역', () {
    FakeSeasonsRepository seasonRepo({DateTime? completedAt}) => FakeSeasonsRepository(
          seasons: [seasonOf('s1', seasonNumber: 1, myPosition: 3, myPoints: 75, completedAt: completedAt)],
          details: {
            's1': seasonDetailOf(
              's1',
              season: seasonOf('s1', seasonNumber: 1, myPosition: 3, myPoints: 75, completedAt: completedAt),
              drivers: [
                driverStandingOf(1, name: 'NORRIS', points: 93),
                driverStandingOf(2, name: 'PIASTRI', points: 79),
                driverStandingOf(3, isPlayer: true, points: 75, wins: 1, podiums: 3),
                driverStandingOf(4, name: 'RUSSELL', points: 64),
                driverStandingOf(5, name: 'ANTONELLI', points: 63),
              ],
              calendar: [
                seasonCalendarRoundOf(1,
                    trackName: 'Melbourne', firstSessionId: 'p1', raceSessionId: 'race1', racePosition: 2, qualiPosition: 4, points: 18),
                seasonCalendarRoundOf(2,
                    trackName: 'Shanghai', firstSessionId: 'p2', raceSessionId: 'race2', racePosition: 1, qualiPosition: 1, points: 25),
                seasonCalendarRoundOf(3, trackName: 'Suzuka'),
              ],
            ),
          },
        );

    String statText(WidgetTester t, String key) => [
          for (final w in t.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))))
            w.data ?? '',
        ].join('|');

    testWidgets('진행 중인 시즌의 순위·포인트·선두와 차이·우승·포디움·라운드와 다음 라운드를 보여준다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo());

      expect(find.text('진행 중인 시즌'), findsOneWidget);
      expect(find.text('Driver Career Season 1'), findsOneWidget);
      expect(statText(t, 'dashboard-stat-position'), '순위|P3');
      expect(statText(t, 'dashboard-stat-points'), '포인트|75');
      expect(statText(t, 'dashboard-stat-gap'), '선두와 차이|-18|NORRIS');
      expect(statText(t, 'dashboard-stat-wins'), '우승|1');
      expect(statText(t, 'dashboard-stat-podiums'), '포디움|3');
      expect(statText(t, 'dashboard-stat-rounds'), '라운드|2 / 3');
      expect(statText(t, 'dashboard-next-round'), contains('Suzuka'));
    });

    testWidgets('최근 결과는 최근 라운드부터, 순위는 위쪽 3명과 내 앞뒤만 보여준다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo());

      final r2 = t.getTopLeft(find.byKey(const ValueKey('dashboard-round-2')));
      final r1 = t.getTopLeft(find.byKey(const ValueKey('dashboard-round-1')));
      expect(r2.dy, lessThan(r1.dy));
      expect(find.byKey(const ValueKey('dashboard-round-3')), findsNothing);

      for (final position in [1, 2, 3, 4]) {
        expect(find.byKey(ValueKey('dashboard-standing-$position')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('dashboard-standing-5')), findsNothing);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('나란히 놓인 최근 결과와 드라이버 순위 카드는 높이가 같다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo());

      Size cardOf(String title) => t.getSize(find.ancestor(of: find.text(title), matching: find.byType(Card)).first);
      expect(cardOf('최근 결과').height, cardOf('드라이버 순위').height);
      expect(
        t.getTopLeft(find.text('최근 결과')).dy,
        t.getTopLeft(find.text('드라이버 순위')).dy,
      );
    });

    testWidgets('최근 결과 줄을 누르면 그 주말 본 레이스로 간다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo());

      await t.tap(find.text('Shanghai'));
      await t.pumpAndSettle();
      expect(find.text('body:session:race2'), findsOneWidget);
    });

    testWidgets('View season을 누르면 시즌 상세로 간다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo());

      await t.tap(find.byKey(const ValueKey('dashboard-season-link')));
      await t.pumpAndSettle();
      expect(find.text('body:season:s1'), findsOneWidget);
    });

    testWidgets('완료된 시즌만 있으면 최근 시즌으로 보여준다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo(completedAt: DateTime(2026, 10, 25)));

      expect(find.text('최근 시즌'), findsOneWidget);
      expect(find.text('진행 중인 시즌'), findsNothing);
    });

    testWidgets('시즌이 없으면 시즌 영역을 그리지 않는다', (t) async {
      await _pumpDashboard(t, const []);

      expect(find.text('진행 중인 시즌'), findsNothing);
      expect(find.text('최근 시즌'), findsNothing);
    });
  });
}
