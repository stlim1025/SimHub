import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/lap_detail/data/public_lap_repository.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_display.dart';
import 'package:simcenter_app/features/lap_detail/domain/shared_lap.dart';
import 'package:simcenter_app/features/lap_detail/presentation/shared_lap_page.dart';
import 'package:simcenter_app/features/lap_detail/presentation/telemetry_tab.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

/// 공유 랩 화면을 셸 없이 띄운다. 다른 화면 경로는 `login`·`dashboard` 글자로 확인한다.
Future<GoRouter> _pumpShared(
  WidgetTester tester, {
  required FakePublicLapRepository repo,
  String location = '/share/laps/l1',
  AppUser? user,
}) async {
  setViewSize(tester, const Size(1000, 3000));
  final router = GoRouter(initialLocation: location, routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('dashboard')),
    GoRoute(path: '/login', builder: (_, _) => const Text('login')),
    GoRoute(
      path: '/share/laps/:lapId',
      builder: (_, state) => SharedLapPage(
        lapId: state.pathParameters['lapId']!,
        tab: state.uri.queryParameters['tab'],
      ),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      fakeAuth(user),
      publicLapRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

FakePublicLapRepository _repo({bool withTrace = true}) => FakePublicLapRepository(
      laps: {'l1': SharedLap(detail: sampleDetail(withComparison: false, sessionId: null), displayName: '공유 드라이버')},
      traces: {if (withTrace) 'l1': traceOf('l1')},
    );

void main() {
  group('sharedLapLocation', () {
    test('Telemetry 탭만 쿼리로 싣고 그 밖은 경로만', () {
      expect(sharedLapLocation('l1'), '/share/laps/l1');
      expect(sharedLapLocation('l1', tab: kLapTabDetails), '/share/laps/l1');
      expect(sharedLapLocation('l1', tab: kLapTabBest), '/share/laps/l1');
      expect(sharedLapLocation('l1', tab: kLapTabTelemetry), '/share/laps/l1?tab=telemetry');
    });

    test('공유 화면의 탭은 details·telemetry만(best는 details)', () {
      expect(normalizeSharedLapTab('telemetry'), kLapTabTelemetry);
      expect(normalizeSharedLapTab('best'), kLapTabDetails);
      expect(normalizeSharedLapTab(null), kLapTabDetails);
    });
  });

  testWidgets('로그인 없이 머리줄·드라이버 이름·Lap Details를 보이고 로그인이 필요한 것은 숨긴다', (t) async {
    final repo = _repo();
    await _pumpShared(t, repo: repo);

    expect(repo.lapRequests, ['l1']);
    expect(find.text('SimHub'), findsOneWidget);
    expect(find.text('Jeddah Lap 1:38.448'), findsOneWidget);
    expect(find.text('공유 드라이버'), findsOneWidget);
    expect(find.text('Lap Details'), findsWidgets);
    expect(find.text('Lap Time'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);

    expect(find.text('Your Best Laps'), findsNothing);
    expect(find.text('Comparison'), findsNothing);
    expect(find.textContaining('Compare with'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(find.text('세션 보기'), findsNothing);
  });

  testWidgets('[로그인]은 로그인 화면으로 간다', (t) async {
    final router = await _pumpShared(t, repo: _repo());
    await t.tap(find.text('로그인'));
    await t.pumpAndSettle();
    expect(locationOf(router), '/login');
  });

  testWidgets('로그인 상태면 [내 기록으로]가 Dashboard로 간다', (t) async {
    final loggedIn = await _pumpShared(t, repo: _repo(), user: testUser);
    expect(find.text('로그인'), findsNothing);
    await t.tap(find.text('내 기록으로'));
    await t.pumpAndSettle();
    expect(locationOf(loggedIn), '/');
  });

  testWidgets('Telemetry 탭은 공개 트레이스로 그래프를 그린다(비교 선 없음)', (t) async {
    final repo = _repo();
    final router = await _pumpShared(t, repo: repo);

    await t.tap(find.text('Telemetry'));
    await t.pumpAndSettle();

    expect(locationOf(router), '/share/laps/l1?tab=telemetry');
    expect(repo.traceRequests, ['l1']);
    final charts = t.widget<TelemetryCharts>(find.byType(TelemetryCharts));
    expect(charts.reference, isNull);
    expect(find.byKey(const ValueKey('telemetry-chart-delta')), findsNothing);
  });

  testWidgets('트레이스가 없으면 안내를 보인다', (t) async {
    await _pumpShared(t, repo: _repo(withTrace: false), location: '/share/laps/l1?tab=telemetry');

    expect(find.byType(TelemetryCharts), findsNothing);
    expect(find.text('이 랩은 텔레메트리가 저장되지 않았어요'), findsOneWidget);
  });

  testWidgets('없는 랩이면 404 상태', (t) async {
    await _pumpShared(t, repo: FakePublicLapRepository(), location: '/share/laps/nope');

    expect(find.text('찾을 수 없는 랩입니다.'), findsOneWidget);
  });
}
