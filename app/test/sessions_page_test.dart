import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:simcenter_app/core/widgets/pagination_bar.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';
import 'package:simcenter_app/features/sessions/presentation/sessions_page.dart';

import 'support/fakes.dart';

const _guideText = '결과 화면까지 마친 세션이 여기에 기록됩니다.';
const _noMatchText = '이 조건에 맞는 세션이 없습니다.';
const _pageSize = 15;

/// 첫 호출만 실패하고 이후엔 정상 응답하는 저장소(다시 시도 검증용).
class _FlakySessionsRepository extends FakeSessionsRepository {
  _FlakySessionsRepository({super.sessions});

  int failuresLeft = 1;

  @override
  Future<SessionSummaryPage> getMySessions({
    String? sessionType,
    int page = 1,
    int pageSize = _pageSize,
  }) async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMySessions(sessionType: sessionType, page: page, pageSize: pageSize);
  }
}

Future<GoRouter> _pump(
  WidgetTester tester,
  SessionsRepository repo, {
  String initialLocation = '/sessions',
  Size size = const Size(1000, 2400),
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
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

List<SessionSummary> _races(int count) => [
      for (var i = 0; i < count; i++)
        sessionOf('s$i', trackName: 'Track $i', myPosition: i + 1, classifiedAt: DateTime.utc(2026, 10, 12, 9, i)),
    ];

OutlinedButton _button(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));

bool _chipSelected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

void main() {
  group('SessionsPage', () {
    testWidgets('SessionsPage_Empty_ShowsGuide', (t) async {
      final router = await _pump(t, FakeSessionsRepository());

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
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget); // 필터는 그대로 바꿀 수 있다.
    });

    testWidgets('SessionsPage_Initial_RequestsAllFirstPageOf15', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(1));
      await _pump(t, repo);

      expect(repo.requests, [(sessionType: null, page: 1, pageSize: _pageSize)]);
      expect(_chipSelected(t, 'All'), isTrue);
      expect(_chipSelected(t, 'Race'), isFalse);
    });

    testWidgets('SessionsPage_ShowsRowsAndPagination', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(16));
      await _pump(t, repo);

      expect(find.text('Showing 1 to 15 of 16'), findsOneWidget);
      expect(find.text('R'), findsNWidgets(_pageSize));
      expect(find.text('Track 0'), findsOneWidget);
      expect(find.text('Track 14'), findsOneWidget);
      expect(find.text('Track 15'), findsNothing);
      expect(find.text('P4 / 22'), findsOneWidget);
      expect(find.text('Grid P6'), findsNWidgets(_pageSize));
      expect(find.text('Driver Career'), findsNWidgets(_pageSize));
      expect(find.text('1:45.321'), findsNWidgets(_pageSize));
      expect(find.text('12'), findsNWidgets(_pageSize));
      expect(
        find.text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.utc(2026, 10, 12, 9).toLocal())),
        findsOneWidget,
      );
      expect(find.byType(PaginationBar), findsOneWidget);
      expect(_button(t, '이전').onPressed, isNull);
      expect(_button(t, '다음').onPressed, isNotNull);

      await t.tap(find.text('다음'));
      await t.pumpAndSettle();

      expect(repo.requests.last, (sessionType: null, page: 2, pageSize: _pageSize));
      expect(find.text('Showing 16 to 16 of 16'), findsOneWidget);
      expect(find.text('Track 15'), findsOneWidget);
      expect(_button(t, '다음').onPressed, isNull);
    });

    testWidgets('SessionsPage_FilterChip_RequestsSessionType_AndResetsPage', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(16));
      final router = await _pump(t, repo);
      await t.tap(find.text('다음'));
      await t.pumpAndSettle();
      expect(repo.requests.last.page, 2);

      await t.tap(find.widgetWithText(ChoiceChip, 'Race'));
      await t.pumpAndSettle();

      expect(repo.requests.last, (sessionType: 'Race', page: 1, pageSize: _pageSize));
      expect(_location(router), '/sessions?type=race');
      expect(_chipSelected(t, 'Race'), isTrue);
      expect(_chipSelected(t, 'All'), isFalse);
      expect(find.text('Showing 1 to 15 of 16'), findsOneWidget);
    });

    testWidgets('SessionsPage_EachChip_MapsToItsSessionType', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(1));
      final router = await _pump(t, repo);

      await t.tap(find.widgetWithText(ChoiceChip, 'Qualifying'));
      await t.pumpAndSettle();
      expect(repo.requests.last.sessionType, 'Qualifying');
      expect(_location(router), '/sessions?type=qualifying');

      await t.tap(find.widgetWithText(ChoiceChip, 'Practice'));
      await t.pumpAndSettle();
      expect(repo.requests.last.sessionType, 'Practice');
      expect(_location(router), '/sessions?type=practice');

      await t.tap(find.widgetWithText(ChoiceChip, 'All'));
      await t.pumpAndSettle();
      expect(repo.requests.last.sessionType, isNull);
      expect(_location(router), '/sessions?type=all');
    });

    testWidgets('SessionsPage_SelectedChip_DoesNotReload', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(1));
      final router = await _pump(t, repo, initialLocation: '/sessions?type=race');
      final calls = repo.requests.length;

      await t.tap(find.widgetWithText(ChoiceChip, 'Race'));
      await t.pumpAndSettle();

      expect(repo.requests.length, calls);
      expect(_location(router), '/sessions?type=race');
    });

    testWidgets('SessionsPage_UnknownTypeQuery_FallsBackToAll', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(1));
      await _pump(t, repo, initialLocation: '/sessions?type=weird');

      expect(repo.requests.single.sessionType, isNull);
      expect(_chipSelected(t, 'All'), isTrue);
    });

    testWidgets('SessionsPage_PlayerAbsent_ShowsDash', (t) async {
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
      expect(find.text('-'), findsNWidgets(3)); // 결과 · 베스트 랩 · 점수
      expect(find.textContaining('Grid'), findsNothing);
      expect(find.textContaining(' / '), findsNothing);
    });

    testWidgets('SessionsPage_PositionWithoutGrid_OmitsGrid', (t) async {
      final repo = FakeSessionsRepository(sessions: [
        sessionOf('quali', sessionType: 'Qualifying', sessionKind: 'Qualifying3', myPosition: 2, myGridPosition: 0),
      ]);
      await _pump(t, repo);

      expect(find.text('P2 / 22'), findsOneWidget);
      expect(find.text('Q3'), findsOneWidget);
      expect(find.textContaining('Grid'), findsNothing);
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

    testWidgets('SessionsPage_NarrowScreen_DoesNotOverflow', (t) async {
      final repo = FakeSessionsRepository(sessions: _races(16));
      await _pump(t, repo, size: const Size(400, 2400));

      expect(t.takeException(), isNull);
      expect(find.text('Showing 1 to 15 of 16'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Practice'), findsOneWidget);
    });

    testWidgets('SessionsPage_NarrowScreen_EmptyDoesNotOverflow', (t) async {
      await _pump(t, FakeSessionsRepository(), size: const Size(400, 800));

      expect(t.takeException(), isNull);
      expect(find.text(_guideText), findsOneWidget);
    });
  });
}
