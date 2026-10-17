import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';
import 'package:simcenter_app/features/sessions/presentation/session_detail_page.dart';
import 'package:simcenter_app/features/sessions/presentation/session_results_table.dart';
import 'package:simcenter_app/features/sessions/presentation/tyre_stints_view.dart';

import 'support/fakes.dart';

const _allHeaders = ['Pos', 'Driver', 'Team', 'Grid', 'Laps', 'Time/Gap', 'Best', 'Tyres', 'Pits', 'Pen', 'Pts'];
const _compactHiddenHeaders = ['Grid', 'Tyres', 'Pits', 'Pen'];

/// 첫 호출만 실패하고 이후엔 정상 응답하는 저장소(다시 시도 검증용).
class _FlakySessionsRepository extends FakeSessionsRepository {
  _FlakySessionsRepository({super.details});

  int failuresLeft = 1;

  @override
  Future<SessionDetail> getMySession(String sessionId) async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMySession(sessionId);
  }
}

/// 항상 500으로 실패하는 저장소.
class _ServerErrorRepository extends FakeSessionsRepository {
  @override
  Future<SessionDetail> getMySession(String sessionId) async =>
      throw ApiException('서버가 아파요.', statusCode: 500);
}

List<SessionResult> _raceResults() => [
      resultOf(
        1,
        name: 'NORRIS',
        isFastestLap: true,
        bestLapTimeMs: 104987,
        totalRaceTimeMs: 1598765,
        points: 25,
      ),
      resultOf(
        2,
        name: 'ME',
        isPlayer: true,
        isAiControlled: false,
        bestLapTimeMs: 105321,
        totalRaceTimeMs: 1610000,
        penaltiesTimeMs: 5000,
        numPenalties: 1,
        points: 18,
        tyreStints: const [
          TyreStintView(endLap: 7, visualCompound: 'Medium', actualCompound: 'C3'),
          TyreStintView(endLap: 15, visualCompound: 'Hard', actualCompound: 'C2'),
        ],
      ),
      resultOf(3, name: 'PIASTRI', numLaps: 14, bestLapTimeMs: 106000, totalRaceTimeMs: 1500000, points: 15),
      resultOf(4, name: 'ALONSO', resultStatus: 'DidNotFinish', numLaps: 3),
    ];

Future<GoRouter> _pumpPage(
  WidgetTester tester,
  SessionsRepository repo, {
  String sessionId = 'd1',
  String? initialLocation,
  Size size = const Size(1000, 2400),
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: initialLocation ?? '/sessions/$sessionId', routes: [
    GoRoute(path: '/sessions', builder: (_, _) => const Text('sessions-list')),
    GoRoute(
      path: '/seasons/:seasonId',
      builder: (_, state) => Text('season:${state.pathParameters['seasonId']}:${state.uri.queryParameters['tab']}'),
    ),
    GoRoute(
      path: '/sessions/:sessionId',
      builder: (_, state) => Scaffold(body: SessionDetailPage(sessionId: state.pathParameters['sessionId']!)),
    ),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [sessionsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

/// 표만 [width] 폭 안에 올린다(콘텐츠 폭 판정 검증용).
Future<void> _pumpTable(
  WidgetTester tester,
  List<SessionResult> results, {
  required double width,
  bool isRace = true,
}) async {
  setViewSize(tester, const Size(1400, 1600));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: SessionResultsTable(results: results, isRace: isRace)),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

double _top(WidgetTester t, String text) => t.getTopLeft(find.text(text)).dy;

/// 결과 표(DataTable)의 데이터 행들.
List<DataRow> _dataRows(WidgetTester t) => t.widget<DataTable>(find.byType(DataTable)).rows;

Color? _textColor(WidgetTester t, String text) => t.widget<Text>(find.text(text)).style?.color;

void main() {
  group('SessionDetailPage', () {
    testWidgets('SessionDetail_ShowsResultsInOrder_WithAiBadgeAndMyRowHighlight', (t) async {
      final repo = FakeSessionsRepository(details: {'d1': detailOf('d1', results: _raceResults())});
      await _pumpPage(t, repo);

      expect(repo.detailRequests, ['d1']);
      expect(_top(t, 'NORRIS'), lessThan(_top(t, 'ME')));
      expect(_top(t, 'ME'), lessThan(_top(t, 'PIASTRI')));
      expect(_top(t, 'PIASTRI'), lessThan(_top(t, 'ALONSO')));

      // AI 배지는 AI 차에만(내 차 제외).
      expect(find.text('AI'), findsNWidgets(3));

      // 내 행만 강조된다.
      final rows = _dataRows(t);
      expect(rows, hasLength(4));
      expect([for (final r in rows) r.color?.resolve({}) != null], [false, true, false, false]);
    });

    testWidgets('SessionDetail_Header_ShowsTrackLabelModeDateAiAndRound', (t) async {
      final repo = FakeSessionsRepository(details: {
        'd1': detailOf(
          'd1',
          results: _raceResults(),
          trackName: 'Spa',
          sessionKind: 'Qualifying3',
          sessionType: 'Qualifying',
          gameMode: 'MyTeamCareer',
          seasonId: 'season-1',
          round: 7,
          aiDifficulty: 85,
        ),
      });
      await _pumpPage(t, repo);

      expect(find.text('Spa'), findsOneWidget);
      expect(find.text('Q3'), findsOneWidget);
      expect(find.text('My Team'), findsOneWidget);
      expect(find.text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.utc(2026, 10, 12, 9).toLocal())), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(find.text('R7'), findsOneWidget);
    });

    testWidgets('SessionDetail_SeasonRound_LinksToSeasonTab', (t) async {
      final repo = FakeSessionsRepository(details: {
        'd1': detailOf('d1', results: _raceResults(), seasonId: 'season-1', round: 7),
      });
      final router = await _pumpPage(t, repo);

      expect(find.ancestor(of: find.text('R7'), matching: find.byType(InkWell)), findsOneWidget);

      await t.tap(find.text('R7'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/season-1?tab=season');
      expect(find.text('season:season-1:season'), findsOneWidget);
    });

    testWidgets('SessionDetail_NoSeasonNoAi_OmitsRoundAndAiDifficulty', (t) async {
      final repo = FakeSessionsRepository(details: {
        'd1': detailOf('d1', results: _raceResults(), seasonId: null, round: null, aiDifficulty: 0),
      });
      await _pumpPage(t, repo);

      expect(find.textContaining('AI 난이도'), findsNothing);
      expect(find.text('시즌'), findsNothing);
      expect(find.textContaining(RegExp(r'^R\d+$')), findsNothing);
    });

    testWidgets('SessionDetail_Race_ShowsTimeGapLapsDownStatusPenAndPoints', (t) async {
      final repo = FakeSessionsRepository(details: {'d1': detailOf('d1', results: _raceResults())});
      await _pumpPage(t, repo);

      expect(find.text('26:38.765'), findsOneWidget); // 기준 행: 총 시간(패널티 0)
      expect(find.text('+16.235'), findsOneWidget); // (1610000 + 5000) - 1598765
      expect(find.text('+1 Lap'), findsOneWidget);
      expect(find.text('DNF'), findsOneWidget);
      expect(find.text('+5s (1)'), findsOneWidget);
      for (final points in ['25', '18', '15']) {
        expect(find.text(points), findsWidgets, reason: points);
      }
    });

    testWidgets('SessionDetail_Qualifying_ShowsBestLapAndGapToFastest', (t) async {
      final repo = FakeSessionsRepository(details: {
        'd1': detailOf('d1', sessionType: 'Qualifying', sessionKind: 'Qualifying1', results: [
          resultOf(1, name: 'A', bestLapTimeMs: 81500),
          resultOf(2, name: 'B', bestLapTimeMs: 81234, isFastestLap: true),
          resultOf(3, name: 'C', resultStatus: 'Retired'),
        ]),
      });
      await _pumpPage(t, repo);

      // 시간 열: 가장 빠른 행(B)은 베스트 랩, A는 차이, C는 상태.
      expect(find.text('+0.266'), findsOneWidget);
      expect(find.text('RET'), findsOneWidget);
      // 베스트 열과 시간 열 모두에 1:21.234가 보인다.
      expect(find.text('1:21.234'), findsNWidgets(2));
    });

    testWidgets('SessionDetail_FastestLap_UsesFastestColor', (t) async {
      final repo = FakeSessionsRepository(details: {'d1': detailOf('d1', results: _raceResults())});
      await _pumpPage(t, repo);

      expect(_textColor(t, '1:44.987'), AppColors.fastestLap);
      expect(_textColor(t, '1:45.321'), isNot(AppColors.fastestLap));
    });

    testWidgets('SessionDetail_TeamColor_UsesApiHexOrMutedFallback', (t) async {
      final repo = FakeSessionsRepository(details: {
        'd1': detailOf('d1', results: [
          resultOf(1, teamColor: '#FF8000'),
          resultOf(2, teamColor: 'not-a-color'),
        ]),
      });
      await _pumpPage(t, repo);

      expect(teamBarColor(t, const ValueKey('team-color-bar-0')), const Color(0xFFFF8000));
      expect(teamBarColor(t, const ValueKey('team-color-bar-1')), AppColors.textMuted);
    });

    testWidgets('SessionDetail_NotFound_ShowsNotFoundState', (t) async {
      final router = await _pumpPage(t, FakeSessionsRepository(), sessionId: 'missing');

      expect(find.text('찾을 수 없는 세션입니다.'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);

      await t.tap(find.text('Sessions'));
      await t.pumpAndSettle();

      expect(_location(router), '/sessions');
      expect(find.text('sessions-list'), findsOneWidget);
    });

    testWidgets('SessionDetail_LoadFails_RetryReloads', (t) async {
      final repo = _FlakySessionsRepository(details: {'d1': detailOf('d1', results: _raceResults())});
      await _pumpPage(t, repo);

      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('찾을 수 없는 세션입니다.'), findsNothing);

      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();

      expect(find.text('NORRIS'), findsOneWidget);
    });

    testWidgets('SessionDetail_ServerError_ShowsMessageAndRetry', (t) async {
      await _pumpPage(t, _ServerErrorRepository());

      expect(find.text('서버가 아파요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('찾을 수 없는 세션입니다.'), findsNothing);
    });

    testWidgets('SessionDetail_Back_WithoutOpener_GoesToSessionList', (t) async {
      final repo = FakeSessionsRepository(details: {'d1': detailOf('d1', results: _raceResults())});
      final router = await _pumpPage(t, repo);

      await t.tap(find.byTooltip('세션 목록'));
      await t.pumpAndSettle();

      expect(_location(router), '/sessions');
    });

    testWidgets('SessionDetail_Back_WhenOpenedFromSeason_ReturnsToOpener', (t) async {
      final repo = FakeSessionsRepository(details: {'d1': detailOf('d1', results: _raceResults())});
      final router = await _pumpPage(t, repo, initialLocation: '/seasons/season-1?tab=results');

      // 시즌 화면의 세션 칩이 하는 것처럼 세션을 위에 쌓는다.
      unawaited(router.push('/sessions/d1'));
      await t.pumpAndSettle();
      expect(find.text('NORRIS'), findsOneWidget);

      await t.tap(find.byTooltip('세션 목록'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/season-1?tab=results');
      expect(find.text('season:season-1:results'), findsOneWidget);
      expect(find.text('sessions-list'), findsNothing);
    });

    testWidgets('SessionDetail_Narrow_HidesGridTyresPitsPen', (t) async {
      final repo = FakeSessionsRepository(details: {'d1': detailOf('d1', results: _raceResults())});
      await _pumpPage(t, repo, size: const Size(500, 2400));

      expect(t.takeException(), isNull);
      for (final header in _compactHiddenHeaders) {
        expect(find.text(header), findsNothing, reason: header);
      }
      expect(find.text('NORRIS'), findsOneWidget);
    });

    testWidgets('SessionDetail_Full24CarGrid_DoesNotOverflowWide', (t) async {
      final repo = FakeSessionsRepository(details: {
        'd1': detailOf('d1', results: [
          for (var i = 1; i <= 24; i++)
            resultOf(
              i,
              name: 'A VERY LONG DRIVER NAME NUMBER $i',
              teamName: 'A Rather Long Team Name',
              totalRaceTimeMs: 1600000 + i * 1000,
              bestLapTimeMs: 105000 + i,
              tyreStints: const [
                TyreStintView(endLap: 5, visualCompound: 'Soft', actualCompound: 'C5'),
                TyreStintView(endLap: 10, visualCompound: 'Medium', actualCompound: 'C4'),
                TyreStintView(endLap: 15, visualCompound: 'Hard', actualCompound: 'C3'),
              ],
            ),
        ]),
      });
      await _pumpPage(t, repo, size: const Size(1100, 3000));

      expect(t.takeException(), isNull);
    });
  });

  group('SessionResultsTable', () {
    testWidgets('SessionResultsTable_Wide_ShowsEveryColumn', (t) async {
      await _pumpTable(t, _raceResults(), width: 900);

      expect(t.takeException(), isNull);
      for (final header in _allHeaders) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
    });

    testWidgets('SessionResultsTable_Narrow_HidesGridTyresPitsPenAndStillScrolls', (t) async {
      await _pumpTable(t, _raceResults(), width: 500);

      expect(t.takeException(), isNull);
      for (final header in _allHeaders.where((h) => !_compactHiddenHeaders.contains(h))) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      for (final header in _compactHiddenHeaders) {
        expect(find.text(header), findsNothing, reason: header);
      }
    });

    testWidgets('SessionResultsTable_VeryNarrow_ScrollsHorizontallyWithoutOverflow', (t) async {
      await _pumpTable(t, _raceResults(), width: 280);

      expect(t.takeException(), isNull);
      expect(find.text('NORRIS'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SessionResultsTable),
          matching: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SessionResultsTable_Boundary_599IsCompactAnd600IsFull', (t) async {
      await _pumpTable(t, _raceResults(), width: 599);
      expect(find.text('Grid'), findsNothing);

      await _pumpTable(t, _raceResults(), width: 600);
      expect(find.text('Grid'), findsOneWidget);
    });

    testWidgets('SessionResultsTable_Empty_ShowsHeadersOnly', (t) async {
      await _pumpTable(t, const [], width: 900);

      expect(t.takeException(), isNull);
      expect(find.text('Pos'), findsOneWidget);
      expect(_dataRows(t), isEmpty);
    });
  });

  group('TyreStintsView', () {
    Future<void> pumpStints(WidgetTester t, List<TyreStintView> stints) => t.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: TyreStintsView(stints: stints)))),
        );

    testWidgets('TyreStintsView_ShowsOneCircleWithTooltipPerStint', (t) async {
      await pumpStints(t, const [
        TyreStintView(endLap: 7, visualCompound: 'Medium', actualCompound: 'C3'),
        TyreStintView(endLap: 15, visualCompound: 'Soft', actualCompound: null),
      ]);

      expect(find.byTooltip('Medium (C3) · ~L7'), findsOneWidget);
      expect(find.byTooltip('Soft · ~L15'), findsOneWidget);
    });

    testWidgets('TyreStintsView_Empty_ShowsDash', (t) async {
      await pumpStints(t, const []);

      expect(find.text('-'), findsOneWidget);
    });

    test('tyreColorOf maps each compound to its token and unknown to muted', () {
      expect(tyreColorOf('Soft'), AppColors.tyreSoft);
      expect(tyreColorOf('Medium'), AppColors.tyreMedium);
      expect(tyreColorOf('Hard'), AppColors.tyreHard);
      expect(tyreColorOf('Intermediate'), AppColors.tyreIntermediate);
      expect(tyreColorOf('Wet'), AppColors.tyreWet);
      expect(tyreColorOf('Unknown'), AppColors.textMuted);
      expect(tyreColorOf('Weird'), AppColors.textMuted);
    });
  });
}
