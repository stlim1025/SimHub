import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/widgets/error_retry.dart';
import 'package:simcenter_app/core/widgets/not_found_state.dart';
import 'package:simcenter_app/features/lap_detail/data/lap_detail_repository.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/profile/application/selected_game_provider.dart';
import 'package:simcenter_app/features/setups/data/setups_repository.dart';
import 'package:simcenter_app/features/setups/domain/setup_models.dart';
import 'package:simcenter_app/features/setups/presentation/setup_track_page.dart';
import 'package:simcenter_app/features/tracks/application/track_corners_provider.dart';
import 'package:simcenter_app/features/tracks/application/track_outlines_provider.dart';
import 'package:simcenter_app/features/tracks/data/tracks_repository.dart';
import 'package:simcenter_app/features/tracks/domain/theoretical_best.dart';
import 'package:simcenter_app/features/tracks/domain/track_outline.dart';
import 'package:simcenter_app/features/tracks/domain/track_overview_models.dart';
import 'package:simcenter_app/features/tracks/presentation/track_overview_page.dart';
import 'package:simcenter_app/features/tracks/presentation/track_side_panel.dart';
import 'package:simcenter_app/features/tracks/presentation/tracks_page.dart';

import 'support/lap_detail_harness.dart';
import 'support/fakes.dart';
import 'support/setups_fakes.dart';

Future<GoRouter> _pump(
  WidgetTester tester,
  String location, {
  FakeSetupsRepository? setupsRepo,
  FakeTracksRepository? tracksRepo,
  FakeLapDetailRepository? lapRepo,
  Map<String, TrackOutline> outlines = const {},
  Size size = const Size(1400, 2400),
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: location, routes: [
    GoRoute(
      path: '/tracks',
      builder: (_, state) => Scaffold(body: TracksPage(condition: state.uri.queryParameters['condition'])),
    ),
    GoRoute(
      path: '/tracks/:trackId',
      builder: (_, state) => Scaffold(
        body: TrackOverviewPage(
          trackId: state.pathParameters['trackId']!,
          tab: state.uri.queryParameters['tab'],
          condition: state.uri.queryParameters['condition'],
          session: state.uri.queryParameters['session'],
        ),
      ),
    ),
    GoRoute(
      path: '/setups/:trackId/:setupId',
      builder: (_, state) => Text('setup:${state.pathParameters['trackId']}/${state.pathParameters['setupId']}'),
    ),
    GoRoute(path: '/leaderboard', builder: (_, state) => Text('leaderboard:${state.uri.queryParameters['trackId']}')),
    GoRoute(path: '/laps/:lapId', builder: (_, state) => Text('lap:${state.pathParameters['lapId']}')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      setupsRepositoryProvider.overrideWithValue(setupsRepo ?? FakeSetupsRepository()),
      tracksRepositoryProvider.overrideWithValue(tracksRepo ?? FakeTracksRepository()),
      lapDetailRepositoryProvider.overrideWithValue(lapRepo ?? FakeLapDetailRepository()),
      selectedGameProvider.overrideWithValue('F1_26'),
      trackOutlinesProvider.overrideWith((ref) async => outlines),
      trackCornersProvider.overrideWith((ref) async => const {}),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

/// 버튼 묶음 칸([key])의 선택 상태(접근성 `selected`).
bool _isSegmentSelected(WidgetTester tester, String key) =>
    tester
        .widget<Semantics>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Semantics)).first)
        .properties
        .selected ??
    false;

/// 트랙 칸([trackId]) 안 글자.
Finder _inTile(String trackId, String text) =>
    find.descendant(of: find.byKey(ValueKey('track-tile-$trackId')), matching: find.text(text));

/// 트랙 칸([trackId])에 셋업 수 글자가 있는지.
Finder _setupCountIn(String trackId) =>
    find.descendant(of: find.byKey(ValueKey('track-tile-$trackId')), matching: find.textContaining('셋업'));

/// Dry 셋업 10 · Wet 셋업 4(Australia), Dry 10 · Wet 0(China), 셋업 없는 역방향(Austria Reverse).
final _setupTracks = [
  setupTrackOf('au', 'Australia', displayOrder: 1, circuitName: 'Melbourne Grand Prix Circuit', wetCount: 4),
  setupTrackOf('cn', 'China', displayOrder: 2, countryCode: 'CN', circuitName: 'Shanghai International Circuit'),
  setupTrackOf('at-r', 'Austria Reverse', displayOrder: 25, countryCode: 'AT', dryCount: 0),
];

SetupList _setupListOf(String condition, List<SetupListItem> items) =>
    SetupList(track: australiaRef, condition: condition, items: items, fetchedAt: DateTime.utc(2026, 10, 22, 9));

/// 위치가 있는 트레이스(지도를 그릴 수 있다).
final LapTrace _positionedTrace = LapTrace(
  lapId: 'l1',
  resolutionM: 5,
  timeMs: const [0, 100, 200, 300, 400],
  speedKph: const [200, 200, 200, 200, 200],
  throttle: const [50, 50, 50, 50, 50],
  brake: const [0, 0, 0, 0, 0],
  steer: const [0, 0, 0, 0, 0],
  gear: const [6, 6, 6, 6, 6],
  rpm: const [11000, 11000, 11000, 11000, 11000],
  worldPosX: const [0, 100, 100, 0, 0],
  worldPosZ: const [0, 0, 100, 100, 0],
);

final _top = [
  const TrackTopLap(rank: 1, displayName: 'tt_driver_1', teamName: 'Red Bull Racing', lapTimeMs: 77101, lapId: 'l1'),
  const TrackTopLap(rank: 2, displayName: 'michal', teamName: 'Ferrari', lapTimeMs: 77104, lapId: 'l2'),
];

final _best = [
  TrackBestLap(
    lapId: 'm1',
    lapTimeMs: 78000,
    sessionType: 'TimeTrial',
    teamName: 'McLaren',
    isValid: true,
    setAt: DateTime.utc(2026, 10, 20, 10),
  ),
  TrackBestLap(
    lapId: 'm2',
    lapTimeMs: 78500,
    sessionType: 'Race',
    isValid: false,
    setAt: DateTime.utc(2026, 10, 19, 10),
  ),
];

TheoreticalSegment _segment(int index, String lapId, int timeMs, int bestMs, {double? deploy, double? bestDeploy}) =>
    TheoreticalSegment(
      index: index,
      startM: index * 1000,
      endM: (index + 1) * 1000,
      lapId: lapId,
      lapSetAt: DateTime.utc(2026, 10, 20, 10),
      timeMs: timeMs,
      bestLapTimeMs: bestMs,
      deployKj: deploy,
      harvestKj: deploy == null ? null : 0,
      bestLapDeployKj: bestDeploy,
      bestLapHarvestKj: bestDeploy == null ? null : 0,
    );

/// Time Trial(배터리 없음, 0.2초) · 비 오는 예선(배터리 있음, 0.3초 — 구간 1은 배터리를 1MJ 더 쓴 랩 q2).
final _theoretical = [
  TheoreticalBestGroup(
    sessionType: 'TimeTrial',
    visualTyreCompound: 16,
    lapCount: 4,
    lapLengthM: 2000,
    bestLapId: 't1',
    bestLapMs: 78100,
    theoreticalMs: 77900,
    unlimitedMs: 77900,
    hasBattery: false,
    segments: [_segment(0, 't2', 38800, 39000), _segment(1, 't1', 39100, 39100)],
  ),
  TheoreticalBestGroup(
    sessionType: 'Qualifying',
    visualTyreCompound: 17,
    isWet: true,
    lapCount: 3,
    lapLengthM: 2000,
    bestLapId: 'q1',
    bestLapMs: 79000,
    theoreticalMs: 78700,
    unlimitedMs: 78600,
    hasBattery: true,
    segments: [
      _segment(0, 'q1', 39500, 39500, deploy: 500, bestDeploy: 500),
      _segment(1, 'q2', 39200, 39500, deploy: 1500, bestDeploy: 500),
    ],
  ),
];

void main() {
  group('TracksPage', () {
    testWidgets('F1 26 Tracks 제목, 트랙 칸을 누르면 트랙 개요로', (t) async {
      final repo = FakeSetupsRepository(tracks: [
        setupTrackOf('au', 'Australia', circuitName: 'Melbourne Grand Prix Circuit'),
        setupTrackOf('cn', 'China', displayOrder: 2, countryCode: 'CN'),
      ]);
      final router = await _pump(t, '/tracks', setupsRepo: repo);

      expect(find.text('F1 26 Tracks'), findsOneWidget);
      expect(find.text('F1 2026'), findsOneWidget);
      expect(repo.trackRequests, ['F1_26']);

      await t.tap(find.byKey(const ValueKey('track-tile-cn')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/cn');
    });

    testWidgets('트랙이 없으면 빈 상태', (t) async {
      await _pump(t, '/tracks');

      expect(find.text('아직 등록된 트랙이 없다.'), findsOneWidget);
    });

    testWidgets('트랙 칸: 라운드 번호(역방향은 번호 없이 뒤)·서킷 이름·Dry 셋업 수(없으면 비움), Dry가 기본', (t) async {
      await _pump(t, '/tracks', setupsRepo: FakeSetupsRepository(tracks: _setupTracks));

      expect(find.text('Australia'), findsOneWidget);
      expect(find.text('Melbourne Grand Prix Circuit'), findsOneWidget);
      expect(_inTile('au', '1'), findsOneWidget);
      expect(_inTile('cn', '2'), findsOneWidget);
      expect(_inTile('at-r', '3'), findsNothing);
      expect(_inTile('au', '셋업 10'), findsOneWidget);
      expect(_inTile('cn', '셋업 10'), findsOneWidget);
      expect(_setupCountIn('at-r'), findsNothing);
      expect(_isSegmentSelected(t, 'setup-condition-Dry'), isTrue);
      expect(_isSegmentSelected(t, 'setup-condition-Wet'), isFalse);
    });

    testWidgets('Wet을 누르면 ?condition=wet로 Wet 셋업 수를 보이고, Dry를 누르면 쿼리 없이 돌아온다', (t) async {
      final router = await _pump(t, '/tracks', setupsRepo: FakeSetupsRepository(tracks: _setupTracks));

      await t.tap(find.byKey(const ValueKey('setup-condition-Wet')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks?condition=wet');
      expect(_isSegmentSelected(t, 'setup-condition-Wet'), isTrue);
      expect(_inTile('au', '셋업 4'), findsOneWidget);
      expect(_setupCountIn('cn'), findsNothing);

      await t.tap(find.byKey(const ValueKey('setup-condition-Dry')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks');
      expect(_inTile('au', '셋업 10'), findsOneWidget);
    });

    testWidgets('Wet 조건에서도 트랙 칸을 누르면 트랙 개요로', (t) async {
      final router = await _pump(t, '/tracks?condition=wet', setupsRepo: FakeSetupsRepository(tracks: _setupTracks));

      await t.tap(find.byKey(const ValueKey('track-tile-au')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au');
    });

    testWidgets('오류면 다시 시도', (t) async {
      await _pump(t, '/tracks', setupsRepo: FakeSetupsRepository(error: ApiException('서버 오류', statusCode: 500)));

      expect(find.byType(ErrorRetry), findsOneWidget);
    });
  });

  group('TrackOverviewPage', () {
    testWidgets('제목·서킷·기록 요약·Time Trial 상위·내 빠른 랩·트랙 정보', (t) async {
      await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf(top: _top, best: _best)}),
      );

      expect(find.text('F1 26 Australia'), findsOneWidget);
      expect(find.text('Melbourne Grand Prix Circuit'), findsWidgets);
      expect(find.text('Australia stats'), findsOneWidget);
      for (final (label, value) in [
        ('My best lap', '1:17.101'),
        ('My Time Trial best', '1:17.323'),
        ('Average lap time', '1:26.500'),
        ('Average AI difficulty', '82'),
        ('Laps', '42'),
        ('Sessions', '5'),
      ]) {
        expect(
          find.descendant(of: find.byKey(ValueKey('track-stat-$label')), matching: find.text(value)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.descendant(of: find.byKey(const ValueKey('track-top-1')), matching: find.text('tt_driver_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-top-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-best-lap-m1')), findsOneWidget);
      expect(find.text('Race · Invalid'), findsOneWidget);
      expect(find.text('Formula 1 Australian Grand Prix'), findsOneWidget);
      expect(find.text('5.278 km'), findsOneWidget);
      expect(find.text('1:19.813'), findsOneWidget);
    });

    testWidgets('넓은 화면이면 Best Lap Times와 Track Details를 나란히 둔다(보통 폭에서는 위아래)', (t) async {
      final tracksRepo = FakeTracksRepository(overviews: {'au': trackOverviewOf()});
      Offset topLeftOf(String title) => t.getTopLeft(find.text(title));

      await _pump(t, '/tracks/au', tracksRepo: tracksRepo);
      expect(topLeftOf('Track Details').dy, greaterThan(topLeftOf('Best Lap Times').dy));

      await _pump(t, '/tracks/au', tracksRepo: tracksRepo, size: const Size(1600, 2400));
      expect(topLeftOf('Track Details').dy, topLeftOf('Best Lap Times').dy);
      expect(topLeftOf('Track Details').dx, greaterThan(topLeftOf('Best Lap Times').dx));
    });

    testWidgets('mapLapId가 없으면 지도를 그리지 않는다', (t) async {
      final lapRepo = FakeLapDetailRepository(traces: {'l1': _positionedTrace});
      await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf()}),
        lapRepo: lapRepo,
      );

      expect(find.byKey(const ValueKey('track-overview-map')), findsNothing);
      expect(lapRepo.comparisonTraceRequests, isEmpty);
    });

    testWidgets('달린 기록이 없으면 서킷 윤곽 그림을 대신 그린다', (t) async {
      const outline = TrackOutline(width: 1, height: 0.5, points: [Offset(0, 0), Offset(1, 0), Offset(1, 0.5)]);
      await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf()}),
        outlines: {'Australia': outline},
      );

      expect(find.byKey(const ValueKey('track-outline-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-overview-map')), findsNothing);
    });

    testWidgets('기록 지도가 있으면 윤곽 대신 기록 지도를 그린다', (t) async {
      const outline = TrackOutline(width: 1, height: 0.5, points: [Offset(0, 0), Offset(1, 0), Offset(1, 0.5)]);
      await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf(mapLapId: 'l1')}),
        lapRepo: FakeLapDetailRepository(traces: {'l1': _positionedTrace}),
        outlines: {'Australia': outline},
      );

      expect(find.byKey(const ValueKey('track-overview-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-outline-map')), findsNothing);
    });

    testWidgets('목록 보드 오른쪽 열: 트랙 지도는 정보·내 기록과 따로 맨 위 카드(지도 랩이 없으면 서킷 윤곽 카드)', (t) async {
      const outline = TrackOutline(width: 1, height: 0.5, points: [Offset(0, 0), Offset(1, 0), Offset(1, 0.5)]);
      Future<void> pumpPanel(TrackOverview overview) async {
        setViewSize(t, const Size(400, 1600));
        await t.pumpWidget(ProviderScope(
          overrides: [
            tracksRepositoryProvider.overrideWithValue(FakeTracksRepository(overviews: {'au': overview})),
            lapDetailRepositoryProvider.overrideWithValue(
              FakeLapDetailRepository(details: {'l1': sampleDetail()}, traces: {'l1': _positionedTrace}),
            ),
            trackOutlinesProvider.overrideWith((ref) async => {'Australia': outline}),
            trackCornersProvider.overrideWith((ref) async => const {}),
          ],
          child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TrackSidePanel(trackId: 'au')))),
        ));
        await t.pumpAndSettle();
      }

      // 지도 랩이 있으면 레이스 리뷰와 같은 트랙 지도 카드(섹터 범례 포함)가 정보 카드 위에 따로 선다.
      await pumpPanel(trackOverviewOf(mapLapId: 'l1'));
      final map = find.byKey(const ValueKey('race-review-track-map'));
      expect(map, findsOneWidget);
      expect(find.descendant(of: map, matching: find.text('트랙 지도')), findsOneWidget);
      expect(find.descendant(of: map, matching: find.text('섹터 1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('track-side-info')), matching: map), findsNothing);
      expect(t.getTopLeft(map).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('track-side-info'))).dy));

      // 지도 랩이 없으면 서킷 윤곽을 같은 '트랙 지도' 카드로.
      await pumpPanel(trackOverviewOf());
      final outlineCard = find.byKey(const ValueKey('track-side-outline'));
      expect(outlineCard, findsOneWidget);
      expect(find.descendant(of: outlineCard, matching: find.byKey(const ValueKey('track-outline-map'))), findsOneWidget);
      expect(find.byKey(const ValueKey('race-review-track-map')), findsNothing);
    });

    testWidgets('mapLapId가 있으면 그 랩 트레이스로 트랙 지도를 그린다', (t) async {
      final lapRepo = FakeLapDetailRepository(traces: {'l1': _positionedTrace});
      await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf(mapLapId: 'l1')}),
        lapRepo: lapRepo,
      );

      expect(lapRepo.comparisonTraceRequests, ['l1']);
      expect(find.byKey(const ValueKey('track-overview-map')), findsOneWidget);
    });

    testWidgets('지도 랩의 섹터 시간이 있으면 랩 상세 지도처럼 섹터 범례를 보인다', (t) async {
      final lapRepo = FakeLapDetailRepository(details: {'l1': sampleDetail()}, traces: {'l1': _positionedTrace});
      await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf(mapLapId: 'l1')}),
        lapRepo: lapRepo,
      );

      expect(lapRepo.detailRequests, contains('l1'));
      expect(find.text('Sector 1'), findsOneWidget);
    });

    testWidgets('기록이 없으면 각 카드에 안내 문장', (t) async {
      await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(
          overviews: {'au': trackOverviewOf(stats: const TrackMyStats(lapCount: 0, sessionCount: 0))},
        ),
      );

      expect(find.text('아직 이 트랙의 Time Trial 기록이 없다.'), findsOneWidget);
      expect(find.text('이 트랙에서 달린 랩이 아직 없다.'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('track-stat-My best lap')), matching: find.text('-')),
        findsOneWidget,
      );
    });

    testWidgets('Top Setups 바로가기는 그 트랙 화면의 셋업 탭으로', (t) async {
      final router = await _pump(t, '/tracks/au', tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf()}));

      await t.tap(find.byKey(const ValueKey('track-link-setups')));
      await t.pumpAndSettle();

      expect(_location(router), '/tracks/au?tab=setups');
      expect(_isSegmentSelected(t, 'track-tab-setups'), isTrue);
      expect(find.byType(SetupTrackPage), findsOneWidget);
    });

    testWidgets('셋업 탭: 머리는 트랙 화면 그대로, 개요 대신 상위 셋업 표, 조건·세션·줄·Overview가 주소를 바꾼다', (t) async {
      final setupsRepo = FakeSetupsRepository(lists: {
        'au|Dry': _setupListOf('Dry', [setupItemOf('s1', 1), setupItemOf('s2', 2, team: 'Red Bull Racing')]),
        'au|Wet': _setupListOf('Wet', [setupItemOf('w1', 1, team: 'Ferrari')]),
      });
      final router = await _pump(
        t,
        '/tracks/au',
        setupsRepo: setupsRepo,
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf()}),
      );
      // 개요 탭이 기본: 셋업 표는 없고 기록 요약이 있다.
      expect(_isSegmentSelected(t, 'track-tab-overview'), isTrue);
      expect(find.byType(SetupTrackPage), findsNothing);
      expect(find.text('Australia stats'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('track-tab-setups')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au?tab=setups');
      expect(_isSegmentSelected(t, 'track-tab-setups'), isTrue);
      expect(find.text('F1 26 Australia'), findsOneWidget); // 트랙 화면 제목은 그대로.
      expect(find.text('F1 26 Australia Setups'), findsNothing); // 셋업 화면 머리는 싣지 않는다.
      expect(t.widget<SetupTrackPage>(find.byType(SetupTrackPage)).embedded, isTrue);
      expect(find.text('Australia stats'), findsNothing);
      expect(find.byKey(const ValueKey('track-link-setups')), findsNothing);
      expect(find.byKey(const ValueKey('setup-row-s1')), findsOneWidget);
      expect(find.text('Red Bull Racing'), findsOneWidget);
      expect(setupsRepo.listRequests.last, (trackId: 'au', condition: 'Dry', session: 'TimeTrial'));

      await t.tap(find.byKey(const ValueKey('setup-condition-Wet')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au?tab=setups&condition=wet');
      expect(_isSegmentSelected(t, 'track-tab-setups'), isTrue);
      expect(setupsRepo.listRequests.last, (trackId: 'au', condition: 'Wet', session: 'Race'));
      expect(find.text('Ferrari'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('setup-session-Qualifying')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au?tab=setups&condition=wet&session=qualifying');
      expect(setupsRepo.listRequests.last, (trackId: 'au', condition: 'Wet', session: 'Qualifying'));

      // 넓은 화면: 줄을 누르면 화면은 그대로, 목록 옆 칸에 그 셋업을 보인다.
      await t.tap(find.byKey(const ValueKey('setup-row-w1')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au?tab=setups&condition=wet&session=qualifying');
      expect(find.byKey(const ValueKey('setup-detail-panel')), findsOneWidget);

      router.go('/tracks/au?tab=setups');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('track-tab-overview')));
      await t.pumpAndSettle();
      expect(_location(router), '/tracks/au');
      expect(find.byType(SetupTrackPage), findsNothing);
      expect(find.text('Australia stats'), findsOneWidget);
    });

    testWidgets('주소의 tab이 setups가 아니면 개요', (t) async {
      await _pump(t, '/tracks/au?tab=nope', tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf()}));

      expect(_isSegmentSelected(t, 'track-tab-overview'), isTrue);
      expect(find.byType(SetupTrackPage), findsNothing);
      expect(find.text('Australia stats'), findsOneWidget);
    });

    testWidgets('혼자 쓰는 동안은 리더보드로 가는 바로가기·Full leaderboard 버튼이 없다', (t) async {
      await _pump(t, '/tracks/au', tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf()}));

      expect(find.byKey(const ValueKey('track-link-setups')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-link-leaderboard')), findsNothing);
      expect(find.text('Full leaderboard'), findsNothing);
    });

    testWidgets('내 빠른 랩 줄을 누르면 랩 상세로', (t) async {
      final router = await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf(best: _best)}),
      );

      await t.ensureVisible(find.byKey(const ValueKey('track-best-lap-m1')));
      await t.tap(find.byKey(const ValueKey('track-best-lap-m1')));
      await t.pumpAndSettle();

      expect(_location(router), '/laps/m1');
    });

    testWidgets('Theoretical Best: 조건을 고르면 그 조건의 이론상 최고·줄일 곳, 줄을 누르면 그 구간을 달린 랩으로', (t) async {
      final router = await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf()}, theoreticalBest: {'au': _theoretical}),
      );

      final card = find.byKey(const ValueKey('track-theoretical-best'));
      await t.ensureVisible(card);
      expect(find.descendant(of: card, matching: find.text('Time Trial · Soft')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('1:17.900')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('-0.200')), findsWidgets);
      // 배터리를 따지지 않는 Time Trial은 배터리 안내가 없다.
      expect(find.byKey(const ValueKey('theoretical-battery-note')), findsNothing);

      await t.tap(find.text('Qualifying · Medium · Rain'));
      await t.pumpAndSettle();
      expect(find.descendant(of: card, matching: find.text('1:18.700')), findsOneWidget);
      expect(find.byKey(const ValueKey('theoretical-battery-note')), findsOneWidget);
      expect(find.text('씀 +25%'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('theoretical-segment-1')));
      await t.pumpAndSettle();
      expect(_location(router), '/laps/q2');
    });

    testWidgets('Theoretical Best: 계산할 랩이 없으면 안내', (t) async {
      await _pump(t, '/tracks/au', tracksRepo: FakeTracksRepository(overviews: {'au': trackOverviewOf()}));

      expect(find.text('이론상 최고 랩은 텔레메트리가 온전히 기록된 유효한 Time Trial·예선 랩으로 계산한다. 이 트랙에는 아직 그런 랩이 없다.'), findsOneWidget);
    });

    testWidgets('없는 트랙이면 404 상태', (t) async {
      await _pump(t, '/tracks/zz');

      expect(find.byType(NotFoundState), findsOneWidget);
    });

    testWidgets('좁은 화면에서도 넘치지 않는다', (t) async {
      await _pump(
        t,
        '/tracks/au',
        tracksRepo: FakeTracksRepository(
          overviews: {'au': trackOverviewOf(top: _top, best: _best)},
          theoreticalBest: {'au': _theoretical},
        ),
        size: const Size(400, 3000),
      );

      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('track-details')), findsOneWidget);
    });
  });
}
