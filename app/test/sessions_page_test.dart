import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:simcenter_app/core/widgets/menu_items.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/core/widgets/pagination_bar.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';
import 'package:simcenter_app/features/sessions/presentation/session_widgets.dart';
import 'package:simcenter_app/features/sessions/presentation/sessions_page.dart';

import 'support/fakes.dart';

const _guideText = '결과 화면까지 마친 세션이 여기에 기록됩니다.';
const _noMatchText = '이 조건에 맞는 세션이 없습니다.';
const _pageSize = 15;
const _ferrari = LapTeam(name: 'Ferrari', color: '#E8002D');

/// 첫 호출만 실패하고 이후엔 정상 응답하는 저장소(다시 시도 검증용).
class _FlakySessionsRepository extends FakeSessionsRepository {
  _FlakySessionsRepository({super.sessions});

  int failuresLeft = 1;

  @override
  Future<SessionSummaryPage> getMySessions({
    String? sessionType,
    int page = 1,
    int pageSize = _pageSize,
    String? gameCode,
  }) async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMySessions(sessionType: sessionType, page: page, pageSize: pageSize, gameCode: gameCode);
  }
}

Future<GoRouter> _pump(
  WidgetTester tester,
  SessionsRepository repo, {
  String initialLocation = '/sessions',
  Size size = const Size(1000, 2400),
  ThemeData? theme,
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(
      path: '/sessions',
      builder: (_, state) => Scaffold(body: SessionsPage(filter: state.uri.queryParameters['type'])),
    ),
    GoRoute(
      path: '/sessions/:sessionId',
      builder: (_, state) => Text('detail:${state.pathParameters['sessionId']}'),
    ),
    GoRoute(path: '/telemetry-app', builder: (_, _) => const Text('telemetry-app')),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [sessionsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(theme: theme, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

List<SessionSummary> _races(int count) => [
      for (var i = 0; i < count; i++)
        sessionOf(
          's$i',
          trackName: 'Track $i',
          myPosition: i + 1,
          classifiedAt: DateTime.utc(2026, 10, 12, 9, i),
          countryCode: 'BE',
          myTeam: _ferrari,
          seasonNumber: 1,
        ),
    ];

OutlinedButton _button(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));

Future<void> _pickFilter(WidgetTester t, String label) async {
  await t.tap(find.byKey(const ValueKey('sessions-filter-menu')));
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(CheckMenuItem<String>, label));
  await t.pumpAndSettle();
}

void main() {
  group('SessionsPage', () {
    testWidgets('SessionsPage_Empty_ShowsGuide', (t) async {
      final router = await _pump(t, FakeSessionsRepository());

      expect(find.text('All Sessions'), findsOneWidget);
      expect(find.text(_guideText), findsOneWidget);
      expect(find.text(_noMatchText), findsNothing);
      expect(find.textContaining('Showing'), findsNothing);

      await t.tap(find.text('Telemetry App'));
      await t.pumpAndSettle();

      expect(_location(router), '/telemetry-app');
    });

    testWidgets('SessionsPage_FilteredEmpty_ShowsNoMatch', (t) async {
      final repo = FakeSessionsRepository(sessions: [
        sessionOf('q1', sessionType: 'Qualifying', sessionKind: 'Qualifying1'),
      ]);
      await _pump(t, repo, initialLocation: '/sessions?type=race');

      expect(repo.requests.single.sessionType, 'Race');
      expect(find.text(_noMatchText), findsOneWidget);
      expect(find.text(_guideText), findsNothing);
      expect(find.text('Telemetry App'), findsNothing);
      expect(find.text('Filters: Race'), findsOneWidget); // 필터는 그대로 바꿀 수 있다.
    });

    testWidgets('SessionsPage_Initial_RequestsAllFirstPageOf15', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(1));
      await _pump(t, repo);

      expect(repo.requests, [(sessionType: null, page: 1, pageSize: _pageSize)]);
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('SessionsPage_ShowsF1LapsColumnsAndPagination', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(16));
      await _pump(t, repo);

      for (final header in ['TRACK', 'TEAM', 'RESULT', 'TIME']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('Showing 1 to 15 of 16'), findsOneWidget);
      expect(find.text('Track 0'), findsOneWidget);
      expect(find.text('Track 14'), findsOneWidget);
      expect(find.text('Track 15'), findsNothing);
      expect(find.text('Race'), findsNWidgets(_pageSize)); // 트랙 아래 세션 종류
      expect(find.text('Ferrari'), findsNWidgets(_pageSize)); // Team 221이 아니라 내 팀 이름
      expect(find.text('Driver Career Season 1'), findsNWidgets(_pageSize));
      expect(find.text('P4'), findsOneWidget);
      expect(find.byKey(const ValueKey('track-flag-BE')), findsNWidgets(_pageSize));
      final local = DateTime.utc(2026, 10, 12, 9).toLocal();
      expect(find.text(DateFormat('yyyy-MM-dd').format(local)), findsNWidgets(_pageSize));
      expect(find.text(DateFormat('HH:mm').format(local)), findsOneWidget);
      expect(find.byType(PaginationBar), findsOneWidget);
      expect(_button(t, '이전').onPressed, isNull);

      await t.tap(find.text('다음'));
      await t.pumpAndSettle();

      expect(repo.requests.last, (sessionType: null, page: 2, pageSize: _pageSize));
      expect(find.text('Showing 16 to 16 of 16'), findsOneWidget);
      expect(find.text('Track 15'), findsOneWidget);
      expect(_button(t, '다음').onPressed, isNull);
    });

    testWidgets('SessionsPage_RaceBadgeIsEmphasized_QualifyingIsNot', (t) async {
      final repo = FakeSessionsRepository(sessions: [
        sessionOf('r', myPosition: 22),
        sessionOf('q', sessionType: 'Qualifying', sessionKind: 'Qualifying3', myPosition: 8, gameMode: 'GrandPrix'),
      ]);
      await _pump(t, repo);

      expect(t.widget<PositionBadge>(find.widgetWithText(PositionBadge, 'P22')).emphasized, isTrue);
      expect(t.widget<PositionBadge>(find.widgetWithText(PositionBadge, 'P8')).emphasized, isFalse);
      expect(find.text('Qualifying 3'), findsOneWidget);
      expect(find.text('Grand Prix'), findsOneWidget); // 시즌이 아니면 모드만
    });

    testWidgets('SessionsPage_SprintWeekend_LabelsSprintAndRace_UnknownPositionDash', (t) async {
      final repo = FakeSessionsRepository(sessions: [
        sessionOf('s', sessionKind: 'Race', isSprintWeekend: true, myPosition: 5),
        sessionOf('r', sessionKind: 'Race2', isSprintWeekend: true, myPosition: 3),
        // 위치 모름은 서버·모델이 null로 바꿔 둔다(P0 대신 -).
        sessionOf('q', sessionType: 'Qualifying', sessionKind: 'Qualifying2', myPosition: null),
      ]);
      await _pump(t, repo);

      expect(find.text('Sprint'), findsOneWidget);
      expect(find.text('Race'), findsOneWidget);
      expect(find.text('Race 2'), findsNothing);
      expect(find.text('P0'), findsNothing);
    });

    testWidgets('SessionsPage_TeamDotUsesMyTeamColor', (t) async {
      await _pump(t, FakeSessionsRepository(sessions: _races(1)));

      final dot = t.widget<Container>(
        find.descendant(of: find.byType(TeamDot), matching: find.byType(Container)),
      );
      expect((dot.decoration! as BoxDecoration).color, const Color(0xFFE8002D));
    });

    testWidgets('SessionsPage_FilterMenu_RequestsSessionType_AndResetsPage', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(16));
      final router = await _pump(t, repo);
      await t.tap(find.text('다음'));
      await t.pumpAndSettle();
      expect(repo.requests.last.page, 2);

      await _pickFilter(t, 'Race');

      expect(repo.requests.last, (sessionType: 'Race', page: 1, pageSize: _pageSize));
      expect(_location(router), '/sessions?type=race');
      expect(find.text('Filters: Race'), findsOneWidget);
      expect(find.text('Showing 1 to 15 of 16'), findsOneWidget);
    });

    testWidgets('SessionsPage_EachFilter_MapsToItsSessionType', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(1));
      final router = await _pump(t, repo);

      await _pickFilter(t, 'Qualifying');
      expect(repo.requests.last.sessionType, 'Qualifying');
      expect(_location(router), '/sessions?type=qualifying');

      await _pickFilter(t, 'Practice');
      expect(repo.requests.last.sessionType, 'Practice');
      expect(_location(router), '/sessions?type=practice');

      await _pickFilter(t, 'All');
      expect(repo.requests.last.sessionType, isNull);
      expect(_location(router), '/sessions?type=all');
    });

    testWidgets('SessionsPage_FilterMenu_ChecksSelected_AndSameChoiceDoesNotReload', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(1));
      final router = await _pump(t, repo, initialLocation: '/sessions?type=race');
      final calls = repo.requests.length;

      await t.tap(find.byKey(const ValueKey('sessions-filter-menu')));
      await t.pumpAndSettle();
      final items = t.widgetList<CheckMenuItem<String>>(find.byType(CheckMenuItem<String>));
      expect([for (final item in items) item.checked], [false, true, false, false]);
      await t.tap(find.widgetWithText(CheckMenuItem<String>, 'Race'));
      await t.pumpAndSettle();

      expect(repo.requests.length, calls);
      expect(_location(router), '/sessions?type=race');
    });

    testWidgets('SessionsPage_UnknownTypeQuery_FallsBackToAll', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(1));
      await _pump(t, repo, initialLocation: '/sessions?type=weird');

      expect(repo.requests.single.sessionType, isNull);
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('SessionsPage_PlayerAbsentAndOldServer_ShowsDashesAndFallbackFlag', (t) async {
      final repo = FakeSessionsRepository(sessions: [
        sessionOf(
          'ghost',
          myPosition: null,
          myGridPosition: null,
          myResultStatus: null,
          myBestLapTimeMs: null,
          myPoints: null,
        ),
      ]);
      await _pump(t, repo);

      expect(find.text('Spa'), findsOneWidget);
      expect(find.text('-'), findsNWidgets(2)); // 팀 · 결과
      expect(find.byKey(const ValueKey('track-flag-fallback')), findsOneWidget);
      expect(find.text('Driver Career'), findsOneWidget);
    });

    testWidgets('SessionsPage_TapRow_OpensSessionDetail', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(2));
      final router = await _pump(t, repo);

      await t.tap(find.text('Track 1'));
      await t.pumpAndSettle();

      expect(_location(router), '/sessions/s1');
      expect(find.text('detail:s1'), findsOneWidget);
    });

    testWidgets('SessionsPage_LoadFails_RetryReloads', (t) async {
      final repo = _FlakySessionsRepository(sessions: _races(1));
      await _pump(t, repo);

      expect(find.text('다시 시도'), findsOneWidget);

      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();

      expect(find.text('Track 0'), findsOneWidget);
    });

    testWidgets('SessionsPage_Narrow_HidesTeamSecondLineAndTime', (t) async {
      await _pump(t, FakeSessionsRepository(sessions: _races(1)), size: const Size(500, 1200));

      expect(t.takeException(), isNull);
      expect(find.text('Ferrari'), findsOneWidget);
      expect(find.text('Race'), findsOneWidget); // 트랙 아래줄은 남는다
      expect(find.text('Driver Career Season 1'), findsNothing);
      expect(find.text(DateFormat('HH:mm').format(DateTime.utc(2026, 10, 12, 9).toLocal())), findsNothing);
    });

    testWidgets('SessionsPage_375_DoesNotOverflow_BothThemes', (t) async {
      final long = [
        for (var i = 0; i < 16; i++)
          sessionOf(
            'l$i',
            trackName: 'Autodromo Internazionale Enzo e Dino Ferrari $i',
            sessionKind: 'OneShotSprintShootout',
            countryCode: 'IT',
            myTeam: const LapTeam(name: 'Visa Cash App Racing Bulls Formula One Team', color: '#6692FF'),
            myPosition: 22,
          ),
      ];
      for (final theme in [AppTheme.dark, AppTheme.light]) {
        await _pump(t, FakeSessionsRepository(sessions: long), size: const Size(375, 2400), theme: theme);

        expect(t.takeException(), isNull, reason: '${theme.brightness}');
        expect(find.text('Showing 1 to 15 of 16'), findsOneWidget);
      }
    });

    testWidgets('SessionsPage_NarrowScreen_EmptyDoesNotOverflow', (t) async {
      await _pump(t, FakeSessionsRepository(), size: const Size(375, 800));

      expect(t.takeException(), isNull);
      expect(find.text(_guideText), findsOneWidget);
    });
  });
}
