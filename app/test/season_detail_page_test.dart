import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';
import 'package:simcenter_app/features/seasons/domain/season_display.dart';
import 'package:simcenter_app/features/seasons/domain/season_models.dart';
import 'package:simcenter_app/features/seasons/presentation/season_detail_page.dart';

import 'support/fakes.dart';

const _standingsNote = '기록된 세션 기준입니다. 라운드 번호는 기록된 주말 순서라 게임과 다를 수 있습니다.';

/// 첫 호출만 실패하고 이후엔 정상 응답하는 저장소(다시 시도 검증용).
class _FlakySeasonsRepository extends FakeSeasonsRepository {
  _FlakySeasonsRepository({super.details});

  int failuresLeft = 1;

  @override
  Future<SeasonDetail> getMySeason(String seasonId) async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMySeason(seasonId);
  }
}

/// 항상 500으로 실패하는 저장소.
class _ServerErrorRepository extends FakeSeasonsRepository {
  @override
  Future<SeasonDetail> getMySeason(String seasonId) async =>
      throw ApiException('서버가 아파요.', statusCode: 500);
}

/// 캘린더 3라운드: 1 = 레이스까지, 2 = 연습만(본 레이스 없음), 3 = 달리지 않음.
const List<SeasonCalendarRound> _calendar = [
  SeasonCalendarRound(
    round: 1,
    trackId: 't1',
    trackName: 'Bahrain',
    countryCode: 'BH',
    weekendId: 'w1',
    raceSessionId: 'r1',
    firstSessionId: 'q1',
    myTeamName: 'Ferrari',
    myTeamColor: '#E8002D',
    racePosition: 4,
    points: 12,
    qualiPosition: 2,
    raceAiDifficulty: 100,
    qualiAiDifficulty: 105,
  ),
  SeasonCalendarRound(
    round: 2,
    trackId: 't2',
    trackName: 'Jeddah',
    countryCode: 'SA',
    weekendId: 'w2',
    firstSessionId: 'p2',
    myTeamName: 'Ferrari',
    myTeamColor: '#E8002D',
  ),
  SeasonCalendarRound(round: 3, trackId: 't3', trackName: 'Suzuka', countryCode: 'JP', myTeamName: 'Ferrari'),
];

/// 라운드 2개 · 드라이버 3명(AI 2명 + 나) · 팀 2개.
SeasonDetail _detail({String id = 'se1', int seasonNumber = 1}) => seasonDetailOf(
      id,
      calendar: _calendar,
      season: seasonOf(
        id,
        gameMode: 'DriverCareer',
        roundCount: 2,
        myPosition: 3,
        myPoints: 87,
        firstSessionAt: DateTime(2026, 10, 17, 12),
        lastSessionAt: DateTime(2026, 10, 24, 12),
        seasonNumber: seasonNumber,
        myDriverName: 'GOM',
      ),
      rounds: [
        seasonRoundOf(
          1,
          trackName: 'Bahrain',
          winnerName: 'NORRIS',
          myPoints: 12,
          firstSessionAt: DateTime(2026, 10, 17, 12),
          sessions: [
            seasonSessionOf('q1', sessionType: 'Qualifying', sessionKind: 'Qualifying1', myPosition: 2),
            seasonSessionOf('r1', myPosition: 4),
          ],
        ),
        seasonRoundOf(
          2,
          trackName: 'Jeddah',
          winnerName: null,
          myPoints: null,
          firstSessionAt: DateTime(2026, 10, 24, 12),
          sessions: [
            seasonSessionOf('r2', myPosition: 20, myResultStatus: 'DidNotFinish'),
            seasonSessionOf('p2', sessionType: 'Practice', sessionKind: 'Practice1', myPosition: null, myResultStatus: null),
          ],
        ),
      ],
      drivers: [
        driverStandingOf(
          1,
          driverKey: 'driver:4',
          name: 'NORRIS',
          teamName: 'McLaren',
          teamColor: '#FF8000',
          points: 43,
          wins: 1,
          podiums: 2,
          cells: [
            standingCellOf(1, position: 1, resultStatus: 'Finished', points: 25),
            standingCellOf(2, position: 2, resultStatus: 'Finished', points: 18),
          ],
        ),
        driverStandingOf(
          2,
          driverKey: 'player',
          name: 'ME',
          teamName: 'Ferrari',
          teamColor: 'not-a-color',
          isPlayer: true,
          isAiControlled: false,
          points: 12,
          podiums: 0,
          cells: [
            standingCellOf(1, position: 4, resultStatus: 'Finished', points: 12),
            standingCellOf(2, position: 20, resultStatus: 'DidNotFinish'),
          ],
        ),
        driverStandingOf(
          3,
          driverKey: 'driver:14',
          name: 'ALONSO',
          teamName: 'Aston Martin',
          teamColor: '#229971',
          points: 3,
          cells: [standingCellOf(1, points: 3)], // 본 레이스 기록 없음(스프린트 점수만), 2라운드는 칸 없음
        ),
      ],
      constructors: [
        constructorStandingOf(1, teamId: 8, teamName: 'McLaren', teamColor: '#FF8000', points: 55, wins: 1),
        constructorStandingOf(2, teamId: 1, teamName: 'Ferrari', teamColor: '#E8002D', points: 12),
      ],
    );

/// 라운드 [roundCount]개 × 드라이버 3명. 모든 칸이 4위 완주.
SeasonDetail _manyRoundsDetail(int roundCount) => seasonDetailOf(
      'se1',
      rounds: [for (var r = 1; r <= roundCount; r++) seasonRoundOf(r)],
      drivers: [
        for (var d = 1; d <= 3; d++)
          driverStandingOf(
            d,
            name: d == 1 ? 'A VERY LONG DRIVER NAME FOR ELLIPSIS' : 'DRIVER $d',
            isPlayer: d == 2,
            cells: [for (var r = 1; r <= roundCount; r++) standingCellOf(r, position: d + 3, resultStatus: 'Finished', points: 1)],
          ),
      ],
    );

Future<GoRouter> _pumpPage(
  WidgetTester tester,
  SeasonsRepository repo, {
  String initialLocation = '/seasons/se1',
  Size size = const Size(1000, 2400),
  ThemeData? theme,
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(path: '/seasons', builder: (_, _) => const Text('seasons-list')),
    GoRoute(
      path: '/seasons/:seasonId',
      builder: (_, state) => Scaffold(
        body: SeasonDetailPage(
          seasonId: state.pathParameters['seasonId']!,
          tab: state.uri.queryParameters['tab'],
        ),
      ),
    ),
    GoRoute(path: '/sessions/:sessionId', builder: (_, state) => Text('session:${state.pathParameters['sessionId']}')),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [seasonsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router, theme: theme),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

int _selectedTab(WidgetTester t) => t.widget<TabBar>(find.byType(TabBar)).controller!.index;

Color? _textColor(WidgetTester t, Finder finder) => t.widget<Text>(finder).style?.color;

Finder _cell(String driverKey, int round) => find.byKey(ValueKey('results-cell-$driverKey-$round'));

Finder _cellText(String driverKey, int round) =>
    find.descendant(of: _cell(driverKey, round), matching: find.byType(Text));

/// 행 배경색(강조되지 않은 행은 null).
Color? _rowColor(WidgetTester t, String key) =>
    (t.widget<Container>(find.byKey(ValueKey(key))).decoration as BoxDecoration).color;

void main() {
  group('SeasonDetailPage - Season 탭', () {
    testWidgets('SeasonDetail_DefaultTab_IsSeason_ShowsCalendarTable', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      final router = await _pumpPage(t, repo);

      expect(repo.detailRequests, ['se1']);
      expect(_selectedTab(t), 0);
      for (final header in ['GRAND PRIX', 'TEAM', 'RACE', 'PTS (87)', 'QUALI', 'DIFF']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('Bahrain'), findsOneWidget);
      expect(find.text('Jeddah'), findsOneWidget);
      expect(find.text('Suzuka'), findsOneWidget);
      expect(find.text('Ferrari'), findsNWidgets(3)); // 달리지 않은 라운드도 시즌 팀
      expect(find.text('P4'), findsOneWidget); // 1라운드 레이스
      expect(find.text('P2'), findsOneWidget); // 1라운드 예선
      expect(find.text('12'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('105'), findsOneWidget);
      expect(find.text('-'), findsNWidgets(4)); // 2·3라운드 DIFF(레이스 / 예선)

      // Results·Standings 내용은 아직 없다.
      expect(find.text('Pts'), findsNothing);
      expect(find.text(_standingsNote), findsNothing);

      await t.tap(find.text('Bahrain'));
      await t.pumpAndSettle();

      // 본 레이스로 간다. from=season은 세션 화면의 뒤로 가기가 이 시즌으로 돌아오게 하는 표시다.
      expect(_location(router), '/sessions/r1?from=season');
      expect(find.text('session:r1'), findsOneWidget);
    });

    testWidgets('SeasonDetail_Season_NoRace_LinksFirstSession_UndrivenNotTappable', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      final router = await _pumpPage(t, repo);

      expect(find.byKey(const ValueKey('season-calendar-link-3')), findsNothing);

      await t.tap(find.text('Jeddah'));
      await t.pumpAndSettle();

      expect(_location(router), '/sessions/p2?from=season');
    });

    testWidgets('SeasonDetail_Header_ShowsSeasonTitleAndDriverName', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo);

      expect(find.text('Driver Career Season 1'), findsOneWidget);
      expect(find.text('GOM'), findsOneWidget);
    });

    testWidgets('SeasonDetail_SeasonPicker_ListsMySeasons_AndSwitches', (t) async {
      final repo = FakeSeasonsRepository(
        seasons: [_detail(id: 'se2', seasonNumber: 2).season, _detail().season],
        details: {'se1': _detail(), 'se2': _detail(id: 'se2', seasonNumber: 2)},
      );
      final router = await _pumpPage(t, repo);

      await t.tap(find.byKey(const ValueKey('track-picker')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('track-option-se2')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-option-se1')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-flag-fallback')), findsNothing); // 국기 없음

      await t.tap(find.byKey(const ValueKey('track-option-se2')));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/se2?tab=season');
      expect(find.text('Driver Career Season 2'), findsOneWidget);
    });

    testWidgets('SeasonDetail_Season_375_HidesTeamAndDiff_NoOverflow_BothThemes', (t) async {
      for (final theme in [AppTheme.dark, AppTheme.light]) {
        final repo = FakeSeasonsRepository(details: {'se1': _detail()});
        await _pumpPage(t, repo, size: const Size(375, 2400), theme: theme);

        expect(t.takeException(), isNull);
        expect(find.text('TEAM'), findsNothing);
        expect(find.text('DIFF'), findsNothing);
        expect(find.text('PTS (87)'), findsOneWidget);
        expect(find.text('Bahrain'), findsOneWidget);
      }
    });

    testWidgets('SeasonDetail_Back_ReturnsToSeasonList', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      final router = await _pumpPage(t, repo);

      await t.tap(find.byTooltip('시즌 목록'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons');
    });
  });

  group('SeasonDetailPage - 탭 이동', () {
    testWidgets('SeasonDetail_TabQuery_SelectsResults', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=results');

      expect(_selectedTab(t), 1);
      // 헤더: 이름 열 + 라운드 + 점수.
      expect(find.text('R1'), findsOneWidget);
      expect(find.text('R2'), findsOneWidget);
      expect(find.text('Pts'), findsOneWidget);
      // 이름 열: 내 행 포함 드라이버 3명.
      expect(find.text('NORRIS'), findsOneWidget);
      expect(find.text('ME'), findsOneWidget);
      expect(find.text('ALONSO'), findsOneWidget);
      // Season 탭 내용은 없다.
      expect(find.text('GRAND PRIX'), findsNothing);

      // 칸: 순위 · DNF · 기록 없음(-).
      expect(find.descendant(of: _cell('driver:4', 1), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: _cell('driver:4', 2), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: _cell('player', 1), matching: find.text('4')), findsOneWidget);
      expect(find.descendant(of: _cell('player', 2), matching: find.text('DNF')), findsOneWidget);
      expect(find.descendant(of: _cell('driver:14', 1), matching: find.text('-')), findsOneWidget); // 본 레이스 기록 없음
      expect(find.descendant(of: _cell('driver:14', 2), matching: find.text('-')), findsOneWidget); // 칸 자체가 없음
    });

    testWidgets('SeasonDetail_Results_CellColors_PodiumAndMuted', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=results');

      expect(_textColor(t, _cellText('driver:4', 1)), AppColors.podiumGold); // 1위
      expect(_textColor(t, _cellText('driver:4', 2)), AppColors.podiumSilver); // 2위
      expect(_textColor(t, _cellText('player', 1)), isNot(AppColors.podiumBronze)); // 4위는 일반 글자
      expect(_textColor(t, _cellText('player', 1)), isNot(AppColors.textMuted));
      expect(_textColor(t, _cellText('player', 2)), AppColors.textMuted); // DNF
      expect(_textColor(t, _cellText('driver:14', 1)), AppColors.textMuted); // 기록 없음
    });

    testWidgets('SeasonDetail_Results_ThirdPlace_UsesBronze', (t) async {
      final detail = seasonDetailOf(
        'se1',
        rounds: [seasonRoundOf(1)],
        drivers: [
          driverStandingOf(1, driverKey: 'driver:1', cells: [
            standingCellOf(1, position: 3, resultStatus: 'Finished', points: 15),
          ]),
        ],
      );
      await _pumpPage(t, FakeSeasonsRepository(details: {'se1': detail}), initialLocation: '/seasons/se1?tab=results');

      expect(_textColor(t, _cellText('driver:1', 1)), AppColors.podiumBronze);
    });

    testWidgets('SeasonDetail_Results_HighlightsOnlyMyRow_AndShowsPointsLast', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=results');

      expect(_rowColor(t, 'results-name-player'), AppColors.playerRow);
      expect(_rowColor(t, 'results-row-player'), AppColors.playerRow);
      expect(_rowColor(t, 'results-name-driver:4'), isNull);
      expect(_rowColor(t, 'results-row-driver:4'), isNull);
      expect(_rowColor(t, 'results-name-driver:14'), isNull);

      // 마지막 열 = 점수.
      final ptsDx = t.getTopLeft(find.text('Pts')).dx;
      expect(ptsDx, greaterThan(t.getTopLeft(find.text('R2')).dx));
      expect(find.descendant(of: find.byKey(const ValueKey('results-row-driver:4')), matching: find.text('43')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('results-row-player')), matching: find.text('12')), findsOneWidget);
    });

    testWidgets('SeasonDetail_Results_TeamColorBar_UsesApiHexOrMutedFallback', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=results');

      expect(teamBarColor(t, const ValueKey('results-team-bar-driver:4')), const Color(0xFFFF8000));
      expect(teamBarColor(t, const ValueKey('results-team-bar-player')), AppColors.textMuted);
    });

    testWidgets('SeasonDetail_Results_NameColumnStaysFixed_NoOverflowWhenNarrow', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _manyRoundsDetail(24)});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=results', size: const Size(400, 1200));

      expect(t.takeException(), isNull);
      final nameCell = find.byKey(const ValueKey('results-name-driver:2'));
      final nameCellDxBefore = t.getTopLeft(nameCell).dx;
      final nameDxBefore = t.getTopLeft(find.text('DRIVER 2')).dx;
      final lastHeaderDxBefore = t.getTopLeft(find.text('R24')).dx;
      final viewWidth = t.view.physicalSize.width;
      expect(t.getSize(find.byKey(const ValueKey('results-name-header'))).width, kResultsNameColumnWidth);
      expect(lastHeaderDxBefore, greaterThan(viewWidth)); // 마지막 라운드는 화면 밖(스크롤해야 보인다)

      // 이름 열(180px) 오른쪽의 보이는 본문 위에서 왼쪽으로 끈다.
      final headerTop = t.getTopLeft(find.byKey(const ValueKey('results-header-row'))).dy;
      await t.dragFrom(Offset(viewWidth - 40, headerTop + kResultsRowHeight / 2), const Offset(-300, 0));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(t.getTopLeft(find.text('R24')).dx, lessThan(lastHeaderDxBefore - 100)); // 본문은 움직였다
      expect(t.getTopLeft(find.text('DRIVER 2')).dx, nameDxBefore); // 이름은 그대로
      expect(t.getTopLeft(nameCell).dx, nameCellDxBefore);
      expect(find.text('DRIVER 2').hitTestable(), findsOneWidget); // 여전히 화면에 보인다
    });

    testWidgets('SeasonDetail_Results_NameAndBodyRowsAlign', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=results');

      void expectAligned(String nameKey, String rowKey) {
        final name = find.byKey(ValueKey(nameKey));
        final row = find.byKey(ValueKey(rowKey));
        expect(t.getSize(name).height, kResultsRowHeight, reason: nameKey);
        expect(t.getSize(row).height, kResultsRowHeight, reason: rowKey);
        expect(t.getTopLeft(name).dy, t.getTopLeft(row).dy, reason: '$nameKey / $rowKey');
      }

      expectAligned('results-name-header', 'results-header-row');
      for (final key in ['driver:4', 'player', 'driver:14']) {
        expectAligned('results-name-$key', 'results-row-$key');
      }
    });

    testWidgets('SeasonDetail_StandingsTab_ShowsDriversConstructorsAndNote', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=standings');

      expect(_selectedTab(t), 2);
      expect(find.text('Drivers'), findsOneWidget);
      expect(find.text('Constructors'), findsOneWidget);
      // Drivers: Pos · Driver · Team · Wins · Podiums · Pts, Constructors: Pos · Team · Wins · Pts.
      expect(find.text('Pos'), findsNWidgets(2));
      expect(find.text('Driver'), findsOneWidget);
      expect(find.text('Team'), findsNWidgets(2));
      expect(find.text('Wins'), findsNWidgets(2));
      expect(find.text('Podiums'), findsOneWidget);
      expect(find.text('Pts'), findsNWidgets(2));

      expect(find.text('NORRIS'), findsOneWidget);
      expect(find.text('ALONSO'), findsOneWidget);
      expect(find.text('Aston Martin'), findsOneWidget);
      expect(find.text('43'), findsOneWidget);
      expect(find.text('AI'), findsNWidgets(2)); // 내 차는 AI 배지가 없다
      expect(find.text('McLaren'), findsNWidgets(2)); // 드라이버 표(NORRIS)와 팀 표
      expect(find.text('55'), findsOneWidget);
      expect(find.text(_standingsNote), findsOneWidget);
      expect(find.text('GRAND PRIX'), findsNothing);
    });

    testWidgets('SeasonDetail_Standings_TeamColorBarsAndMyRowHighlight', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=standings');

      expect(teamBarColor(t, const ValueKey('standings-team-bar-driver:4')), const Color(0xFFFF8000));
      expect(teamBarColor(t, const ValueKey('standings-team-bar-player')), AppColors.textMuted);
      expect(teamBarColor(t, const ValueKey('constructor-team-bar-8')), const Color(0xFFFF8000));
      expect(teamBarColor(t, const ValueKey('constructor-team-bar-1')), const Color(0xFFE8002D));

      final rows = t.widgetList<DataTable>(find.byType(DataTable)).first.rows;
      expect([for (final r in rows) r.color?.resolve({}) != null], [false, true, false]);
    });

    testWidgets('SeasonDetail_Standings_Narrow_ScrollsWithoutOverflow', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=standings', size: const Size(320, 2400));

      expect(t.takeException(), isNull);
      expect(find.text(_standingsNote), findsOneWidget);
    });

    testWidgets('SeasonDetail_Season_Narrow_DoesNotOverflow', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, size: const Size(320, 2400));

      expect(t.takeException(), isNull);
      expect(find.text('GRAND PRIX'), findsOneWidget);
    });

    testWidgets('SeasonDetail_UnknownTab_FallsBackToSeason', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo, initialLocation: '/seasons/se1?tab=weird');

      expect(_selectedTab(t), 0);
      expect(find.text('GRAND PRIX'), findsOneWidget);
      expect(find.text('Pts'), findsNothing);
    });

    testWidgets('SeasonDetail_TapTab_ChangesQueryWithoutPushingHistory', (t) async {
      final updates = <Map<Object?, Object?>>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
        if (call.method == 'routeInformationUpdated') {
          updates.add(call.arguments as Map<Object?, Object?>);
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, null));

      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      final router = await _pumpPage(t, repo);

      await t.tap(find.text('Results'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/se1?tab=results');
      expect(_selectedTab(t), 1);
      expect(find.text('Pts'), findsOneWidget);
      expect(updates.last['replace'], isTrue); // Router.neglect: 브라우저 기록에 항목을 쌓지 않는다.

      await t.tap(find.text('Standings'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/se1?tab=standings');
      expect(_selectedTab(t), 2);
      expect(find.text(_standingsNote), findsOneWidget);
      expect(updates.last['replace'], isTrue);

      await t.tap(find.text('Season'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/se1?tab=season');
      expect(_selectedTab(t), 0);
      expect(find.text('GRAND PRIX'), findsOneWidget);
      expect(repo.detailRequests, ['se1']); // 탭을 바꿔도 다시 불러오지 않는다.

      // 대조: neglect 없이 이동하면 기록에 새 항목이 쌓인다(위 검증이 의미 있는 이유).
      router.go('/seasons/se1?tab=results');
      await t.pumpAndSettle();

      expect(updates.last['replace'], isFalse);
    });

    testWidgets('SeasonDetail_RouterChangesTab_UpdatesTabBarSelection', (t) async {
      final repo = FakeSeasonsRepository(details: {'se1': _detail()});
      final router = await _pumpPage(t, repo);

      router.go('/seasons/se1?tab=standings');
      await t.pumpAndSettle();

      expect(_selectedTab(t), 2);
      expect(find.text(_standingsNote), findsOneWidget);
    });
  });

  group('SeasonDetailPage - 상태', () {
    testWidgets('SeasonDetail_NotFound_ShowsNotFoundState', (t) async {
      final router = await _pumpPage(t, FakeSeasonsRepository(), initialLocation: '/seasons/missing');

      expect(find.text('찾을 수 없는 시즌입니다.'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);
      expect(find.byType(TabBar), findsNothing);

      await t.tap(find.text('Seasons'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons');
      expect(find.text('seasons-list'), findsOneWidget);
    });

    testWidgets('SeasonDetail_LoadFails_RetryReloads', (t) async {
      final repo = _FlakySeasonsRepository(details: {'se1': _detail()});
      await _pumpPage(t, repo);

      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('찾을 수 없는 시즌입니다.'), findsNothing);

      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();

      expect(find.text('GRAND PRIX'), findsOneWidget);
    });

    testWidgets('SeasonDetail_ServerError_ShowsMessageAndRetry', (t) async {
      await _pumpPage(t, _ServerErrorRepository());

      expect(find.text('서버가 아파요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('찾을 수 없는 시즌입니다.'), findsNothing);
    });
  });
}
