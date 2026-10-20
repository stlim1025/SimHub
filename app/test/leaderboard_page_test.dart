import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/core/widgets/button_group.dart';
import 'package:simcenter_app/core/widgets/track_picker.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';
import 'package:simcenter_app/features/ranking/presentation/leaderboard_page.dart';

import 'support/fakes.dart';

const _monaco = Track(trackId: 't1', gameCode: 'F1_25', name: 'Monaco', countryCode: 'MC', displayOrder: 8);
const _silverstone = Track(trackId: 't2', gameCode: 'F1_25', name: 'Silverstone', countryCode: 'GB', displayOrder: 12);

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

    await t.tap(find.byKey(const ValueKey('track-picker')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('track-option-t2')));
    await t.pumpAndSettle();

    expect(h.location, '/leaderboard?trackId=t2');
    expect(h.repo.requests.last, (trackId: 't2', period: 'monthly'));
    expect(find.text('t2-monthly-1위'), findsOneWidget);
  });

  testWidgets('트랙을 바꿔도 선택한 기간은 유지된다', (t) async {
    final h = await _pumpLeaderboard(t);
    await t.tap(find.text('연'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('track-picker')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('track-option-t2')));
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
  group('트랙 메뉴(D-43)', () {
    testWidgets('제목에 고른 트랙의 국기가 보이고, 메뉴는 서버 순서대로 국기와 함께 연다', (t) async {
      await _pumpLeaderboard(t, location: '/leaderboard?trackId=t2');

      expect(find.byKey(const ValueKey('track-flag-GB')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('track-picker')));
      await t.pumpAndSettle();

      final monaco = find.byKey(const ValueKey('track-option-t1'));
      final silverstone = find.byKey(const ValueKey('track-option-t2'));
      expect(t.getTopLeft(monaco).dy, lessThan(t.getTopLeft(silverstone).dy));
      expect(find.descendant(of: monaco, matching: find.byKey(const ValueKey('track-flag-MC'))), findsOneWidget);
    });

    testWidgets('드롭다운 상자 대신 공용 트랙 메뉴를 쓴다', (t) async {
      await _pumpLeaderboard(t);

      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(TrackPicker), findsOneWidget);
    });

    for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
      testWidgets('${platform.name} 좁은 화면(320)에서도 트랙 메뉴와 기간 버튼이 넘치지 않는다', (t) async {
        await _pumpLeaderboard(t, size: const Size(320, 800), platform: platform);

        expect(t.takeException(), isNull);
        expect(find.byType(TrackPicker), findsOneWidget);
        expect(find.byType(ButtonGroup<String>), findsOneWidget);
      });
    }
  });
}
