import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/widgets/pagination_bar.dart';
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';
import 'package:simcenter_app/features/seasons/domain/season_models.dart';
import 'package:simcenter_app/features/seasons/presentation/seasons_page.dart';

import 'support/fakes.dart';

const _guideText = '커리어나 그랑프리 모드에서 세션을 결과 화면까지 마치면 시즌이 기록됩니다.';
const _pageSize = 20;

/// 첫 호출만 실패하고 이후엔 정상 응답하는 저장소(다시 시도 검증용).
class _FlakySeasonsRepository extends FakeSeasonsRepository {
  _FlakySeasonsRepository({super.seasons});

  int failuresLeft = 1;

  @override
  Future<SeasonSummaryPage> getMySeasons({int page = 1, int pageSize = _pageSize}) async {
    if (failuresLeft-- > 0) throw Exception('boom');
    return super.getMySeasons(page: page, pageSize: pageSize);
  }
}

Future<GoRouter> _pump(
  WidgetTester tester,
  SeasonsRepository repo, {
  Size size = const Size(1000, 6000),
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: '/seasons', routes: [
    GoRoute(path: '/seasons', builder: (_, _) => const Scaffold(body: SeasonsPage())),
    GoRoute(path: '/seasons/:seasonId', builder: (_, state) => Text('detail:${state.pathParameters['seasonId']}')),
    GoRoute(path: '/telemetry-app', builder: (_, _) => const Text('telemetry-app')),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [seasonsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

List<SeasonSummary> _seasons(int count) => [
      for (var i = 0; i < count; i++)
        seasonOf('se$i', firstSessionAt: DateTime(2026, 1, 1 + i, 12), lastSessionAt: DateTime(2026, 1, 1 + i, 12)),
    ];

OutlinedButton _button(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));

void main() {
  group('SeasonsPage', () {
    testWidgets('SeasonsPage_Empty_ShowsGuide', (t) async {
      final router = await _pump(t, FakeSeasonsRepository());

      expect(find.text(_guideText), findsOneWidget);
      expect(find.textContaining('Showing'), findsNothing);

      await t.tap(find.text('Telemetry App'));
      await t.pumpAndSettle();

      expect(_location(router), '/telemetry-app');
    });

    testWidgets('SeasonsPage_Initial_RequestsFirstPageOf20', (t) async {
      final repo = FakeSeasonsRepository(seasons: _seasons(1));
      await _pump(t, repo);

      expect(repo.requests, [(page: 1, pageSize: _pageSize)]);
    });

    testWidgets('SeasonsPage_ShowsCardWithMyStandingAndLeader', (t) async {
      final repo = FakeSeasonsRepository(seasons: [
        seasonOf(
          'se1',
          gameMode: 'DriverCareer',
          roundCount: 6,
          myPosition: 3,
          myPoints: 87,
          leaderName: 'VERSTAPPEN',
          leaderPoints: 120,
          firstSessionAt: DateTime(2026, 10, 17, 12),
          lastSessionAt: DateTime(2026, 10, 24, 12),
        ),
      ]);
      await _pump(t, repo);

      expect(find.text('Driver Career · 2026.10.17'), findsOneWidget); // 제목
      expect(find.text('Driver Career'), findsOneWidget); // 게임 모드 배지
      expect(find.text('2026.10.17 ~ 2026.10.24'), findsOneWidget);
      expect(find.text('6 rounds'), findsOneWidget);
      expect(find.text('P3 · 87 pts'), findsOneWidget);
      expect(find.text('VERSTAPPEN 120'), findsOneWidget);
    });

    testWidgets('SeasonsPage_PlayerAbsent_ShowsDash', (t) async {
      final repo = FakeSeasonsRepository(seasons: [seasonOf('se1', myPosition: null, myPoints: null)]);
      await _pump(t, repo);

      expect(find.text('VERSTAPPEN 120'), findsOneWidget);
      expect(find.text('-'), findsOneWidget); // 내 순위만 없다
      expect(find.textContaining('pts'), findsNothing);
    });

    testWidgets('SeasonsPage_NoResultsAtAll_ShowsDashForMeAndLeader', (t) async {
      final repo = FakeSeasonsRepository(seasons: [
        seasonOf('se1', myPosition: null, myPoints: null, leaderName: null, leaderPoints: null),
      ]);
      await _pump(t, repo);

      expect(find.text('-'), findsNWidgets(2));
    });

    testWidgets('SeasonsPage_Paginates', (t) async {
      final repo = FakeSeasonsRepository(seasons: _seasons(25));
      await _pump(t, repo);

      expect(find.byType(PaginationBar), findsOneWidget);
      expect(find.text('Showing 1 to 20 of 25'), findsOneWidget);
      expect(find.text('Driver Career · 2026.01.01'), findsOneWidget);
      expect(find.text('Driver Career · 2026.01.20'), findsOneWidget);
      expect(find.text('Driver Career · 2026.01.21'), findsNothing);
      expect(_button(t, '이전').onPressed, isNull);

      await t.tap(find.text('다음'));
      await t.pumpAndSettle();

      expect(repo.requests.last, (page: 2, pageSize: _pageSize));
      expect(find.text('Showing 21 to 25 of 25'), findsOneWidget);
      expect(find.text('Driver Career · 2026.01.21'), findsOneWidget);
      expect(find.text('Driver Career · 2026.01.01'), findsNothing);
      expect(_button(t, '다음').onPressed, isNull);
    });

    testWidgets('SeasonsPage_TapCard_OpensSeasonDetail', (t) async {
      final repo = FakeSeasonsRepository(seasons: _seasons(2));
      final router = await _pump(t, repo);

      await t.tap(find.text('Driver Career · 2026.01.02'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/se1');
      expect(find.text('detail:se1'), findsOneWidget);
    });

    testWidgets('SeasonsPage_LoadFails_RetryReloads', (t) async {
      final repo = _FlakySeasonsRepository(seasons: _seasons(1));
      await _pump(t, repo);

      expect(find.text('다시 시도'), findsOneWidget);

      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();

      expect(find.text('Driver Career · 2026.01.01'), findsOneWidget);
    });

    testWidgets('SeasonsPage_NarrowScreen_DoesNotOverflow', (t) async {
      final repo = FakeSeasonsRepository(seasons: [
        ..._seasons(19),
        seasonOf(
          'long',
          leaderName: 'A VERY LONG LEADER NAME FOR OVERFLOW CHECKING',
          leaderPoints: 1234,
          myPosition: 22,
          myPoints: 1234,
          roundCount: 24,
        ),
      ]);
      await _pump(t, repo, size: const Size(320, 8000));

      expect(t.takeException(), isNull);
      expect(find.text('Showing 1 to 20 of 20'), findsOneWidget);
    });

    testWidgets('SeasonsPage_NarrowScreen_EmptyDoesNotOverflow', (t) async {
      await _pump(t, FakeSeasonsRepository(), size: const Size(320, 800));

      expect(t.takeException(), isNull);
      expect(find.text(_guideText), findsOneWidget);
    });
  });
}
