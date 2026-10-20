import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/core/widgets/pagination_bar.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/laps/presentation/laps_page.dart';
import 'package:simcenter_app/features/laps/presentation/track_laps_page.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';

import 'support/fakes.dart';

const _emptyText = '아직 기록된 랩이 없습니다';
const _trackPageSize = 15;

/// `GET /tracks`(캘린더 순서).
const _masterTracks = [
  Track(trackId: 't0', gameCode: 'F1_25', name: 'Melbourne', countryCode: 'AU', displayOrder: 1),
  Track(trackId: 't1', gameCode: 'F1_25', name: 'Jeddah', countryCode: 'SA', displayOrder: 5),
  Track(trackId: 't2', gameCode: 'F1_25', name: 'Silverstone', countryCode: 'GB', displayOrder: 12),
];

const _ferrari = LapTeam(name: 'Ferrari', color: '#E8002D');

/// 첫 호출만 실패하고 이후엔 정상 응답하는 저장소(다시 시도 검증용).
class _FlakyLapsRepository extends FakeLapsRepository {
  _FlakyLapsRepository({super.laps, super.tracks});

  int failuresLeft = 1;

  @override
  Future<List<MyTrack>> getMyTracks({String? gameCode}) async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMyTracks(gameCode: gameCode);
  }

  @override
  Future<MyLaps> getMyLaps({
    String? trackId,
    String? sessionType,
    String sort = kLapSortRecent,
    bool validOnly = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMyLaps(
      trackId: trackId,
      sessionType: sessionType,
      sort: sort,
      validOnly: validOnly,
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
  List<Track> masterTracks = _masterTracks,
  ThemeData? theme,
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(path: '/laps', builder: (_, _) => const Scaffold(body: LapsPage())),
    GoRoute(
      path: '/laps/tracks/:trackId',
      builder: (_, state) => Scaffold(body: TrackLapsPage(trackId: state.pathParameters['trackId']!)),
    ),
    GoRoute(path: '/laps/:lapId', builder: (_, state) => Text('lap:${state.pathParameters['lapId']}')),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      lapsRepositoryProvider.overrideWithValue(repo),
      rankingRepositoryProvider.overrideWithValue(FakeRankingRepository(tracks: masterTracks)),
    ],
    child: MaterialApp.router(theme: theme, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

String _dayOf(DateTime utc) => DateFormat('yyyy-MM-dd').format(utc.toLocal());

List<Lap> _manyLaps(int count) => [
      for (var i = 0; i < count; i++) lapOf('l$i', 'Silverstone', 90000 + i),
    ];

OutlinedButton _button(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('LapsPage (/laps)', () {
    testWidgets('기록이 없으면 안내 카드와 트랙 메뉴(자리표시 Laps)를 보인다', (t) async {
      await _pump(t, FakeLapsRepository());

      expect(find.text(_emptyText), findsOneWidget);
      expect(find.text('Laps'), findsOneWidget);
      expect(find.byKey(const ValueKey('track-picker')), findsOneWidget);
    });

    testWidgets('마지막으로 달린 트랙(/me/tracks 첫 항목)의 표를 주소를 바꾸지 않고 바로 보인다', (t) async {
      final repo = FakeLapsRepository(
        tracks: [trackOf('t1', 'Jeddah', countryCode: 'SA'), trackOf('t2', 'Silverstone')],
        laps: [lapOf('l1', 'Jeddah', 98448)],
      );
      final router = await _pump(t, repo);

      expect(_location(router), '/laps');
      expect(repo.requests.single.trackId, 't1');
      expect(find.text('Jeddah'), findsOneWidget); // 제목(트랙 메뉴).
      expect(find.byKey(const ValueKey('track-flag-SA')), findsOneWidget);
      expect(find.text('1:38.448'), findsOneWidget);
    });

    testWidgets('트랙 메뉴에서 다른 트랙을 고르면 /laps/tracks/:trackId로 간다', (t) async {
      final repo = FakeLapsRepository(tracks: [trackOf('t1', 'Jeddah')], laps: [lapOf('l1', 'Jeddah', 98448)]);
      final router = await _pump(t, repo);

      await _tapAndSettle(t, find.byKey(const ValueKey('track-picker')));
      await _tapAndSettle(t, find.byKey(const ValueKey('track-option-t2')));

      expect(_location(router), '/laps/tracks/t2');
      expect(repo.requests.last.trackId, 't2');
    });

    testWidgets('표 행 위에 겹친 메뉴 항목을 누르면 랩 상세가 아니라 그 트랙으로 간다', (t) async {
      final repo = FakeLapsRepository(tracks: [trackOf('t0', 'Melbourne')], laps: _manyLaps(15));
      final router = await _pump(t, repo);
      await _tapAndSettle(t, find.byKey(const ValueKey('track-picker')));

      final option = find.byKey(const ValueKey('track-option-t2'));
      final rowUnder = find.byWidgetPredicate((w) {
        final key = w.key;
        return key is ValueKey<String> &&
            key.value.startsWith('lap-row-') &&
            t.getRect(find.byKey(key)).contains(t.getCenter(option));
      });
      expect(rowUnder, findsOneWidget); // 정말로 행 위에 겹쳐 있다.

      await _tapAndSettle(t, option);

      expect(_location(router), '/laps/tracks/t2');
    });

    testWidgets('메뉴가 열린 채로 메뉴 밖의 표 행을 누르면 메뉴만 닫히고 랩 상세로 가지 않는다', (t) async {
      final repo = FakeLapsRepository(tracks: [trackOf('t0', 'Melbourne')], laps: _manyLaps(15));
      final router = await _pump(t, repo);
      await _tapAndSettle(t, find.byKey(const ValueKey('track-picker')));

      final row = t.getRect(find.byKey(const ValueKey('lap-row-l1')));
      await t.tapAt(Offset(row.right - 40, row.center.dy)); // 메뉴(폭 280) 오른쪽 바깥.
      await t.pumpAndSettle();

      expect(_location(router), '/laps');
      expect(find.byKey(const ValueKey('track-option-t2')), findsNothing);
    });

    testWidgets('트랙 목록을 불러오지 못하면 다시 시도할 수 있다', (t) async {
      final repo = _FlakyLapsRepository(tracks: [trackOf('t1', 'Jeddah')], laps: [lapOf('l1', 'Jeddah', 98448)]);
      await _pump(t, repo);

      expect(find.text('다시 시도'), findsOneWidget);

      await _tapAndSettle(t, find.text('다시 시도'));

      expect(find.text('1:38.448'), findsOneWidget);
    });
  });

  group('TrackLapsPage (/laps/tracks/:trackId)', () {
    const trackPath = '/laps/tracks/t1';

    testWidgets('처음에는 최신순·전체 랩 1페이지(15개)를 요청한다', (t) async {
      final repo = FakeLapsRepository(laps: [lapOf('l1', 'Jeddah', 83452)]);
      await _pump(t, repo, initialLocation: trackPath);

      expect(repo.requests, [
        (trackId: 't1', sort: 'recent', validOnly: false, page: 1, pageSize: _trackPageSize),
      ]);
    });

    testWidgets('표 열은 TEAM · TIME · MODE · 날씨 · DATE이고 행은 팀 점·이름, 랩타임, 모드, 날씨 아이콘, 날짜다', (t) async {
      final repo = FakeLapsRepository(laps: [
        lapOf('l1', 'Jeddah', 98448, team: _ferrari, gameMode: 'DriverCareer', weather: 'Clear'),
      ]);
      await _pump(t, repo, initialLocation: trackPath);

      for (final header in ['TEAM', 'TIME', 'MODE', 'DATE']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.byTooltip('날씨'), findsOneWidget); // 날씨 열 머리글(아이콘).
      expect(find.text('Ferrari'), findsOneWidget);
      expect(find.byKey(const ValueKey('team-dot-l1')), findsOneWidget);
      expect(find.text('1:38.448'), findsOneWidget);
      expect(find.text('Driver Career'), findsOneWidget);
      expect(find.byTooltip('Clear'), findsOneWidget);
      expect(find.text(_dayOf(DateTime.utc(2026, 10, 12, 9))), findsOneWidget);
    });

    testWidgets('팀·모드·날씨를 모르는 옛 랩은 -, 세션 유형 라벨, -로 보인다', (t) async {
      final repo = FakeLapsRepository(laps: [lapOf('l1', 'Jeddah', 98448, sessionType: 'TimeTrial')]);
      await _pump(t, repo, initialLocation: trackPath);

      expect(find.text('Time Trial'), findsOneWidget);
      expect(find.text('-'), findsNWidgets(2)); // TEAM, 날씨.
    });

    testWidgets('랩타임은 링크 색 굵은 글자이고, 유효 랩은 ✓ 원, 무효 랩은 빨간 ✕ + 툴팁', (t) async {
      final repo = FakeLapsRepository(laps: [
        lapOf('ok', 'Jeddah', 98448),
        lapOf('bad', 'Jeddah', 97000, isValid: false),
      ]);
      await _pump(t, repo, initialLocation: trackPath, theme: AppTheme.light);

      final time = t.widget<Text>(find.text('1:38.448'));
      final context = t.element(find.text('1:38.448'));
      expect(time.style?.color, context.palette.link);
      expect(time.style?.fontWeight, FontWeight.bold);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byTooltip('무효 랩'), findsOneWidget);
      expect(t.widget<Icon>(find.byIcon(Icons.cancel)).color, context.palette.danger);
    });

    testWidgets('행 어디를 눌러도 그 랩의 상세(/laps/:lapId)로 간다', (t) async {
      final repo = FakeLapsRepository(laps: [lapOf('l1', 'Jeddah', 98448, team: _ferrari)]);
      final router = await _pump(t, repo, initialLocation: trackPath);

      await _tapAndSettle(t, find.text('Ferrari'));

      expect(_location(router), '/laps/l1');
      expect(find.text('lap:l1'), findsOneWidget);
    });

    testWidgets('Fastest를 누르면 빠른 순으로 다시 읽고, Recent로 돌아갈 수 있다', (t) async {
      final repo = FakeLapsRepository(laps: [
        lapOf('slow', 'Jeddah', 90000),
        lapOf('fast', 'Jeddah', 80000),
      ]);
      await _pump(t, repo, initialLocation: trackPath);

      double top(String text) => t.getTopLeft(find.text(text)).dy;
      expect(top('1:30.000'), lessThan(top('1:20.000'))); // recent: 서버가 준 순서 그대로.

      await _tapAndSettle(t, find.text('Fastest'));

      expect(repo.requests.last, (trackId: 't1', sort: 'fastest', validOnly: false, page: 1, pageSize: _trackPageSize));
      expect(top('1:20.000'), lessThan(top('1:30.000')));

      await _tapAndSettle(t, find.text('Recent'));

      expect(repo.requests.last.sort, 'recent');
    });

    testWidgets('Recent·Fastest는 작은 테두리 버튼 묶음이고 고른 쪽이 선택 상태다', (t) async {
      final semantics = t.ensureSemantics();
      await _pump(t, FakeLapsRepository(laps: [lapOf('l1', 'Jeddah', 98448)]), initialLocation: trackPath);

      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(t.getSemantics(find.text('Recent')), isSemantics(isButton: true, isSelected: true));
      expect(t.getSemantics(find.text('Fastest')), isSemantics(isButton: true, isSelected: false));

      await _tapAndSettle(t, find.text('Fastest'));

      expect(t.getSemantics(find.text('Fastest')), isSemantics(isSelected: true));
      expect(t.getSemantics(find.text('Recent')), isSemantics(isSelected: false));
      semantics.dispose();
    });

    testWidgets('유효 랩만을 켜면 validOnly=true 1페이지로 다시 읽어 무효 랩이 빠진다', (t) async {
      final repo = FakeLapsRepository(laps: [
        ..._manyLaps(20),
        lapOf('bad', 'Jeddah', 70000, isValid: false),
      ]);
      await _pump(t, repo, initialLocation: trackPath);
      await _tapAndSettle(t, find.text('다음'));
      expect(find.byIcon(Icons.cancel), findsOneWidget); // 2페이지 마지막 행.

      await _tapAndSettle(t, find.text('유효 랩만'));

      expect(repo.requests.last, (trackId: 't1', sort: 'recent', validOnly: true, page: 1, pageSize: _trackPageSize));
      expect(find.text('Showing 1 to 15 of 20'), findsOneWidget);

      await _tapAndSettle(t, find.text('다음'));
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('유효 랩만인데 유효 랩이 없으면 그에 맞는 안내를 보인다', (t) async {
      final repo = FakeLapsRepository(laps: [lapOf('bad', 'Jeddah', 70000, isValid: false)]);
      await _pump(t, repo, initialLocation: trackPath);

      await _tapAndSettle(t, find.text('유효 랩만'));

      expect(find.text('유효 랩이 없습니다'), findsOneWidget);
    });

    testWidgets('첫 페이지는 안내 문구와 다음 버튼만 켜진 공용 페이지 바를 보인다', (t) async {
      await _pump(t, FakeLapsRepository(laps: _manyLaps(20)), initialLocation: trackPath);

      expect(find.byType(PaginationBar), findsOneWidget);
      expect(find.text('Showing 1 to 15 of 20'), findsOneWidget);
      expect(_button(t, '이전').onPressed, isNull);
      expect(_button(t, '다음').onPressed, isNotNull);
    });

    testWidgets('다음·이전으로 페이지를 바꾸고, 정렬을 바꾸면 1페이지로 돌아간다', (t) async {
      final repo = FakeLapsRepository(laps: _manyLaps(20));
      await _pump(t, repo, initialLocation: trackPath);

      await _tapAndSettle(t, find.text('다음'));
      expect(repo.requests.last.page, 2);
      expect(find.text('Showing 16 to 20 of 20'), findsOneWidget);
      expect(_button(t, '다음').onPressed, isNull);

      await _tapAndSettle(t, find.text('이전'));
      expect(repo.requests.last.page, 1);

      await _tapAndSettle(t, find.text('다음'));
      await _tapAndSettle(t, find.text('Fastest'));
      expect(repo.requests.last, (trackId: 't1', sort: 'fastest', validOnly: false, page: 1, pageSize: _trackPageSize));
    });

    testWidgets('랩이 없으면 안내만 보이고 페이지 바는 없다', (t) async {
      await _pump(t, FakeLapsRepository(), initialLocation: trackPath);

      expect(find.text(_emptyText), findsOneWidget);
      expect(find.byType(PaginationBar), findsNothing);
    });

    testWidgets('제목은 트랙 마스터의 국기 + 이름이다', (t) async {
      await _pump(t, FakeLapsRepository(laps: [lapOf('l1', 'ignored', 83452)]), initialLocation: trackPath);

      expect(find.text('Jeddah'), findsOneWidget);
      expect(find.byKey(const ValueKey('track-flag-SA')), findsOneWidget);
    });

    testWidgets('트랙 마스터에 없으면 내 트랙 이름, 그것도 없으면 랩의 트랙 이름을 제목으로 쓴다', (t) async {
      await _pump(
        t,
        FakeLapsRepository(tracks: [trackOf('t9', 'Portimão', countryCode: 'PT')], laps: [lapOf('l1', 'Portimão', 1)]),
        initialLocation: '/laps/tracks/t9',
      );
      expect(find.text('Portimão'), findsOneWidget);
      expect(find.byKey(const ValueKey('track-flag-PT')), findsOneWidget);

      await _pump(t, FakeLapsRepository(laps: [lapOf('l1', 'Hockenheim', 1)]), initialLocation: '/laps/tracks/t8');
      expect(find.text('Hockenheim'), findsOneWidget);
    });

    testWidgets('다른 트랙을 고르면 정렬·필터·페이지가 처음으로 돌아간다', (t) async {
      final repo = FakeLapsRepository(laps: _manyLaps(20));
      await _pump(t, repo, initialLocation: trackPath);
      await _tapAndSettle(t, find.text('Fastest'));
      await _tapAndSettle(t, find.text('유효 랩만'));
      await _tapAndSettle(t, find.text('다음'));

      await _tapAndSettle(t, find.byKey(const ValueKey('track-picker')));
      await _tapAndSettle(t, find.byKey(const ValueKey('track-option-t2')));

      expect(repo.requests.last, (trackId: 't2', sort: 'recent', validOnly: false, page: 1, pageSize: _trackPageSize));
    });

    testWidgets('랩을 불러오지 못하면 다시 시도할 수 있다', (t) async {
      final repo = _FlakyLapsRepository(laps: [lapOf('l1', 'Jeddah', 83452)]);
      await _pump(t, repo, initialLocation: trackPath);

      expect(find.text('다시 시도'), findsOneWidget);

      await _tapAndSettle(t, find.text('다시 시도'));

      expect(find.text('1:23.452'), findsOneWidget);
    });

    testWidgets('콘텐츠 폭 600 미만이면 MODE·날씨 열을 숨기고 375px에서도 넘치지 않는다', (t) async {
      final repo = FakeLapsRepository(laps: [
        for (var i = 0; i < 20; i++)
          lapOf('l$i', 'Jeddah', 98000 + i,
              team: const LapTeam(name: 'Visa Cash App Racing Bulls F1 Team', color: '#6692FF'),
              gameMode: 'ChallengeCareer',
              weather: 'HeavyRain',
              isValid: i.isEven),
      ]);
      for (final theme in [AppTheme.dark, AppTheme.light]) {
        await _pump(t, repo, initialLocation: trackPath, size: const Size(375, 2400), theme: theme);

        expect(t.takeException(), isNull);
        expect(find.text('TEAM'), findsOneWidget);
        expect(find.text('MODE'), findsNothing);
        expect(find.byTooltip('날씨'), findsNothing);
        expect(find.text('Challenge Career'), findsNothing);
        expect(find.text('Showing 1 to 15 of 20'), findsOneWidget);
      }
    });
  });
}
