import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';
import 'package:simcenter_app/features/sessions/presentation/engine_painter.dart';
import 'package:simcenter_app/features/sessions/presentation/session_detail_page.dart';
import 'package:simcenter_app/features/sessions/presentation/stint_line_chart.dart';
import 'package:simcenter_app/features/sessions/presentation/tyre_stints_view.dart';

import 'support/fakes.dart';

const _ferrari = LapTeam(name: 'Ferrari', color: '#E8002D');

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
      resultOf(1, name: 'NORRIS', raceNumber: 4, gridPosition: 2, bestLapTimeMs: 104987, totalRaceTimeMs: 1598765, points: 25),
      resultOf(
        2,
        name: 'ME',
        isPlayer: true,
        isAiControlled: false,
        raceNumber: 16,
        teamName: 'Ferrari',
        teamColor: '#E8002D',
        totalRaceTimeMs: 1601074,
        gapMs: 2309,
        positionChange: -1,
        points: 18,
      ),
      resultOf(3, name: 'PIASTRI', numLaps: 14, positionChange: 9, points: 15),
      resultOf(4, name: 'ALONSO', resultStatus: 'DidNotFinish', numLaps: 3),
    ];

/// 계약(docs/15 §11.4)의 모든 카드 데이터가 있는 레이스.
SessionDetail _fullDetail({String sessionType = 'Race', String sessionKind = 'Race'}) => detailOf(
      'd1',
      results: _raceResults(),
      trackName: 'Jeddah',
      sessionType: sessionType,
      sessionKind: sessionKind,
      countryCode: 'SA',
      myTeam: _ferrari,
      seasonNumber: 1,
      seasonId: 'season-1',
      round: 3,
      aiDifficulty: 105,
      weather: 'Clear',
      myBestLap: const SessionBestLap(lapId: 'lap-9', lapTimeMs: 90088),
      setup: const {'frontWing': 10, 'rearWing': 8, 'tyrePressureFL': 22.5, 'mystery': 3},
      laps: const [
        SessionLap(
          lapNumber: 1,
          position: 11,
          positionChange: 1,
          visualCompound: 'Medium',
          lapTimeMs: 95000,
          gapToBestMs: 4912,
          sectorsMs: [30000, 32000, 33000],
          lapId: 'lap-1',
        ),
        SessionLap(
          lapNumber: 2,
          position: 10,
          positionChange: 1,
          visualCompound: 'Medium',
          lapTimeMs: 90088,
          gapToBestMs: 0,
          sectorsMs: [29000, 30500, 30588],
          isBestLap: true,
          bestSectors: [true, false, false],
          lapId: 'lap-9',
        ),
        SessionLap(
          lapNumber: 3,
          position: 18,
          positionChange: -8,
          visualCompound: 'Soft',
          inPit: true,
          lapTimeMs: 110123,
          gapToBestMs: 20035,
          isValid: false,
        ),
      ],
      engineWear: const EngineWear(
        ice: 12,
        turboCharger: 8,
        mguH: 15,
        mguK: 6,
        energyStore: 4,
        controlElectronics: 3,
        gearbox: 52,
        engineDamage: 0,
      ),
      tyreStints: const [
        SessionTyreStint(visualCompound: 'Medium', startLap: 1, endLap: 2, laps: [
          StintLap(lapInStint: 1, lapTimeMs: 95000, tyreLifeRemaining: 97),
          StintLap(lapInStint: 2, lapTimeMs: 90088, tyreLifeRemaining: 93),
        ]),
        SessionTyreStint(visualCompound: 'Soft', startLap: 3, endLap: 3, laps: [
          StintLap(lapInStint: 1, lapTimeMs: 110123, tyreLifeRemaining: 99),
        ]),
      ],
      penalties: const [
        SessionPenalty(
          lap: 2,
          carIndex: 1,
          driverName: 'ME',
          isPlayer: true,
          teamColor: '#E8002D',
          infringement: 'Small Collision',
          penalty: 'Warning',
        ),
        SessionPenalty(lap: 3, carIndex: 0, driverName: 'NORRIS', infringement: 'Corner Cutting', penalty: 'Time Penalty', timeS: 5),
      ],
    );

Future<GoRouter> _pumpPage(
  WidgetTester tester,
  SessionsRepository repo, {
  String sessionId = 'd1',
  String? initialLocation,
  Size size = const Size(1200, 4000),
  ThemeData? theme,
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: initialLocation ?? '/sessions/$sessionId', routes: [
    GoRoute(path: '/sessions', builder: (_, _) => const Text('sessions-list')),
    GoRoute(path: '/laps/:lapId', builder: (_, state) => Text('lap:${state.pathParameters['lapId']}')),
    GoRoute(path: '/sessions/:sessionId/setup', builder: (_, state) => Text('setup:${state.pathParameters['sessionId']}')),
    GoRoute(
      path: '/seasons/:seasonId',
      builder: (_, state) => Text('season:${state.pathParameters['seasonId']}:${state.uri.queryParameters['tab']}'),
    ),
    GoRoute(
      path: '/sessions/:sessionId',
      builder: (_, state) => Scaffold(
        body: SessionDetailPage(
          sessionId: state.pathParameters['sessionId']!,
          from: state.uri.queryParameters['from'],
        ),
      ),
    ),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [sessionsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(theme: theme, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

FakeSessionsRepository _repo(SessionDetail detail) => FakeSessionsRepository(details: {'d1': detail});

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

Offset _topLeft(WidgetTester t, String text) => t.getTopLeft(find.text(text).first);

Color? _textColor(WidgetTester t, String text) => t.widget<Text>(find.text(text)).style?.color;

Finder _rowOf(String key) => find.byKey(ValueKey(key));

void main() {
  group('SessionDetailPage 헤더·레이아웃', () {
    testWidgets('헤더: 국기 + 트랙 + 세션 종류 이름', (t) async {
      await _pumpPage(t, _repo(_fullDetail(sessionType: 'Qualifying', sessionKind: 'Qualifying3')));

      expect(find.byKey(const ValueKey('track-flag-SA')), findsOneWidget);
      expect(find.text('Jeddah'), findsOneWidget);
      expect(find.text('Qualifying 3'), findsNWidgets(2)); // 헤더 + Details Session Type
    });

    testWidgets('일곱 카드 제목이 모두 보인다', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      for (final title in [
        'Details',
        'Final Classification',
        'Laps',
        'Engine Wear',
        'Tyre Stints: Tyre Life Remaining',
        'Tyre Stints: Lap Times',
        'Penalties',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('900px 이상은 2열(Details 옆 Final Classification), 미만은 1열', (t) async {
      await _pumpPage(t, _repo(_fullDetail()), size: const Size(1200, 4000));
      expect(_topLeft(t, 'Final Classification').dy, _topLeft(t, 'Details').dy);
      expect(_topLeft(t, 'Final Classification').dx, greaterThan(_topLeft(t, 'Details').dx));

      await _pumpPage(t, _repo(_fullDetail()), size: const Size(800, 6000));
      expect(_topLeft(t, 'Final Classification').dy, greaterThan(_topLeft(t, 'Details').dy));
      expect(_topLeft(t, 'Laps').dy, greaterThan(_topLeft(t, 'Final Classification').dy));
    });

    for (final light in [false, true]) {
      testWidgets('375px에서 넘치지 않는다(${light ? 'light' : 'dark'}, 전체 데이터·빈 데이터)', (t) async {
        // AppTheme은 글꼴을 불러오므로 테스트 안에서 만든다.
        final theme = light ? AppTheme.light : AppTheme.dark;
        await _pumpPage(t, _repo(_fullDetail()), size: const Size(375, 8000), theme: theme);
        expect(t.takeException(), isNull);

        await _pumpPage(t, _repo(detailOf('d1')), size: const Size(375, 4000), theme: theme);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('Details 카드', () {
    testWidgets('값: 난이도·날씨·팀·세션 종류·모드+시즌·날짜·라운드', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      expect(find.text('105'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.descendant(of: _rowOf('detail-row-Team'), matching: find.text('Ferrari')), findsOneWidget);
      expect(find.descendant(of: _rowOf('detail-row-Session Type'), matching: find.text('Race')), findsOneWidget);
      expect(find.text('Driver Career Season 1'), findsOneWidget);
      expect(find.text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.utc(2026, 10, 12, 9).toLocal())), findsOneWidget);
      expect(find.text('R3'), findsOneWidget);
    });

    testWidgets('Best Lap Time을 누르면 그 랩 상세로 간다', (t) async {
      final router = await _pumpPage(t, _repo(_fullDetail()));

      await t.tap(find.descendant(of: _rowOf('detail-row-Best Lap Time'), matching: find.text('1:30.088')));
      await t.pumpAndSettle();

      expect(_location(router), '/laps/lap-9');
    });

    testWidgets('View Setup을 누르면 그 세션의 셋업 화면으로 간다(대화상자 아님)', (t) async {
      final router = await _pumpPage(t, _repo(_fullDetail()));

      await t.tap(find.text('View Setup'));
      await t.pumpAndSettle();

      expect(_location(router), '/sessions/d1/setup');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('setup:d1'), findsOneWidget);
    });

    testWidgets('예선이면 같은 주말 Q1·Q2·Q3 내 순위', (t) async {
      final detail = detailOf(
        'd1',
        sessionType: 'Qualifying',
        sessionKind: 'Qualifying3',
        qualifyingPositions: const [
          QualifyingPosition(label: 'Q1', position: 6, sessionId: 'q1'),
          QualifyingPosition(label: 'Q2', position: 10),
          QualifyingPosition(label: 'Q3', position: 8),
        ],
      );
      final router = await _pumpPage(t, _repo(detail));

      expect(find.text('P6'), findsOneWidget);
      expect(find.text('P10'), findsOneWidget);
      expect(find.text('P8'), findsOneWidget);

      await t.tap(find.text('P6'));
      await t.pumpAndSettle();
      expect(_location(router), '/sessions/q1');
    });

    testWidgets('옛 서버: 값이 없으면 -, 셋업 링크 없음, 최고 랩은 헤더 값', (t) async {
      await _pumpPage(t, _repo(detailOf('d1', aiDifficulty: 0, myBestLapTimeMs: 91234)));

      expect(find.text('View Setup'), findsNothing);
      expect(find.text('1:31.234'), findsOneWidget);
      for (final label in ['Setup', 'Difficulty', 'Conditions', 'Team']) {
        expect(find.descendant(of: _rowOf('detail-row-$label'), matching: find.text('-')), findsOneWidget, reason: label);
      }
      expect(find.text('Driver Career'), findsOneWidget);
    });

    testWidgets('시즌 라운드 R3는 그 시즌으로 가는 링크', (t) async {
      final router = await _pumpPage(t, _repo(_fullDetail()));

      await t.tap(find.text('R3'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/season-1?tab=season');
    });
  });

  group('Final Classification 카드', () {
    testWidgets('순서·번호·You·내 행 강조·변동·GAP', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      expect(find.text('NORRIS'), findsWidgets);
      expect(find.text('ME'), findsNothing); // 나는 You
      expect(find.text('You'), findsNWidgets(2)); // 순위표 + 패널티
      expect(find.descendant(of: _rowOf('classification-row-0'), matching: find.text('4')), findsWidgets);
      expect(find.descendant(of: _rowOf('classification-row-1'), matching: find.text('+0:02.309')), findsOneWidget);
      expect(find.descendant(of: _rowOf('classification-row-2'), matching: find.text('+1 Lap')), findsOneWidget);
      expect(find.descendant(of: _rowOf('classification-row-3'), matching: find.text('DNF')), findsOneWidget);
      expect(find.text('26:38.765'), findsOneWidget);

      // 변동: 서버 값(ME −1 ↓, PIASTRI +9 ↑), 없으면 그리드 − 순위(NORRIS 2 − 1 = ↑1).
      expect(find.descendant(of: _rowOf('classification-row-1'), matching: find.byIcon(Icons.arrow_downward)), findsOneWidget);
      expect(find.descendant(of: _rowOf('classification-row-2'), matching: find.text('9')), findsOneWidget);
      expect(find.descendant(of: _rowOf('classification-row-0'), matching: find.byIcon(Icons.arrow_upward)), findsOneWidget);

      final highlighted = t.widget<Material>(
        find.descendant(of: _rowOf('classification-row-1'), matching: find.byType(Material)).first,
      );
      expect(highlighted.color, AppColors.playerRow);
    });

    testWidgets('모든 차 표본이 있으면 다른 차(최고 랩이 있는) 행의 비교 버튼으로 내 최고 랩을 그 차와 비교한다', (t) async {
      final detail = detailOf(
        'd1',
        hasFieldSamples: true,
        myBestLap: const SessionBestLap(lapId: 'lap-9', lapTimeMs: 72684),
        results: [
          resultOf(1, carIndex: 4, name: 'POLE', bestLapTimeMs: 71157, teamColor: '#3671C6'),
          resultOf(2, carIndex: 9, name: 'ME', isPlayer: true, bestLapTimeMs: 72684),
          resultOf(3, carIndex: 5, name: 'NOTIME'),
        ],
      );
      final router = await _pumpPage(t, _repo(detail));

      expect(find.byKey(const ValueKey('classification-compare-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('classification-compare-9')), findsNothing); // 나
      expect(find.byKey(const ValueKey('classification-compare-5')), findsNothing); // 최고 랩 없음

      await t.tap(find.byKey(const ValueKey('classification-compare-4')));
      await t.pumpAndSettle();
      final location = Uri.parse(_location(router));
      expect(location.path, '/laps/lap-9');
      expect(location.queryParameters, {
        'tab': 'telemetry',
        'compare': 'car',
        'compareSession': 'd1',
        'compareCar': '4',
        'compareName': 'POLE',
        'compareTimeMs': '71157',
        'compareTeamColor': '#3671C6',
      });
    });

    testWidgets('표본이 없는 세션에는 비교 버튼이 없다', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      expect(find.byIcon(Icons.compare_arrows), findsNothing);
    });

    testWidgets('결과가 없으면 안내 문구', (t) async {
      await _pumpPage(t, _repo(detailOf('d1')));

      expect(find.text('이 세션에는 최종 순위 데이터가 없어요.'), findsOneWidget);
    });
  });

  group('Laps 카드', () {
    testWidgets('순위+변동·타이어·IN PIT·랩타임·GAP·섹터, 최고 랩·섹터는 보라, 무효는 빨강', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      for (final header in ['POS.', 'TYRE', 'LAP TIME', 'SECTOR 1', 'SECTOR 2', 'SECTOR 3']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('IN PIT'), findsNWidgets(2)); // 머리글 + 3랩 꼬리표
      expect(find.text('GAP'), findsNWidgets(2)); // Final Classification + Laps
      expect(find.descendant(of: _rowOf('session-lap-1'), matching: find.text('11')), findsOneWidget);
      expect(find.descendant(of: _rowOf('session-lap-3'), matching: find.text('8')), findsOneWidget);
      expect(find.descendant(of: _rowOf('session-lap-3'), matching: find.text('IN PIT')), findsOneWidget);
      expect(find.descendant(of: _rowOf('session-lap-3'), matching: find.byType(TyreCompoundCircle)), findsOneWidget);
      expect(find.text('+4.912'), findsOneWidget);
      expect(find.text('30.000'), findsOneWidget);
      expect(_textColor(t, '29.000'), AppColors.fastestLap);
      expect(_textColor(t, '30.500'), isNot(AppColors.fastestLap));
      expect(
        t.widget<Text>(find.descendant(of: _rowOf('session-lap-2'), matching: find.text('1:30.088'))).style?.color,
        AppColors.fastestLap,
      );
      expect(_textColor(t, '1:50.123'), AppColors.danger);
    });

    testWidgets('저장된 랩 행을 누르면 랩 상세', (t) async {
      final router = await _pumpPage(t, _repo(_fullDetail()));

      await t.tap(_rowOf('session-lap-1'));
      await t.pumpAndSettle();

      expect(_location(router), '/laps/lap-1');
    });

    testWidgets('좁으면 IN PIT·GAP·섹터를 숨긴다', (t) async {
      await _pumpPage(t, _repo(_fullDetail()), size: const Size(500, 8000));

      expect(t.takeException(), isNull);
      for (final header in ['IN PIT', 'SECTOR 1']) {
        expect(find.text(header), findsNothing, reason: header);
      }
      expect(find.text('GAP'), findsOneWidget); // Final Classification만 남는다
      expect(find.text('LAP TIME'), findsOneWidget);
    });
  });

  group('Engine Wear·Tyre Stints·Penalties 카드', () {
    testWidgets('엔진 그림 + 부품 목록(%), 색은 25/50/75% 단계', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is EnginePainter), findsOneWidget);
      expect(find.descendant(of: _rowOf('engine-wear-ICE'), matching: find.text('12%')), findsOneWidget);
      expect(find.descendant(of: _rowOf('engine-wear-Gearbox'), matching: find.text('52%')), findsOneWidget);
      expect(find.descendant(of: _rowOf('engine-wear-Engine Damage'), matching: find.text('0%')), findsOneWidget);
      final painter = t
          .widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is EnginePainter))
          .painter! as EnginePainter;
      expect(painter.partColors[EnginePart.ice.index], AppColors.wearLow);
      expect(painter.partColors[EnginePart.gearbox.index], AppColors.wearHigh);
    });

    testWidgets('스틴트 그래프 두 장: 스틴트마다 선, 범례', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      final charts = t.widgetList<StintLineChart>(find.byType(StintLineChart)).toList();
      expect(charts, hasLength(2));
      expect(charts.first.series.map((s) => s.color), [AppColors.tyreMedium, AppColors.tyreSoft]);
      expect(charts.first.range.max, 100);
      expect(charts.first.maxX, 2);
      expect(find.text('Stint 1 · Medium (L1–L2)'), findsNWidgets(2));
      expect(find.text('Lap in stint'), findsNWidgets(2));
    });

    testWidgets('Lap Times 그래프에 마우스를 올리면 그 랩의 랩타임 툴팁과 안내선', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      final lapTimes = find.byType(StintLineChart).last;
      final paint = find.descendant(
        of: lapTimes,
        matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is StintChartPainter),
      );
      await t.ensureVisible(paint);
      await t.pumpAndSettle();
      final box = t.getRect(paint);
      // 오른쪽 끝(그림 영역 끝 근처) = 스틴트 안 랩 2.
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(Offset(box.right - 10, box.center.dy));
      await t.pump();

      expect(find.text('Lap 2 · 1:30.088 · Medium'), findsOneWidget);
      final painter = t.widget<CustomPaint>(paint).painter! as StintChartPainter;
      expect(painter.hoverX, 2);

      // 왼쪽 끝 = 랩 1: 두 스틴트가 한 줄씩(Soft 스틴트는 세션 랩 3).
      await mouse.moveTo(Offset(box.left + 70, box.center.dy));
      await t.pump();
      expect(find.text('Lap 1 · 1:35.000 · Medium'), findsOneWidget);
      expect(find.text('Lap 3 · 1:50.123 · Soft'), findsOneWidget);

      await mouse.moveTo(Offset(box.center.dx, box.bottom + 200));
      await t.pump();
      expect(find.byKey(const ValueKey('stint-chart-tooltip')), findsNothing);
    });

    testWidgets('Lap Times 그래프를 누르면(터치) 툴팁이 보인다', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      final paint = find.descendant(
        of: find.byType(StintLineChart).last,
        matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is StintChartPainter),
      );
      await t.ensureVisible(paint);
      await t.pumpAndSettle();
      final box = t.getRect(paint);
      await t.tapAt(Offset(box.right - 10, box.center.dy));
      await t.pump();

      expect(find.text('Lap 2 · 1:30.088 · Medium'), findsOneWidget);
    });

    test('stintHoverX: 가로 위치 → 가장 가까운 스틴트 안 랩(1~maxX)', () {
      // 그림 영역 = 64 ~ 492(폭 428).
      expect(stintHoverX(dx: 0, width: 500, maxX: 5), 1);
      expect(stintHoverX(dx: 64 + 428 / 2, width: 500, maxX: 5), 3);
      expect(stintHoverX(dx: 999, width: 500, maxX: 5), 5);
      expect(stintHoverX(dx: 100, width: 500, maxX: 1), 1);
      expect(stintHoverX(dx: 10, width: 50, maxX: 5), isNull);
    });

    test('stintTooltipText: 첫 랩을 알면 세션 랩 번호, 모르면 스틴트 안 랩', () {
      const known = StintChartSeries(
        label: 'Stint 2',
        color: AppColors.tyreSoft,
        points: [(x: 1, y: 90088)],
        startLap: 12,
        compound: 'Soft',
      );
      const unknown = StintChartSeries(label: 'Stint 1', color: AppColors.tyreSoft, points: []);
      String fmt(double v) => '${v.round()}';

      expect(stintTooltipText(known, 1, 90088, fmt), 'Lap 12 · 90088 · Soft');
      expect(stintTooltipText(unknown, 3, 95, fmt), 'Lap 3 in stint · 95');
    });

    testWidgets('패널티: 랩·You·침해·벌칙(시간이면 초)', (t) async {
      await _pumpPage(t, _repo(_fullDetail()));

      expect(find.text('Small Collision'), findsOneWidget);
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Time Penalty (5s)'), findsOneWidget);
      expect(find.text('Corner Cutting'), findsOneWidget);
    });

    testWidgets('데이터가 없으면 카드마다 안내 문구', (t) async {
      await _pumpPage(t, _repo(detailOf('d1', results: _raceResults())));

      for (final message in [
        '이 세션에는 랩 데이터가 없어요.',
        '이 세션에는 엔진 마모 데이터가 없어요.',
        '이 세션에는 타이어 마모 데이터가 없어요.',
        '이 세션에는 스틴트 랩타임 데이터가 없어요.',
        '이 세션에는 패널티 기록이 없어요.',
      ]) {
        expect(find.text(message), findsOneWidget, reason: message);
      }
    });

    test('tyreColorOf: 컴파운드 토큰, 모르면 muted', () {
      expect(tyreColorOf('Soft'), AppColors.tyreSoft);
      expect(tyreColorOf('Medium'), AppColors.tyreMedium);
      expect(tyreColorOf('Hard'), AppColors.tyreHard);
      expect(tyreColorOf('Intermediate'), AppColors.tyreIntermediate);
      expect(tyreColorOf('Wet'), AppColors.tyreWet);
      expect(tyreColorOf('Weird'), AppColors.textMuted);
    });

    test('stintXTicks: 10개 이하로 건너뛴다', () {
      expect(stintXTicks(3), [1, 2, 3]);
      expect(stintXTicks(25), [1, 4, 7, 10, 13, 16, 19, 22, 25]);
    });
  });

  group('불러오기·뒤로 가기', () {
    testWidgets('없는 세션은 404 상태', (t) async {
      final router = await _pumpPage(t, FakeSessionsRepository(), sessionId: 'missing');

      expect(find.text('찾을 수 없는 세션입니다.'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);

      await t.tap(find.text('Sessions'));
      await t.pumpAndSettle();

      expect(_location(router), '/sessions');
    });

    testWidgets('실패하면 다시 시도로 다시 불러온다', (t) async {
      final repo = _FlakySessionsRepository(details: {'d1': detailOf('d1', results: _raceResults())});
      await _pumpPage(t, repo);

      expect(find.text('다시 시도'), findsOneWidget);

      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();

      expect(find.text('NORRIS'), findsOneWidget);
    });

    testWidgets('서버 오류는 메시지 + 다시 시도', (t) async {
      await _pumpPage(t, _ServerErrorRepository());

      expect(find.text('서버가 아파요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('from이 없으면 시즌 세션이어도 목록으로', (t) async {
      final router = await _pumpPage(t, _repo(_fullDetail()));

      await t.tap(find.byTooltip('세션 목록'));
      await t.pumpAndSettle();

      expect(_location(router), '/sessions');
    });

    testWidgets('from=season이면 그 시즌의 Season 탭으로', (t) async {
      final router = await _pumpPage(t, _repo(_fullDetail()), initialLocation: '/sessions/d1?from=season');

      await t.tap(find.byTooltip('시즌으로'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/season-1?tab=season');
    });

    testWidgets('from=season이어도 시즌 없는 세션은 목록으로', (t) async {
      final router = await _pumpPage(t, _repo(detailOf('d1', gameMode: 'Online')), initialLocation: '/sessions/d1?from=season');

      await t.tap(find.byTooltip('세션 목록'));
      await t.pumpAndSettle();

      expect(_location(router), '/sessions');
    });
  });
}
