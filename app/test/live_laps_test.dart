import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/widgets/app_notice.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/core/shell/app_shell.dart';
import 'package:simcenter_app/core/time/clock_provider.dart';
import 'package:simcenter_app/core/widgets/fresh_highlight.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/dashboard/presentation/dashboard_page.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';
import 'package:simcenter_app/features/laps/application/fresh_laps.dart';
import 'package:simcenter_app/features/laps/application/laps_providers.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/laps/presentation/laps_page.dart';
import 'package:simcenter_app/features/live_laps/application/live_laps_controller.dart';
import 'package:simcenter_app/features/live_laps/presentation/new_lap_snack_bar.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';

import 'support/fakes.dart';

/// D-50(docs/15 §9): 새 랩 실시간 표시.

/// 셸 없이 컨트롤러만 붙인 컨테이너. 내 트랙 목록을 듣고 있어 다시 불러오기 횟수를 셀 수 있다.
Future<({ProviderContainer container, FakeRankingHub hub, FakeLapsRepository repo})> _container(
  WidgetTester tester, {
  AppUser? user = testUser,
  FakeRankingHub? hub,
}) async {
  final fakeHub = hub ?? FakeRankingHub();
  final repo = FakeLapsRepository(tracks: [trackOf('t1', 'Jeddah')]);
  // 위젯 트리의 ProviderScope에 올린다 — 테스트가 끝나 트리가 정리될 때 컨테이너도 정리돼 강조 타이머가 남지 않는다.
  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      fakeAuth(user),
      rankingHubClientProvider.overrideWithValue(fakeHub),
      lapsRepositoryProvider.overrideWithValue(repo),
      devicesRepositoryProvider.overrideWithValue(FakeDevicesRepository()),
    ],
    child: Builder(builder: (context) {
      container = ProviderScope.containerOf(context);
      return const SizedBox();
    }),
  ));
  await container.read(authControllerProvider.future);
  container.listen(myTracksProvider, (_, _) {});
  container.listen(liveLapsControllerProvider, (_, _) {});
  await _flush(tester);
  return (container: container, hub: fakeHub, repo: repo);
}

/// 실제 셸 + Dashboard·Laps 화면을 올린다. 랩 상세는 자리표시.
Future<({FakeRankingHub hub, FakeLapsRepository repo})> _pumpApp(
  WidgetTester tester, {
  required String initialLocation,
  List<Lap> laps = const [],
}) async {
  setViewSize(tester, const Size(1200, 1400));
  final hub = FakeRankingHub();
  final repo = FakeLapsRepository(tracks: [trackOf('t1', 'Jeddah')], laps: laps);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/laps', builder: (_, _) => const LapsPage()),
          GoRoute(path: '/laps/:lapId', builder: (_, state) => Text('body:lap:${state.pathParameters['lapId']}')),
          GoRoute(path: '/settings', builder: (_, _) => const Text('body:settings')),
        ],
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      fakeAuth(),
      rankingHubClientProvider.overrideWithValue(hub),
      lapsRepositoryProvider.overrideWithValue(repo),
      rankingRepositoryProvider.overrideWithValue(FakeRankingRepository()),
      devicesRepositoryProvider.overrideWithValue(FakeDevicesRepository()),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 18, 11)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (hub: hub, repo: repo);
}

/// 허브 이벤트 → provider 다시 불러오기(예약 작업) → 저장소 응답까지 흘려보낸다.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(Duration.zero);
  }
}

Lap _lapFromPayload(Map<String, dynamic> payload) => Lap.fromJson(payload);

Finder _freshIn(String rowKey) =>
    find.descendant(of: find.byKey(ValueKey(rowKey)), matching: find.byType(FreshHighlight));

void main() {
  group('LapRecorded 파싱', () {
    test('LapDto + trackId 페이로드를 랩으로 읽는다', () {
      final lap = Lap.tryParse(lapRecordedPayload('l9', trackId: 't7'))!;

      expect(lap.lapId, 'l9');
      expect(lap.trackId, 't7');
      expect(lap.lapTimeMs, 98448);
      expect(lap.team?.name, 'Ferrari');
      expect(lap.hasTrace, isTrue);
    });

    test('필수 필드가 없는 옛 페이로드는 null', () {
      expect(Lap.tryParse({'lapId': 'l1', 'trackId': 't1', 'lapTimeMs': 1}), isNull);
    });

    test('/me/laps 항목처럼 trackId가 없으면 null', () {
      final json = lapRecordedPayload('l1')..remove('trackId');

      expect(Lap.fromJson(json).trackId, isNull);
    });
  });

  group('실시간 새 랩 리스너', () {
    testWidgets('로그인 상태면 허브에 연결하고, 받은 랩을 알리고 강조 목록에 넣는다', (t) async {
      final (:container, :hub, repo: _) = await _container(t);

      expect(hub.connectCalls, 1);
      expect(container.read(liveLapsControllerProvider), isNull);

      hub.laps.add(lapRecordedPayload('l9'));
      await _flush(t);

      final event = container.read(liveLapsControllerProvider)!;
      expect(event.lap.lapId, 'l9');
      expect(event.lap.trackName, 'Jeddah');
      expect(container.read(freshLapIdsProvider), contains('l9'));
    });

    testWidgets('새 랩을 받으면 랩 provider들을 다시 불러온다', (t) async {
      final (:container, :hub, :repo) = await _container(t);
      final before = repo.tracksCalls;

      hub.laps.add(lapRecordedPayload('l9'));
      await _flush(t);
      await _flush(t);

      expect(repo.tracksCalls, before + 1);
    });

    testWidgets('같은 랩이 두 번 와도 알림 이벤트는 따로 나온다', (t) async {
      final (:container, :hub, repo: _) = await _container(t);
      final events = <LiveLapEvent?>[];
      container.listen(liveLapsControllerProvider, (_, next) => events.add(next));

      hub.laps.add(lapRecordedPayload('l9'));
      await _flush(t);
      hub.laps.add(lapRecordedPayload('l9'));
      await _flush(t);

      expect(events, hasLength(2));
    });

    testWidgets('읽을 수 없는 페이로드는 알리지 않지만 목록은 다시 불러온다', (t) async {
      final (:container, :hub, :repo) = await _container(t);
      final before = repo.tracksCalls;

      hub.laps.add({'lapId': 'l1'});
      await _flush(t);
      await _flush(t);

      expect(container.read(liveLapsControllerProvider), isNull);
      expect(repo.tracksCalls, before + 1);
    });

    testWidgets('재연결되면 놓친 랩을 채우려 한 번 다시 불러온다(알림 없음)', (t) async {
      final (:container, :hub, :repo) = await _container(t);
      final before = repo.tracksCalls;

      hub.reconnects.add(null);
      await _flush(t);
      await _flush(t);

      expect(repo.tracksCalls, before + 1);
      expect(container.read(liveLapsControllerProvider), isNull);
    });

    testWidgets('연결이 완전히 끊기면 잠시 뒤 다시 연결하고, 성공하면 다시 불러온다', (t) async {
      final (:container, :hub, :repo) = await _container(t);
      final before = repo.tracksCalls;

      hub.closes.add(null);
      await _flush(t);
      expect(hub.connectCalls, 1);

      await t.pump(kLiveLapsRetryDelay);
      await _flush(t);

      expect(hub.connectCalls, 2);
      expect(repo.tracksCalls, before + 1);
    });

    testWidgets('첫 연결이 실패하면 잠시 뒤 다시 시도한다', (t) async {
      final hub = FakeRankingHub()..connectError = StateError('서버 없음');
      final (container: _, hub: _, :repo) = await _container(t, hub: hub);
      expect(hub.connectCalls, 1);

      hub.connectError = null;
      await t.pump(kLiveLapsRetryDelay);
      await _flush(t);

      expect(hub.connectCalls, 2);
      expect(repo.tracksCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('로그인 전에는 연결하지 않는다', (t) async {
      final (container: _, :hub, repo: _) = await _container(t, user: null);

      expect(hub.connectCalls, 0);
      expect(hub.laps.hasListener, isFalse);
    });

    testWidgets('로그아웃하면 듣기를 멈춘다', (t) async {
      final (:container, :hub, repo: _) = await _container(t);
      expect(hub.laps.hasListener, isTrue);

      await container.read(authControllerProvider.notifier).logout();
      await _flush(t);

      expect(hub.laps.hasListener, isFalse);
      expect(hub.reconnects.hasListener, isFalse);
      hub.laps.add(lapRecordedPayload('l9'));
      await _flush(t);
      expect(container.read(liveLapsControllerProvider), isNull);
    });
  });

  group('셸 알림과 강조', () {
    testWidgets('어느 화면에서든 새 랩 알림을 띄우고 보기를 누르면 랩 상세로 간다', (t) async {
      final (:hub, repo: _) = await _pumpApp(t, initialLocation: '/settings');

      hub.laps.add(lapRecordedPayload('l9'));
      await _flush(t);
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('새 랩 1:38.448 · Jeddah ✓'), findsOneWidget);
      // 자동으로 넘기지 않는다.
      expect(find.text('body:settings'), findsOneWidget);

      await t.tap(find.text('보기'));
      await t.pumpAndSettle();

      expect(find.text('body:lap:l9'), findsOneWidget);
    });

    testWidgets('무효 랩은 ✕로 알린다', (t) async {
      final (:hub, repo: _) = await _pumpApp(t, initialLocation: '/settings');

      hub.laps.add(lapRecordedPayload('l9', lapTimeMs: 101234, isValid: false));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('새 랩 1:41.234 · Jeddah ✕'), findsOneWidget);
      await t.pumpAndSettle(kNewLapSnackBarDuration);
    });

    testWidgets('알림은 잠시 뒤 저절로 사라진다', (t) async {
      final (:hub, repo: _) = await _pumpApp(t, initialLocation: '/settings');

      hub.laps.add(lapRecordedPayload('l9'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppToast), findsOneWidget);

      // 실제 앱처럼 프레임을 계속 흘려 알림 시간이 지나가게 한다(긴 pump 한 번은 사라질 타이머를 늦게 건다).
      for (var s = 0; s <= kNewLapSnackBarDuration.inSeconds + 1; s++) {
        await t.pump(const Duration(seconds: 1));
      }
      await t.pumpAndSettle();

      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('Laps 표에 새 행이 바로 나타나 잠깐 강조된다', (t) async {
      final old = lapOf('l1', 'Jeddah', 99000);
      final (:hub, :repo) = await _pumpApp(t, initialLocation: '/laps', laps: [old]);
      expect(find.byKey(const ValueKey('lap-row-l1')), findsOneWidget);

      final payload = lapRecordedPayload('l9');
      repo.laps = [_lapFromPayload(payload), old];
      hub.laps.add(payload);
      await t.pump();
      await t.pump();
      await t.pump();

      expect(find.byKey(const ValueKey('lap-row-l9')), findsOneWidget);
      expect(_freshIn('lap-row-l9'), findsOneWidget);
      expect(_freshIn('lap-row-l1'), findsNothing);

      await t.pump(kFreshLapKeepDuration);
      await t.pumpAndSettle();

      expect(_freshIn('lap-row-l9'), findsNothing);
      expect(find.byKey(const ValueKey('lap-row-l9')), findsOneWidget);
    });

    testWidgets('Dashboard 최근 랩에도 새 랩이 바로 나타나 잠깐 강조된다', (t) async {
      final old = lapOf('l1', 'Silverstone', 83452);
      final (:hub, :repo) = await _pumpApp(t, initialLocation: '/', laps: [old]);

      final payload = lapRecordedPayload('l9');
      repo.laps = [_lapFromPayload(payload), old];
      hub.laps.add(payload);
      await t.pump();
      await t.pump();
      await t.pump();

      expect(_freshIn('recent-lap-l9'), findsOneWidget);
      expect(_freshIn('recent-lap-l1'), findsNothing);

      await t.pump(kFreshLapKeepDuration);
      await t.pumpAndSettle();
      expect(_freshIn('recent-lap-l9'), findsNothing);
    });
  });
}
