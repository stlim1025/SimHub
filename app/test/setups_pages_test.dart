import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/platform/download_launcher.dart';
import 'package:simcenter_app/core/widgets/empty_state_card.dart';
import 'package:simcenter_app/core/widgets/error_retry.dart';
import 'package:simcenter_app/core/widgets/not_found_state.dart';
import 'package:simcenter_app/features/profile/application/selected_game_provider.dart';
import 'package:simcenter_app/features/setups/data/setups_repository.dart';
import 'package:simcenter_app/features/setups/domain/setup_models.dart';
import 'package:simcenter_app/features/setups/presentation/setup_detail_page.dart';
import 'package:simcenter_app/features/setups/presentation/setup_track_page.dart';
import 'package:simcenter_app/features/setups/presentation/setups_page.dart';

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
    GoRoute(
      path: '/setups',
      builder: (_, state) => Scaffold(body: SetupsPage(condition: state.uri.queryParameters['condition'])),
    ),
    GoRoute(
      path: '/setups/:trackId',
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

final _tracks = [
  setupTrackOf('au', 'Australia', displayOrder: 1, circuitName: 'Melbourne Grand Prix Circuit', wetCount: 4),
  setupTrackOf('cn', 'China', displayOrder: 2, countryCode: 'CN', circuitName: 'Shanghai International Circuit'),
  setupTrackOf('at-r', 'Austria Reverse', displayOrder: 25, countryCode: 'AT', dryCount: 0),
];

SetupList _listOf(String condition, List<SetupListItem> items) =>
    SetupList(track: australiaRef, condition: condition, items: items, fetchedAt: DateTime.utc(2026, 10, 22, 9));

void main() {
  group('SetupsPage', () {
    testWidgets('제목·이동 경로·트랙 칸(라운드 번호, 역방향은 번호 없이 뒤)', (t) async {
      await _pump(t, FakeSetupsRepository(tracks: _tracks), '/setups');

      expect(find.text('F1 25 Setups'), findsOneWidget);
      expect(find.text('F1 2025'), findsOneWidget);
      expect(find.text('Australia'), findsOneWidget);
      expect(find.text('Melbourne Grand Prix Circuit'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('track-tile-au')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('track-tile-cn')), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('track-tile-at-r')), matching: find.text('3')), findsNothing);
      // Dry 셋업 수가 보인다.
      expect(find.descendant(of: find.byKey(const ValueKey('track-tile-au')), matching: find.text('10')), findsOneWidget);
    });

    testWidgets('선택한 게임(F1 26)이 제목과 요청에 쓰인다', (t) async {
      final repo = FakeSetupsRepository(tracks: _tracks);
      await _pump(t, repo, '/setups', game: 'F1_26');

      expect(find.text('F1 26 Setups'), findsOneWidget);
      expect(repo.trackRequests, ['F1_26']);
    });

    testWidgets('Wet을 누르면 ?condition=wet, 트랙을 누르면 그 조건의 트랙 셋업으로', (t) async {
      final router = await _pump(t, FakeSetupsRepository(tracks: _tracks), '/setups');

      await t.tap(find.byKey(const ValueKey('setup-condition-Wet')));
      await t.pumpAndSettle();
      expect(_location(router), '/setups?condition=wet');
      expect(find.descendant(of: find.byKey(const ValueKey('track-tile-au')), matching: find.text('4')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('track-tile-au')));
      await t.pumpAndSettle();
      expect(_location(router), '/setups/au?condition=wet');
    });

    testWidgets('트랙이 없으면 빈 상태', (t) async {
      await _pump(t, FakeSetupsRepository(), '/setups');

      expect(find.byType(EmptyStateCard), findsOneWidget);
      expect(find.text('아직 가져온 셋업이 없다.'), findsOneWidget);
    });

    testWidgets('오류면 다시 시도', (t) async {
      await _pump(t, FakeSetupsRepository(error: ApiException('서버 오류', statusCode: 500)), '/setups');

      expect(find.byType(ErrorRetry), findsOneWidget);
    });
  });

  group('SetupTrackPage', () {
    final repo = FakeSetupsRepository(lists: {
      'au|Dry': _listOf('Dry', [setupItemOf('s1', 1), setupItemOf('s2', 2, team: 'Red Bull Racing')]),
      'au|Wet': _listOf('Wet', [setupItemOf('w1', 1, team: 'Ferrari')]),
    });

    testWidgets('제목과 # | TEAM | SESSION | LAP TIME 표(USER 칸 없음)', (t) async {
      await _pump(t, repo, '/setups/au');

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
      final router = await _pump(t, repo, '/setups/au');

      await t.tap(find.byKey(const ValueKey('setup-condition-Wet')));
      await t.pumpAndSettle();

      expect(_location(router), '/setups/au?condition=wet');
      expect(repo.listRequests.last, (trackId: 'au', condition: 'Wet', session: 'Race'));
      expect(find.text('Ferrari'), findsOneWidget);
    });

    testWidgets('세션 종류를 고르면 주소와 요청이 바뀌고, Wet에는 Time Trial이 없다', (t) async {
      final router = await _pump(t, repo, '/setups/au');
      expect(repo.listRequests.last, (trackId: 'au', condition: 'Dry', session: 'TimeTrial'));

      await t.tap(find.byKey(const ValueKey('setup-session-Race')));
      await t.pumpAndSettle();
      expect(_location(router), '/setups/au?session=race');
      expect(repo.listRequests.last, (trackId: 'au', condition: 'Dry', session: 'Race'));

      await t.tap(find.byKey(const ValueKey('setup-condition-Wet')));
      await t.pumpAndSettle();
      expect(_location(router), '/setups/au?condition=wet'); // 레이스는 Wet 기본이라 쿼리 없음
      expect(find.byKey(const ValueKey('setup-session-TimeTrial')), findsNothing);
      expect(find.byKey(const ValueKey('setup-session-Qualifying')), findsOneWidget);
    });

    testWidgets('줄을 누르면 셋업 상세로', (t) async {
      final router = await _pump(t, repo, '/setups/au');

      await t.tap(find.byKey(const ValueKey('setup-row-s2')));
      await t.pumpAndSettle();

      expect(_location(router), '/setups/au/s2');
    });

    testWidgets('셋업이 없으면 빈 상태', (t) async {
      await _pump(t, FakeSetupsRepository(), '/setups/au');

      expect(find.text('아직 가져온 셋업이 없다.'), findsOneWidget);
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
