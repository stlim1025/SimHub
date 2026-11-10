import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/platform/download_launcher.dart';
import 'package:simcenter_app/core/widgets/not_found_state.dart';
import 'package:simcenter_app/features/profile/application/selected_game_provider.dart';
import 'package:simcenter_app/features/setups/data/setups_repository.dart';
import 'package:simcenter_app/features/setups/domain/setup_models.dart';
import 'package:simcenter_app/features/setups/presentation/setup_detail_page.dart';
import 'package:simcenter_app/features/setups/presentation/setup_track_page.dart';

import 'support/fakes.dart';
import 'support/setups_fakes.dart';

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeSetupsRepository repo,
  String location, {
  String game = 'F1_25',
  List<String>? opened,
  Size size = const Size(1400, 2400),
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: location, routes: [
    // 셋업 목록(`/setups`)은 Tracks에 합쳤다 — 트랙별 셋업 주소는 트랙 화면의 셋업 탭(`/tracks/:trackId?tab=setups`).
    GoRoute(path: '/tracks', builder: (_, state) => Text('tracks:${state.uri.query}')),
    GoRoute(
      path: '/tracks/:trackId',
      builder: (_, state) => Scaffold(
        body: SetupTrackPage(
          trackId: state.pathParameters['trackId']!,
          condition: state.uri.queryParameters['condition'],
          session: state.uri.queryParameters['session'],
        ),
      ),
    ),
    GoRoute(
      path: '/setups/:trackId/:setupId',
      builder: (_, state) => Scaffold(
        body: SetupDetailPage(trackId: state.pathParameters['trackId']!, setupId: state.pathParameters['setupId']!),
      ),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      setupsRepositoryProvider.overrideWithValue(repo),
      selectedGameProvider.overrideWithValue(game),
      downloadLauncherProvider.overrideWithValue((url) {
        opened?.add(url);
        return true;
      }),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

SetupList _listOf(String condition, List<SetupListItem> items) =>
    SetupList(track: australiaRef, condition: condition, items: items, fetchedAt: DateTime.utc(2026, 10, 22, 9));

void main() {
  // 트랙 목록의 Dry | Wet · 트랙별 셋업 수(예전 SetupsPage)는 tracks_pages_test.dart의 TracksPage에서 본다.
  group('SetupTrackPage', () {
    final repo = FakeSetupsRepository(lists: {
      'au|Dry': _listOf('Dry', [setupItemOf('s1', 1), setupItemOf('s2', 2, team: 'Red Bull Racing')]),
      'au|Wet': _listOf('Wet', [setupItemOf('w1', 1, team: 'Ferrari')]),
    });

    testWidgets('제목과 # | TEAM | SESSION | LAP TIME 표(USER 칸 없음)', (t) async {
      await _pump(t, repo, '/tracks/au');

      expect(find.text('F1 25 Australia Setups'), findsOneWidget);
      for (final header in ['#', 'TEAM', 'SESSION', 'LAP TIME']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('USER'), findsNothing);
      expect(find.byKey(const ValueKey('setup-row-s1')), findsOneWidget);
      expect(find.byKey(const ValueKey('setup-row-s2')), findsOneWidget);
      expect(find.text('Red Bull Racing'), findsOneWidget);
      expect(find.text('1:15.975'), findsOneWidget);
    });

    testWidgets('Wet을 누르면 주소와 요청 조건이 Wet으로 바뀐다', (t) async {
      final router = await _pump(t, repo, '/tracks/au');

      await t.tap(find.byKey(const ValueKey('setup-condition-Wet')));
      await t.pumpAndSettle();

      expect(_location(router), '/tracks/au?tab=setups&condition=wet');
      expect(repo.listRequests.last, (trackId: 'au', condition: 'Wet', session: 'Race'));
      expect(find.text('Ferrari'), findsOneWidget);
    });

    testWidgets('세션 종류를 고르면 주소와 요청이 바뀌고, Wet에는 Time Trial이 없다', (t) async {
      final router = await _pump(t, repo, '/tracks/au');
      expect(repo.listRequests.last, (trackId: 'au', condition: 'Dry', session: 'TimeTrial'));

      await t.tap(find.byKey(const ValueKey('setup-session-Race')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au?tab=setups&session=race');
      expect(repo.listRequests.last, (trackId: 'au', condition: 'Dry', session: 'Race'));

      await t.tap(find.byKey(const ValueKey('setup-condition-Wet')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au?tab=setups&condition=wet'); // 레이스는 Wet 기본이라 session 쿼리 없음
      expect(find.byKey(const ValueKey('setup-session-TimeTrial')), findsNothing);
      expect(find.byKey(const ValueKey('setup-session-Qualifying')), findsOneWidget);

      // 다시 Dry로 오면 Dry 기본(타임 트라이얼)으로.
      await t.tap(find.byKey(const ValueKey('setup-condition-Dry')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au?tab=setups');
      expect(repo.listRequests.last, (trackId: 'au', condition: 'Dry', session: 'TimeTrial'));
    });

    testWidgets('넓으면 목록 옆에 1위 셋업을 보이고, 줄을 누르면 옆 칸만 그 셋업으로 바뀐다', (t) async {
      final detailRepo = FakeSetupsRepository(
        lists: {'au|Dry': _listOf('Dry', [setupItemOf('s1', 1), setupItemOf('s2', 2, team: 'Red Bull Racing')])},
        details: {
          's1': setupDetailOf('s1'),
          's2': setupDetailOf('s2', sections: const [
            (title: 'Suspension', items: [(label: 'Front Ride Height', value: '30')]),
          ]),
        },
      );
      final router = await _pump(t, detailRepo, '/tracks/au');

      final panel = find.byKey(const ValueKey('setup-detail-panel'));
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.textContaining('Aerodynamics')), findsWidgets);
      expect(t.getTopLeft(panel).dx, greaterThan(t.getTopLeft(find.byKey(const ValueKey('setup-row-s1'))).dx));

      await t.tap(find.byKey(const ValueKey('setup-row-s2')));
      await t.pumpAndSettle();

      expect(_location(router), '/tracks/au'); // 화면은 그대로
      expect(find.descendant(of: panel, matching: find.textContaining('Suspension')), findsWidgets);
      expect(find.descendant(of: panel, matching: find.textContaining('Aerodynamics')), findsNothing);
      expect(detailRepo.detailRequests, ['s1', 's2']);
    });

    testWidgets('좁으면 목록만 두고, 줄을 누르면 셋업 상세로', (t) async {
      final router = await _pump(t, repo, '/tracks/au', size: const Size(900, 2400));

      expect(find.byKey(const ValueKey('setup-detail-panel')), findsNothing);
      await t.tap(find.byKey(const ValueKey('setup-row-s2')));
      await t.pumpAndSettle();

      expect(_location(router), '/setups/au/s2');
    });

    testWidgets('셋업이 없으면 빈 상태, [트랙 목록으로]는 Tracks로', (t) async {
      final router = await _pump(t, FakeSetupsRepository(), '/tracks/au');

      expect(find.text('아직 가져온 셋업이 없다.'), findsOneWidget);

      await t.tap(find.text('트랙 목록으로'));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks');
    });
  });

  group('SetupDetailPage', () {
    testWidgets('제목 · 요약 · 묶음 카드(작성자 줄 없음)', (t) async {
      await _pump(t, FakeSetupsRepository(details: {'s1': setupDetailOf('s1')}), '/setups/au/s1');

      expect(find.text('F1 25 Australia Setup (Dry)'), findsOneWidget);
      expect(find.textContaining('by '), findsNothing);
      for (final (label, value) in [
        ('Team', 'Aston Martin'),
        ('Session', 'Time Trial'),
        ('Lap time', '1:15.974'),
        ('Conditions', 'Dry'),
        ('Steering', 'Wheel'),
        ('Date', '2025-12-22'),
      ]) {
        expect(
          find.descendant(of: find.byKey(ValueKey('setup-meta-$label')), matching: find.text(value)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.byKey(const ValueKey('setup-group-Aerodynamics')), findsOneWidget);
      expect(find.byKey(const ValueKey('setup-group-Brakes')), findsOneWidget);
      expect(find.text('Front Wing'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('원본 사이트로 가는 버튼은 두지 않는다', (t) async {
      await _pump(t, FakeSetupsRepository(details: {'s1': setupDetailOf('s1')}), '/setups/au/s1');

      expect(find.text('View on F1Laps'), findsNothing);
    });

    testWidgets('없는 셋업이면 404 상태', (t) async {
      await _pump(t, FakeSetupsRepository(), '/setups/au/nope');

      expect(find.byType(NotFoundState), findsOneWidget);
    });

    testWidgets('좁은 화면에서도 넘치지 않는다', (t) async {
      await _pump(t, FakeSetupsRepository(details: {'s1': setupDetailOf('s1')}), '/setups/au/s1',
          size: const Size(400, 2400));

      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('setup-group-Brakes')), findsOneWidget);
    });
  });
}
