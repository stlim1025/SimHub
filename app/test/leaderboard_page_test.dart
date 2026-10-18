import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';
import 'package:simcenter_app/features/ranking/presentation/leaderboard_page.dart';

import 'support/fakes.dart';

const _monaco = Track(trackId: 't1', gameCode: 'F1_25', name: 'Monaco');
const _silverstone = Track(trackId: 't2', gameCode: 'F1_25', name: 'Silverstone');

class _Harness {
  _Harness(this.router, this.repo, this.hub);

  final GoRouter router;
  final FakeRankingRepository repo;
  final FakeRankingHub hub;

  String get location => router.routeInformationProvider.value.uri.toString();
}

Future<_Harness> _pumpLeaderboard(
  WidgetTester tester, {
  String location = '/leaderboard',
  List<RankingEntry> Function(String trackId, String period, int call)? entriesFor,
  Size size = const Size(1000, 800),
  TargetPlatform? platform,
}) async {
  setViewSize(tester, size);
  final repo = FakeRankingRepository(
    tracks: const [_monaco, _silverstone],
    entriesFor: entriesFor ?? (trackId, period, _) => [entryOf(1, '$trackId-$period-1위', 80000)],
  );
  final hub = FakeRankingHub();
  final router = GoRouter(initialLocation: location, routes: [
    GoRoute(
      path: '/leaderboard',
      // 실제 앱에서는 AppShell의 Scaffold가 Material 조상을 제공한다.
      builder: (_, state) => Scaffold(
        body: LeaderboardPage(trackId: state.uri.queryParameters['trackId']),
      ),
    ),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankingRepositoryProvider.overrideWithValue(repo),
      rankingHubClientProvider.overrideWithValue(hub),
    ],
    child: MaterialApp.router(theme: ThemeData(platform: platform), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return _Harness(router, repo, hub);
}

void main() {
  testWidgets('trackId가 없으면 첫 트랙의 월별 TOP10을 보여준다', (t) async {
    final h = await _pumpLeaderboard(t);

    expect(h.repo.requests.single, (trackId: 't1', period: 'monthly'));
    expect(find.text('Monaco'), findsOneWidget); // 드롭다운 선택값.
    expect(find.text('t1-monthly-1위'), findsOneWidget);
    expect(find.text('1:20.000'), findsOneWidget);
  });

  testWidgets('?trackId=가 있으면 그 트랙을 보여준다', (t) async {
    final h = await _pumpLeaderboard(t, location: '/leaderboard?trackId=t2');

    expect(h.repo.requests.single, (trackId: 't2', period: 'monthly'));
    expect(find.text('Silverstone'), findsOneWidget);
  });

  testWidgets('알 수 없는 trackId면 첫 트랙으로 대체한다', (t) async {
    final h = await _pumpLeaderboard(t, location: '/leaderboard?trackId=nope');

    expect(h.repo.requests.single.trackId, 't1');
  });

  testWidgets('기간을 일·연으로 바꾸면 해당 기간을 다시 읽는다', (t) async {
    final h = await _pumpLeaderboard(t);

    await t.tap(find.text('일'));
    await t.pumpAndSettle();
    expect(h.repo.requests.last, (trackId: 't1', period: 'daily'));
    expect(find.text('t1-daily-1위'), findsOneWidget);

    await t.tap(find.text('연'));
    await t.pumpAndSettle();
    expect(h.repo.requests.last, (trackId: 't1', period: 'yearly'));
    expect(find.text('t1-yearly-1위'), findsOneWidget);
  });

  testWidgets('트랙을 고르면 ?trackId=로 주소가 바뀌고 그 트랙을 읽는다', (t) async {
    final h = await _pumpLeaderboard(t);

    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Silverstone').last);
    await t.pumpAndSettle();

    expect(h.location, '/leaderboard?trackId=t2');
    expect(h.repo.requests.last, (trackId: 't2', period: 'monthly'));
    expect(find.text('t2-monthly-1위'), findsOneWidget);
  });

  testWidgets('트랙을 바꿔도 선택한 기간은 유지된다', (t) async {
    final h = await _pumpLeaderboard(t);
    await t.tap(find.text('연'));
    await t.pumpAndSettle();

    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Silverstone').last);
    await t.pumpAndSettle();

    expect(h.repo.requests.last, (trackId: 't2', period: 'yearly'));
  });

  testWidgets('월별 보기에서 허브 스냅샷이 오면 즉시 반영한다', (t) async {
    final h = await _pumpLeaderboard(t);

    h.hub.updates.add(hubPayload('t1', [entryOf(1, '실시간 주인공', 79000)]));
    await t.pumpAndSettle();

    expect(find.text('실시간 주인공'), findsOneWidget);
    expect(find.text('1:19.000'), findsOneWidget);
    expect(h.repo.requests, hasLength(1));
  });

  testWidgets('기록이 없으면 안내 문구를 보여준다', (t) async {
    await _pumpLeaderboard(t, entriesFor: (_, _, _) => const []);

    expect(find.textContaining('아직 기록이 없어요'), findsOneWidget);
  });
  group('트랙 선택 상자와 기간 버튼', () {
    void expectSameHeightRow(WidgetTester t) {
      final field = find.byType(InputDecorator).first;
      final segments = find.byType(SegmentedButton<String>);
      expect(field, findsOneWidget);
      expect(segments, findsOneWidget);
      expect(t.getSize(field).height, t.getSize(segments).height);
      expect(t.getCenter(field).dy, t.getCenter(segments).dy);
    }

    for (final platform in [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('${platform.name}에서도 높이가 같고 세로 중앙이 맞는다', (t) async {
        await _pumpLeaderboard(t, platform: platform);

        expectSameHeightRow(t);
      });
    }

    testWidgets('좁은 화면에서는 줄바꿈되어도 넘치지 않고 높이가 같다', (t) async {
      await _pumpLeaderboard(t, size: const Size(320, 800), platform: TargetPlatform.android);

      expect(t.takeException(), isNull);
      final field = find.byType(InputDecorator).first;
      final segments = find.byType(SegmentedButton<String>);
      expect(t.getSize(field).height, t.getSize(segments).height);
    });
  });
}
