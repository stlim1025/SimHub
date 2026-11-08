import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/time/clock_provider.dart';
import 'package:simcenter_app/features/dashboard/data/dashboard_season_store.dart';
import 'package:simcenter_app/features/dashboard/presentation/dashboard_page.dart';
import 'package:simcenter_app/features/devices/application/devices_providers.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';
import 'package:simcenter_app/features/devices/domain/device_models.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';
import 'package:simcenter_app/features/seasons/domain/season_models.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';
import 'package:simcenter_app/features/tracks/application/track_outlines_provider.dart';
import 'package:simcenter_app/features/tracks/domain/track_outline.dart';

import 'support/fakes.dart';

final _now = DateTime.utc(2026, 10, 17, 12);

/// 기본 화면 크기: 보드보다 좁은 쌓은 배치(최근 랩 | Personal Bests는 나란히). 시즌 영역까지 한 화면에 들어오게 길게 둔다.
const _stackedSize = Size(1000, 2000);

/// 넓은 보드 배치(본문 폭 1200 이상).
const _boardSize = Size(1600, 1600);

/// 테스트용 서킷 윤곽(사각형).
const _squareOutline = TrackOutline(
  width: 1,
  height: 1,
  points: [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
);

Future<FakeLapsRepository> _pumpDashboard(
  WidgetTester tester,
  List<Lap> laps, {
  List<AgentDevice> devices = const [],
  FakeSeasonsRepository? seasons,
  FakeSessionsRepository? sessions,
  List<MyTrack> tracks = const [],
  Map<String, TrackOutline> outlines = const {},
  Size size = _stackedSize,
  _MemorySeasonStore? seasonStore,
}) async {
  setViewSize(tester, size);
  final repo = FakeLapsRepository(laps: laps, tracks: tracks);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
    GoRoute(path: '/laps', builder: (_, _) => const Text('body:laps')),
    GoRoute(path: '/laps/:lapId', builder: (_, state) => Text('body:lap:${state.pathParameters['lapId']}')),
    GoRoute(
      path: '/laps/tracks/:trackId',
      builder: (_, state) => Text('body:track-laps:${state.pathParameters['trackId']}'),
    ),
    GoRoute(path: '/telemetry-app', builder: (_, _) => const Text('body:telemetry-app')),
    GoRoute(path: '/seasons/:id', builder: (_, state) => Text('body:season:${state.pathParameters['id']}')),
    GoRoute(path: '/sessions/:id', builder: (_, state) => Text('body:session:${state.pathParameters['id']}')),
    GoRoute(
      path: '/sessions/:id/highlights',
      builder: (_, state) => Text('body:highlights:${state.pathParameters['id']}'),
    ),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      fakeAuth(),
      lapsRepositoryProvider.overrideWithValue(repo),
      devicesRepositoryProvider.overrideWithValue(FakeDevicesRepository(devices: devices)),
      seasonsRepositoryProvider.overrideWithValue(seasons ?? FakeSeasonsRepository()),
      sessionsRepositoryProvider.overrideWithValue(sessions ?? FakeSessionsRepository()),
      trackOutlinesProvider.overrideWith((ref) async => outlines),
      clockProvider.overrideWithValue(() => _now),
      dashboardSeasonStoreProvider.overrideWithValue(seasonStore ?? _MemorySeasonStore()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

/// 대시보드 시즌 선택을 메모리에 기억하는 보관소(게임 코드 → 시즌 id).
class _MemorySeasonStore implements DashboardSeasonStore {
  _MemorySeasonStore([Map<String, String>? choices]) : choices = {...?choices};

  final Map<String, String> choices;

  @override
  Future<String?> read(String gameCode) async => choices[gameCode];

  @override
  Future<void> write(String gameCode, String seasonId) async => choices[gameCode] = seasonId;
}

/// 마지막 주행 시각을 고를 수 있는 내 트랙.
MyTrack _myTrack(String id, String name, {int? bestMs = 83452, int lapCount = 3, required DateTime lastSetAt}) => MyTrack(
      trackId: id,
      trackName: name,
      gameCode: 'F1_25',
      lapCount: lapCount,
      bestValidLapTimeMs: bestMs,
      lastSetAt: lastSetAt,
    );

/// 마지막 레이스(Zandvoort, P7 출발 → P3)와 그 상세(라운드 9, 모든 차 표본, 피트 1회, 우승과 4.218초).
FakeSessionsRepository _lastRaceRepo({bool withDetail = true, bool hasFieldSamples = true}) => FakeSessionsRepository(
      sessions: [
        sessionOf('race8', trackName: 'Hungaroring', classifiedAt: DateTime.utc(2026, 10, 10, 9)),
        sessionOf('race9',
            trackName: 'Zandvoort',
            countryCode: 'NL',
            myPosition: 3,
            myGridPosition: 7,
            myBestLapTimeMs: 72384,
            myPoints: 15,
            seasonNumber: 1,
            classifiedAt: DateTime.utc(2026, 10, 16, 9)),
        sessionOf('quali9', sessionType: 'Qualifying', sessionKind: 'Qualifying3', classifiedAt: DateTime.utc(2026, 10, 16, 8)),
      ],
      details: {
        if (withDetail)
          'race9': detailOf(
            'race9',
            trackName: 'Zandvoort',
            round: 9,
            hasFieldSamples: hasFieldSamples,
            results: [
              resultOf(1, totalRaceTimeMs: 5400000),
              resultOf(2, gapMs: 1904),
              resultOf(3, isPlayer: true, isAiControlled: false, gapMs: 4218, numPitStops: 1, bestLapTimeMs: 72384),
            ],
          ),
      },
    );

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
    await _pumpDashboard(t, [lapOf('l1', 'Silverstone', 83452, gameMode: 'GrandPrix')], size: _boardSize);

    expect(find.text('Grand Prix'), findsOneWidget);

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
      setViewSize(t, _stackedSize);
      await t.pumpWidget(ProviderScope(
        overrides: [
          fakeAuth(),
          lapsRepositoryProvider.overrideWithValue(
            FakeLapsRepository(laps: [lapOf('l1', 'Silverstone', 83452)]),
          ),
          agentDevicesProvider.overrideWith((ref) async => throw StateError('boom')),
          seasonsRepositoryProvider.overrideWithValue(FakeSeasonsRepository()),
          sessionsRepositoryProvider.overrideWithValue(FakeSessionsRepository()),
          trackOutlinesProvider.overrideWith((ref) async => const {}),
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

    testWidgets('최근 결과는 최근 라운드부터, 순위는 위쪽 5명까지 보여준다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo());

      final r2 = t.getTopLeft(find.byKey(const ValueKey('dashboard-round-2')));
      final r1 = t.getTopLeft(find.byKey(const ValueKey('dashboard-round-1')));
      expect(r2.dy, lessThan(r1.dy));
      expect(find.byKey(const ValueKey('dashboard-round-3')), findsNothing);

      for (final position in [1, 2, 3, 4, 5]) {
        expect(find.byKey(ValueKey('dashboard-standing-$position')), findsOneWidget);
      }
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

    testWidgets('진행 중인 시즌이 하나면 시즌 선택 상자가 없다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo());

      expect(find.byKey(const ValueKey('dashboard-season-picker')), findsNothing);
    });

    group('진행 중인 시즌이 여럿이면', () {
      SeasonSummary career(int number, {required int points, required DateTime last, DateTime? completedAt}) => seasonOf(
            's$number',
            seasonNumber: number,
            myPoints: points,
            lastSessionAt: last,
            completedAt: completedAt,
          );
      final older = career(1, points: 40, last: DateTime(2026, 10, 10));
      final newer = career(2, points: 75, last: DateTime(2026, 10, 16));
      final done = career(3, points: 99, last: DateTime(2026, 10, 17), completedAt: DateTime(2026, 10, 17));
      FakeSeasonsRepository twoActive() => FakeSeasonsRepository(
            seasons: [older, newer, done],
            details: {for (final s in [older, newer, done]) s.seasonId: seasonDetailOf(s.seasonId, season: s)},
          );

      testWidgets('가장 최근 시즌을 먼저 보이고, 선택 상자에서 고른 시즌으로 바꾸고 이 기기에 기억한다', (t) async {
        final store = _MemorySeasonStore();
        await _pumpDashboard(t, const [], seasons: twoActive(), seasonStore: store);

        expect(statText(t, 'dashboard-stat-points'), '포인트|75');
        await t.tap(find.byKey(const ValueKey('dashboard-season-picker')));
        await t.pumpAndSettle();
        // 진행 중인 시즌만 고를 수 있다(완료된 시즌 3은 없다).
        expect(find.byKey(const ValueKey('dashboard-season-option-s1')), findsOneWidget);
        expect(find.byKey(const ValueKey('dashboard-season-option-s2')), findsOneWidget);
        expect(find.byKey(const ValueKey('dashboard-season-option-s3')), findsNothing);

        await t.tap(find.byKey(const ValueKey('dashboard-season-option-s1')));
        await t.pumpAndSettle();
        expect(statText(t, 'dashboard-stat-points'), '포인트|40');
        expect(store.choices, {'F1_25': 's1'});

        await t.tap(find.byKey(const ValueKey('dashboard-season-link')));
        await t.pumpAndSettle();
        expect(find.text('body:season:s1'), findsOneWidget);
      });

      testWidgets('기억한 시즌으로 열고, 그 시즌이 끝났으면 가장 최근 진행 중인 시즌', (t) async {
        await _pumpDashboard(t, const [], seasons: twoActive(), seasonStore: _MemorySeasonStore({'F1_25': 's1'}));
        expect(statText(t, 'dashboard-stat-points'), '포인트|40');

        await _pumpDashboard(t, const [], seasons: twoActive(), seasonStore: _MemorySeasonStore({'F1_25': 's3'}));
        expect(statText(t, 'dashboard-stat-points'), '포인트|75');
      });
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

    testWidgets('드라이버 순위 줄마다 선두 대비 포인트 막대가 있다', (t) async {
      await _pumpDashboard(t, const [], seasons: seasonRepo());

      for (final position in [1, 2, 3, 4, 5]) {
        expect(find.byKey(ValueKey('dashboard-standing-bar-$position')), findsOneWidget);
      }
      Size fillOf(int position) => t.getSize(find.descendant(
            of: find.descendant(
              of: find.byKey(ValueKey('dashboard-standing-bar-$position')),
              matching: find.byType(FractionallySizedBox),
            ),
            matching: find.byType(ColoredBox),
          ));
      final leader = fillOf(1);
      final fifth = fillOf(5);
      expect(fifth.width, closeTo(leader.width * 63 / 93, 0.5));
    });
  });

  group('Last Race 타일', () {
    String textOf(WidgetTester t, String key) => [
          for (final w in t.widgetList<Text>(
            find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text), matchRoot: true),
          ))
            w.data ?? w.textSpan?.toPlainText() ?? '',
        ].join('|');

    testWidgets('가장 최근 레이스의 트랙·순위·출발 대비·베스트 랩·포인트와 상세의 라운드·피트·우승과 차이를 보여준다', (t) async {
      final sessions = _lastRaceRepo();
      await _pumpDashboard(t, const [], sessions: sessions, outlines: {'Zandvoort': _squareOutline});

      expect(sessions.requests.first.sessionType, 'Race');
      expect(sessions.detailRequests, ['race9']);
      expect(find.text('LAST RACE'), findsOneWidget);
      expect(find.text('Driver Career Season 1 · R9'), findsOneWidget);
      expect(find.text('Zandvoort'), findsOneWidget);
      expect(textOf(t, 'last-race-position'), 'P3');
      expect(textOf(t, 'last-race-start'), 'P7 출발 · +4 · 우승과 +0:04.218');
      expect(textOf(t, 'last-race-best-lap'), '베스트 랩|1:12.384');
      expect(textOf(t, 'last-race-pits'), '피트|1회');
      expect(textOf(t, 'last-race-points'), '포인트|15');
      expect(find.byKey(const ValueKey('last-race-track')), findsOneWidget);
    });

    testWidgets('하이라이트를 누르면 그 레이스의 하이라이트 화면으로 간다', (t) async {
      await _pumpDashboard(t, const [], sessions: _lastRaceRepo());

      await t.tap(find.byKey(const ValueKey('last-race-highlights')));
      await t.pumpAndSettle();
      expect(find.text('body:highlights:race9'), findsOneWidget);
    });

    testWidgets('세션 열기를 누르면 세션 상세로 간다', (t) async {
      await _pumpDashboard(t, const [], sessions: _lastRaceRepo());

      await t.tap(find.byKey(const ValueKey('last-race-open')));
      await t.pumpAndSettle();
      expect(find.text('body:session:race9'), findsOneWidget);
    });

    testWidgets('모든 차 표본이 없으면 하이라이트 버튼은 없고 세션 열기만 있다', (t) async {
      await _pumpDashboard(t, const [], sessions: _lastRaceRepo(hasFieldSamples: false));

      expect(find.byKey(const ValueKey('last-race-highlights')), findsNothing);
      expect(find.byKey(const ValueKey('last-race-open')), findsOneWidget);
    });

    testWidgets('세션 상세를 못 읽어도 목록 값으로 타일을 그리고 하이라이트는 숨긴다', (t) async {
      await _pumpDashboard(t, const [], sessions: _lastRaceRepo(withDetail: false));

      expect(textOf(t, 'last-race-position'), 'P3');
      expect(textOf(t, 'last-race-start'), 'P7 출발 · +4');
      expect(find.text('Driver Career Season 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('last-race-pits')), findsNothing);
      expect(find.byKey(const ValueKey('last-race-highlights')), findsNothing);
      expect(find.byKey(const ValueKey('last-race-open')), findsOneWidget);
    });

    testWidgets('완주하지 못한 레이스는 순위 대신 상태(DNF)를 보여준다', (t) async {
      await _pumpDashboard(t, const [], sessions: FakeSessionsRepository(sessions: [
        sessionOf('r1', myPosition: 18, myResultStatus: 'DidNotFinish'),
      ]));

      expect(textOf(t, 'last-race-position'), 'DNF');
    });

    testWidgets('서킷 윤곽이 없으면 그림 없이 결과만 그린다', (t) async {
      await _pumpDashboard(t, const [], sessions: _lastRaceRepo());

      expect(find.byKey(const ValueKey('last-race-track')), findsNothing);
      expect(textOf(t, 'last-race-position'), 'P3');
    });

    testWidgets('레이스가 없으면 안내 문구를 보여준다', (t) async {
      await _pumpDashboard(t, const []);

      expect(find.byKey(const ValueKey('last-race-empty')), findsOneWidget);
      expect(find.textContaining('아직 기록된 레이스가 없어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('last-race-tile')), findsNothing);
    });

    testWidgets('375px 폭에서도 넘치지 않는다(서킷 그림 위, 결과 아래)', (t) async {
      await _pumpDashboard(t, const [],
          sessions: _lastRaceRepo(), outlines: {'Zandvoort': _squareOutline}, size: const Size(375, 3000));

      expect(t.takeException(), isNull);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('last-race-position'))).dy,
        greaterThan(t.getBottomLeft(find.byKey(const ValueKey('last-race-track'))).dy),
      );
    });
  });

  group('Personal Bests 카드', () {
    testWidgets('유효 랩 기록이 있는 트랙만 최근에 달린 순서로 5개까지, 최고 랩과 함께 보여준다', (t) async {
      await _pumpDashboard(t, const [], tracks: [
        _myTrack('t1', 'Monza', bestMs: 80123, lastSetAt: DateTime.utc(2026, 10, 1)),
        _myTrack('t2', 'Zandvoort', bestMs: 71902, lapCount: 48, lastSetAt: DateTime.utc(2026, 10, 16)),
        _myTrack('t3', 'Spa', bestMs: null, lastSetAt: DateTime.utc(2026, 10, 15)),
        _myTrack('t4', 'Hungaroring', bestMs: 76904, lastSetAt: DateTime.utc(2026, 10, 14)),
        _myTrack('t5', 'Silverstone', lastSetAt: DateTime.utc(2026, 10, 13)),
        _myTrack('t6', 'Suzuka', lastSetAt: DateTime.utc(2026, 10, 12)),
        _myTrack('t7', 'Imola', lastSetAt: DateTime.utc(2026, 10, 11)),
      ]);

      final card = find.byKey(const ValueKey('dashboard-personal-bests'));
      const rows = ['t2', 't4', 't5', 't6', 't7'];
      for (var i = 1; i < rows.length; i++) {
        expect(
          t.getTopLeft(find.byKey(ValueKey('dashboard-pb-${rows[i]}'))).dy,
          greaterThan(t.getTopLeft(find.byKey(ValueKey('dashboard-pb-${rows[i - 1]}'))).dy),
        );
      }
      expect(find.byKey(const ValueKey('dashboard-pb-t1')), findsNothing);
      expect(find.byKey(const ValueKey('dashboard-pb-t3')), findsNothing);
      expect(find.descendant(of: card, matching: find.text('1:11.902')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('48랩')), findsOneWidget);
    });

    testWidgets('줄을 누르면 그 트랙의 랩 표(/laps/tracks/:id)로 간다', (t) async {
      await _pumpDashboard(t, const [], tracks: [_myTrack('t2', 'Zandvoort', lastSetAt: DateTime.utc(2026, 10, 16))]);

      await t.tap(find.byKey(const ValueKey('dashboard-pb-t2')));
      await t.pumpAndSettle();
      expect(find.text('body:track-laps:t2'), findsOneWidget);
    });

    testWidgets('최고 랩이 있는 트랙이 없으면 안내 문구를 보여준다', (t) async {
      await _pumpDashboard(t, const [], tracks: [_myTrack('t3', 'Spa', bestMs: null, lastSetAt: DateTime.utc(2026, 10, 15))]);

      expect(find.textContaining('트랙별 최고 랩이 아직 없어요'), findsOneWidget);
    });
  });

  testWidgets('최근 랩의 vs PB 칸: 그 트랙 최고 랩이면 PB, 아니면 차이, 무효 랩은 무효', (t) async {
    await _pumpDashboard(
      t,
      [
        lapOf('l1', 'Zandvoort', 72384),
        lapOf('l2', 'Zandvoort', 71902),
        lapOf('l3', 'Zandvoort', 70000, isValid: false),
      ],
      tracks: [_myTrack('t2', 'Zandvoort', bestMs: 71902, lastSetAt: DateTime.utc(2026, 10, 16))],
    );

    Finder inRow(String id, String text) =>
        find.descendant(of: find.byKey(ValueKey('recent-lap-$id')), matching: find.text(text));
    expect(inRow('l1', '+0.482'), findsOneWidget);
    expect(inRow('l2', 'PB'), findsOneWidget);
    expect(inRow('l3', '무효'), findsOneWidget);
  });

  group('보드 배치', () {
    testWidgets('넓으면 첫 줄 [Last Race | 연결 상태 + Personal Bests], 둘째 줄 [시즌 | 최근 랩]이고 첫 줄 바닥이 맞는다', (t) async {
      await _pumpDashboard(
        t,
        [lapOf('l1', 'Silverstone', 83452)],
        sessions: _lastRaceRepo(),
        outlines: {'Zandvoort': _squareOutline},
        tracks: [_myTrack('t2', 'Zandvoort', lastSetAt: DateTime.utc(2026, 10, 16))],
        seasons: FakeSeasonsRepository(
          seasons: [seasonOf('s1', seasonNumber: 1)],
          details: {'s1': seasonDetailOf('s1', season: seasonOf('s1', seasonNumber: 1))},
        ),
        size: _boardSize,
      );

      expect(t.takeException(), isNull);
      final tile = find.byKey(const ValueKey('last-race-tile'));
      final bests = find.byKey(const ValueKey('dashboard-personal-bests'));
      final status = find.text('Connection Status');
      expect(t.getTopLeft(status).dx, greaterThan(t.getTopRight(tile).dx));
      expect(t.getTopLeft(bests).dy, greaterThan(t.getTopLeft(status).dy));
      expect(t.getBottomLeft(bests).dy, closeTo(t.getBottomLeft(tile).dy, 0.5));

      final season = find.text('진행 중인 시즌');
      final recent = find.text('최근 랩');
      expect(t.getTopLeft(season).dy, greaterThan(t.getBottomLeft(tile).dy));
      expect(t.getTopLeft(recent).dx, greaterThan(t.getTopLeft(season).dx));
      expect(t.getTopLeft(recent).dy, greaterThan(t.getBottomLeft(bests).dy));
    });

    testWidgets('보드보다 좁으면 Last Race 타일이 맨 위 전체 폭이다', (t) async {
      await _pumpDashboard(t, const [], sessions: _lastRaceRepo());

      final tile = find.byKey(const ValueKey('last-race-tile'));
      expect(t.getSize(tile).width, 1000 - 40);
      expect(t.getTopLeft(find.text('Connection Status')).dy, greaterThan(t.getBottomLeft(tile).dy));
    });
  });
}
