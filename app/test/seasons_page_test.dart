import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
    GoRoute(
      path: '/seasons/:seasonId',
      builder: (_, state) => Text('detail:${state.pathParameters['seasonId']}:${state.uri.queryParameters['tab']}'),
    ),
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

/// 마지막 세션 날짜가 1월 1일부터 하루씩 늦어지는 시즌 [count]개(se0이 가장 오래됨).
List<SeasonSummary> _seasons(int count) => [
      for (var i = 0; i < count; i++)
        seasonOf('se$i', firstSessionAt: DateTime(2026, 1, 1 + i, 12), lastSessionAt: DateTime(2026, 1, 1 + i, 12)),
    ];

void main() {
  group('SeasonsPage', () {
    testWidgets('SeasonsPage_Empty_ShowsGuideAndImport', (t) async {
      final router = await _pump(t, FakeSeasonsRepository());

      expect(find.text(_guideText), findsOneWidget);
      expect(find.text('Seasons'), findsOneWidget);
      expect(find.text('F1Laps에서 가져오기'), findsOneWidget);
      expect(_location(router), '/seasons');

      await t.tap(find.text('Telemetry App'));
      await t.pumpAndSettle();

      expect(_location(router), '/telemetry-app');
    });

    testWidgets('SeasonsPage_OpensMostRecentActiveSeason', (t) async {
      final repo = FakeSeasonsRepository(seasons: [
        seasonOf('done-new', lastSessionAt: DateTime(2026, 3, 1, 12), completedAt: DateTime.utc(2026, 3, 2)),
        seasonOf('active-old', lastSessionAt: DateTime(2026, 1, 1, 12)),
        seasonOf('active-new', lastSessionAt: DateTime(2026, 2, 1, 12)),
      ]);
      final router = await _pump(t, repo);

      expect(_location(router), '/seasons/active-new?tab=season');
      expect(find.text('detail:active-new:season'), findsOneWidget);
    });

    testWidgets('SeasonsPage_AllCompleted_OpensMostRecentSeason', (t) async {
      final repo = FakeSeasonsRepository(seasons: [
        seasonOf('old', lastSessionAt: DateTime(2026, 1, 1, 12), completedAt: DateTime.utc(2026, 1, 2)),
        seasonOf('new', lastSessionAt: DateTime(2026, 2, 1, 12), completedAt: DateTime.utc(2026, 2, 2)),
      ]);
      final router = await _pump(t, repo);

      expect(_location(router), '/seasons/new?tab=season');
    });

    testWidgets('SeasonsPage_LoadsEveryPageBeforeChoosing', (t) async {
      final repo = FakeSeasonsRepository(seasons: _seasons(25));
      final router = await _pump(t, repo);

      expect(repo.requests, [(page: 1, pageSize: _pageSize), (page: 2, pageSize: _pageSize)]);
      expect(_location(router), '/seasons/se24?tab=season'); // 2페이지에 있는 가장 최근 시즌
    });

    testWidgets('SeasonsPage_LoadFails_RetryReloads', (t) async {
      final repo = _FlakySeasonsRepository(seasons: _seasons(1));
      final router = await _pump(t, repo);

      expect(find.text('다시 시도'), findsOneWidget);

      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();

      expect(_location(router), '/seasons/se0?tab=season');
    });

    testWidgets('SeasonsPage_NarrowScreen_EmptyDoesNotOverflow', (t) async {
      await _pump(t, FakeSeasonsRepository(), size: const Size(320, 800));

      expect(t.takeException(), isNull);
      expect(find.text(_guideText), findsOneWidget);
    });
  });
}
