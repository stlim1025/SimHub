import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:simcenter_app/core/widgets/pagination_bar.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/laps/presentation/laps_page.dart';
import 'package:simcenter_app/features/laps/presentation/track_laps_page.dart';

import 'support/fakes.dart';

const _emptyText = '아직 기록된 랩이 없습니다';
const _trackPageSize = 15;

/// 첫 호출만 실패하고 이후엔 정상 응답하는 저장소(다시 시도 검증용).
class _FlakyLapsRepository extends FakeLapsRepository {
  _FlakyLapsRepository({super.laps, super.tracks});

  int failuresLeft = 1;

  @override
  Future<List<MyTrack>> getMyTracks() async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMyTracks();
  }

  @override
  Future<MyLaps> getMyLaps({
    String? trackId,
    String? sessionType,
    String sort = kLapSortRecent,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMyLaps(
      trackId: trackId,
      sessionType: sessionType,
      sort: sort,
      page: page,
      pageSize: pageSize,
    );
  }
}

Future<GoRouter> _pump(
  WidgetTester tester,
  LapsRepository repo, {
  String initialLocation = '/laps',
  Size size = const Size(1000, 2400),
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(path: '/laps', builder: (_, _) => const Scaffold(body: LapsPage())),
    GoRoute(
      path: '/laps/tracks/:trackId',
      builder: (_, state) => Scaffold(body: TrackLapsPage(trackId: state.pathParameters['trackId']!)),
    ),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [lapsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

String _dayOf(DateTime utc) => DateFormat('yyyy-MM-dd').format(utc.toLocal());

String _dateTimeOf(DateTime utc) => DateFormat('yyyy-MM-dd HH:mm').format(utc.toLocal());

List<Lap> _manyLaps(int count) => [
      for (var i = 0; i < count; i++) lapOf('l$i', 'Silverstone', 90000 + i),
    ];

OutlinedButton _button(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));

void main() {
  group('LapsPage', () {
    testWidgets('LapsPage_Empty_ShowsGuide', (t) async {
      await _pump(t, FakeLapsRepository());

      expect(find.text(_emptyText), findsOneWidget);
    });

    testWidgets('LapsPage_Tracks_ShowsNameBestLapCountAndLastDate', (t) async {
      final repo = FakeLapsRepository(tracks: [
        trackOf('t1', 'Silverstone', lapCount: 12, bestMs: 83452),
        trackOf('t2', 'Monaco', lapCount: 1, bestMs: null),
      ]);
      await _pump(t, repo);

      expect(find.text(_emptyText), findsNothing);
      expect(find.text('Silverstone'), findsOneWidget);
      expect(find.text('1:23.452'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Monaco'), findsOneWidget);
      expect(find.text('-'), findsOneWidget); // 유효 랩이 없는 트랙의 최고 기록.
      expect(find.text('1'), findsOneWidget);
      expect(find.text(_dayOf(DateTime.utc(2026, 10, 12, 9))), findsNWidgets(2));
    });

    testWidgets('LapsPage_TapTrack_OpensTrackLaps', (t) async {
      final repo = FakeLapsRepository(
        tracks: [trackOf('t1', 'Silverstone'), trackOf('t2', 'Monaco')],
        laps: [lapOf('l1', 'Monaco', 71000)],
      );
      final router = await _pump(t, repo);

      await t.tap(find.text('Monaco'));
      await t.pumpAndSettle();

      expect(_location(router), '/laps/tracks/t2');
      expect(repo.requests.single.trackId, 't2');
    });

    testWidgets('LapsPage_LoadFails_RetryReloads', (t) async {
      final repo = _FlakyLapsRepository(tracks: [trackOf('t1', 'Silverstone')]);
      await _pump(t, repo);

      expect(find.text('다시 시도'), findsOneWidget);

      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();

      expect(find.text('Silverstone'), findsOneWidget);
    });
  });

  group('TrackLapsPage', () {
    const trackPath = '/laps/tracks/t1';

    testWidgets('TrackLapsPage_Initial_RequestsRecentFirstPageOf15', (t) async {
      final repo = FakeLapsRepository(laps: [lapOf('l1', 'Silverstone', 83452)]);
      await _pump(t, repo, initialLocation: trackPath);

      expect(repo.requests, [
        (trackId: 't1', sort: 'recent', page: 1, pageSize: _trackPageSize),
      ]);
    });

    testWidgets('TrackLapsPage_Rows_ShowTimeValidMarkSectorsSessionAndDate', (t) async {
      final repo = FakeLapsRepository(laps: [
        lapOf(
          'l1',
          'Silverstone',
          83452,
          sessionType: 'TimeTrial',
          sectors: const [
            LapSector(sectorNumber: 1, sectorTimeMs: 27010),
            LapSector(sectorNumber: 2, sectorTimeMs: 31442),
            LapSector(sectorNumber: 3, sectorTimeMs: 25000),
          ],
        ),
      ]);
      await _pump(t, repo, initialLocation: trackPath);

      for (final header in ['랩타임', 'S1', 'S2', 'S3', '세션 유형', '날짜']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('1:23.452'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('0:27.010'), findsOneWidget);
      expect(find.text('0:31.442'), findsOneWidget);
      expect(find.text('0:25.000'), findsOneWidget);
      expect(find.text('TimeTrial'), findsOneWidget);
      expect(find.text(_dateTimeOf(DateTime.utc(2026, 10, 12, 9))), findsOneWidget);
    });

    testWidgets('TrackLapsPage_InvalidLapWithoutSectors_ShowsInvalidAndDashes', (t) async {
      final repo = FakeLapsRepository(laps: [lapOf('l1', 'Silverstone', 71000, isValid: false)]);
      await _pump(t, repo, initialLocation: trackPath);

      expect(find.text('1:11.000'), findsOneWidget);
      expect(find.text('무효'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.text('-'), findsNWidgets(3));
    });

    testWidgets('TrackLapsPage_ToggleFastest_RequestsFastestAndReorders', (t) async {
      final repo = FakeLapsRepository(laps: [
        lapOf('slow', 'Silverstone', 90000),
        lapOf('fast', 'Silverstone', 80000),
      ]);
      await _pump(t, repo, initialLocation: trackPath);

      double top(String text) => t.getTopLeft(find.text(text)).dy;
      expect(top('1:30.000'), lessThan(top('1:20.000'))); // recent: 서버가 준 순서 그대로.

      await t.tap(find.text('Fastest'));
      await t.pumpAndSettle();

      expect(repo.requests.last, (trackId: 't1', sort: 'fastest', page: 1, pageSize: _trackPageSize));
      expect(top('1:20.000'), lessThan(top('1:30.000')));

      await t.tap(find.text('Recent'));
      await t.pumpAndSettle();

      expect(repo.requests.last.sort, 'recent');
    });

    testWidgets('TrackLapsPage_FirstPage_ShowsLabelAndOnlyNextEnabled', (t) async {
      final repo = FakeLapsRepository(laps: _manyLaps(20));
      await _pump(t, repo, initialLocation: trackPath);

      expect(find.byType(PaginationBar), findsOneWidget); // 공용 페이지 바를 쓴다.
      expect(find.text('Showing 1 to 15 of 20'), findsOneWidget);
      expect(_button(t, '이전').onPressed, isNull);
      expect(_button(t, '다음').onPressed, isNotNull);
    });

    testWidgets('TrackLapsPage_NextAndPrevious_ChangePage', (t) async {
      final repo = FakeLapsRepository(laps: _manyLaps(20));
      await _pump(t, repo, initialLocation: trackPath);

      await t.tap(find.text('다음'));
      await t.pumpAndSettle();

      expect(repo.requests.last.page, 2);
      expect(find.text('Showing 16 to 20 of 20'), findsOneWidget);
      expect(_button(t, '다음').onPressed, isNull);
      expect(_button(t, '이전').onPressed, isNotNull);

      await t.tap(find.text('이전'));
      await t.pumpAndSettle();

      expect(repo.requests.last.page, 1);
      expect(find.text('Showing 1 to 15 of 20'), findsOneWidget);
    });

    testWidgets('TrackLapsPage_ToggleSort_ResetsToFirstPage', (t) async {
      final repo = FakeLapsRepository(laps: _manyLaps(20));
      await _pump(t, repo, initialLocation: trackPath);
      await t.tap(find.text('다음'));
      await t.pumpAndSettle();

      await t.tap(find.text('Fastest'));
      await t.pumpAndSettle();

      expect(repo.requests.last, (trackId: 't1', sort: 'fastest', page: 1, pageSize: _trackPageSize));
      expect(find.text('Showing 1 to 15 of 20'), findsOneWidget);
    });

    testWidgets('TrackLapsPage_Empty_ShowsGuide', (t) async {
      await _pump(t, FakeLapsRepository(), initialLocation: trackPath);

      expect(find.text(_emptyText), findsOneWidget);
      expect(find.byType(PaginationBar), findsNothing);
      expect(find.textContaining('Showing'), findsNothing);
    });

    testWidgets('TrackLapsPage_Title_UsesTrackNameFromMyTracks', (t) async {
      final repo = FakeLapsRepository(
        tracks: [trackOf('t1', 'Silverstone')],
        laps: [lapOf('l1', 'ignored-lap-track-name', 83452)],
      );
      await _pump(t, repo, initialLocation: trackPath);

      expect(find.text('Silverstone'), findsOneWidget);
    });

    testWidgets('TrackLapsPage_Title_FallsBackToLapTrackName', (t) async {
      final repo = FakeLapsRepository(laps: [lapOf('l1', 'Monaco', 71000)]);
      await _pump(t, repo, initialLocation: trackPath);

      expect(find.text('Monaco'), findsOneWidget);
    });

    testWidgets('TrackLapsPage_Back_ReturnsToTrackList', (t) async {
      final repo = FakeLapsRepository(tracks: [trackOf('t1', 'Silverstone')]);
      final router = await _pump(t, repo, initialLocation: trackPath);

      await t.tap(find.byTooltip('트랙 목록'));
      await t.pumpAndSettle();

      expect(_location(router), '/laps');
    });

    testWidgets('TrackLapsPage_LoadFails_RetryReloads', (t) async {
      final repo = _FlakyLapsRepository(laps: [lapOf('l1', 'Silverstone', 83452)]);
      await _pump(t, repo, initialLocation: trackPath);

      expect(find.text('다시 시도'), findsOneWidget);

      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();

      expect(find.text('1:23.452'), findsOneWidget);
    });

    testWidgets('TrackLapsPage_NarrowScreen_DoesNotOverflow', (t) async {
      final repo = FakeLapsRepository(laps: _manyLaps(20));
      await _pump(t, repo, initialLocation: trackPath, size: const Size(375, 2400));

      expect(t.takeException(), isNull);
      expect(find.text('Showing 1 to 15 of 20'), findsOneWidget);
    });
  });
}
