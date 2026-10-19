import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/core/router/app_router.dart';
import 'package:simcenter_app/core/shell/app_shell.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/auth/presentation/login_page.dart';
import 'package:simcenter_app/features/dashboard/presentation/dashboard_page.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';
import 'package:simcenter_app/features/devices/presentation/telemetry_app_page.dart';
import 'package:simcenter_app/features/lap_detail/data/lap_detail_repository.dart';
import 'package:simcenter_app/features/lap_detail/presentation/lap_detail_page.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/presentation/laps_page.dart';
import 'package:simcenter_app/features/laps/presentation/track_laps_page.dart';
import 'package:simcenter_app/features/profile/data/profile_repository.dart';
import 'package:simcenter_app/features/profile/presentation/settings_page.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';
import 'package:simcenter_app/features/seasons/presentation/season_detail_page.dart';
import 'package:simcenter_app/features/seasons/presentation/seasons_page.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';
import 'package:simcenter_app/features/sessions/presentation/session_detail_page.dart';
import 'package:simcenter_app/features/sessions/presentation/sessions_page.dart';

import 'support/fakes.dart';

Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  AppUser? user = testUser,
  FakeSessionsRepository? sessionsRepo,
  FakeSeasonsRepository? seasonsRepo,
  FakeLapDetailRepository? lapDetailRepo,
}) async {
  setViewSize(tester, const Size(1000, 800));
  final container = ProviderContainer(overrides: [
    fakeAuth(user),
    lapsRepositoryProvider.overrideWithValue(FakeLapsRepository()),
    lapDetailRepositoryProvider.overrideWithValue(lapDetailRepo ?? FakeLapDetailRepository()),
    seasonsRepositoryProvider.overrideWithValue(seasonsRepo ?? FakeSeasonsRepository()),
    sessionsRepositoryProvider.overrideWithValue(sessionsRepo ?? FakeSessionsRepository()),
    devicesRepositoryProvider.overrideWithValue(FakeDevicesRepository()),
    rankingRepositoryProvider.overrideWithValue(FakeRankingRepository(
      tracks: const [Track(trackId: 't1', gameCode: 'F1_25', name: 'Monaco')],
    )),
    rankingHubClientProvider.overrideWithValue(FakeRankingHub()),
    profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

void main() {
  testWidgets('로그인 상태로 스플래시를 벗어나면 /의 Dashboard로 간다', (t) async {
    final router = await _pumpApp(t);

    expect(_location(router), '/');
    expect(find.text('Welcome 홍길동!'), findsOneWidget);
  });

  testWidgets('로그인 상태에서 /home은 /로 리다이렉트된다', (t) async {
    final router = await _pumpApp(t);

    router.go('/home');
    await t.pumpAndSettle();

    expect(_location(router), '/');
    expect(find.text('Welcome 홍길동!'), findsOneWidget);
  });

  testWidgets('로그인 상태에서 /login은 /로 리다이렉트된다', (t) async {
    final router = await _pumpApp(t);

    router.go('/login');
    await t.pumpAndSettle();

    expect(_location(router), '/');
  });

  testWidgets('로그아웃 상태면 /login으로 보낸다', (t) async {
    final router = await _pumpApp(t, user: null);

    expect(_location(router), '/login');
  });

  testWidgets('/leaderboard?trackId= 와 /laps는 셸 안에서 열린다', (t) async {
    final router = await _pumpApp(t);

    router.go('/leaderboard?trackId=t1');
    await t.pumpAndSettle();
    expect(_location(router), '/leaderboard?trackId=t1');
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
    expect(find.text('Monaco'), findsOneWidget);

    router.go('/laps');
    await t.pumpAndSettle();
    expect(_location(router), '/laps');
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('예전 /rankings/:trackId는 /leaderboard?trackId=로 리다이렉트된다', (t) async {
    final router = await _pumpApp(t);

    router.go('/rankings/t1');
    await t.pumpAndSettle();

    expect(_location(router), '/leaderboard?trackId=t1');
    expect(find.text('Dashboard'), findsOneWidget); // 셸 안의 Leaderboard로 열린다.
    expect(find.text('Monaco'), findsOneWidget);
  });

  testWidgets('/telemetry-app은 셸 안에서 Telemetry App 화면을 연다', (t) async {
    final router = await _pumpApp(t);

    router.go('/telemetry-app');
    await t.pumpAndSettle();

    expect(_location(router), '/telemetry-app');
    expect(find.byType(TelemetryAppPage), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
  });

  testWidgets('사이드바의 Telemetry App 메뉴로 이동한다', (t) async {
    final router = await _pumpApp(t);

    await t.tap(find.text('Telemetry App'));
    await t.pumpAndSettle();

    expect(_location(router), '/telemetry-app');
    expect(find.byType(TelemetryAppPage), findsOneWidget);
  });

  testWidgets('/sessions는 셸 안에서 Sessions 화면을 열고 type 쿼리를 필터로 넘긴다', (t) async {
    final repo = FakeSessionsRepository(sessions: [sessionOf('s1', trackName: 'Spa')]);
    final router = await _pumpApp(t, sessionsRepo: repo);

    router.go('/sessions');
    await t.pumpAndSettle();
    expect(_location(router), '/sessions');
    expect(find.byType(SessionsPage), findsOneWidget);
    expect(find.text('Spa'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
    expect(repo.requests.last.sessionType, isNull);

    router.go('/sessions?type=qualifying');
    await t.pumpAndSettle();
    expect(repo.requests.last.sessionType, 'Qualifying');
  });

  testWidgets('/sessions/:sessionId는 셸 안에서 세션 결과 화면을 연다', (t) async {
    final repo = FakeSessionsRepository(details: {
      'abc': detailOf('abc', trackName: 'Monza', results: [resultOf(1, name: 'NORRIS')]),
    });
    final router = await _pumpApp(t, sessionsRepo: repo);

    router.go('/sessions/abc');
    await t.pumpAndSettle();

    expect(_location(router), '/sessions/abc');
    expect(find.byType(SessionDetailPage), findsOneWidget);
    expect(repo.detailRequests, ['abc']);
    expect(find.text('Monza'), findsOneWidget);
    expect(find.text('NORRIS'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
  });

  testWidgets('/sessions/:sessionId?from=season은 세션 결과 화면을 열고 from을 넘긴다', (t) async {
    final repo = FakeSessionsRepository(details: {
      'abc': detailOf('abc', trackName: 'Monza', results: [resultOf(1, name: 'NORRIS')], seasonId: 'se1', round: 2),
    });
    final router = await _pumpApp(t, sessionsRepo: repo);

    router.go('/sessions/abc?from=season');
    await t.pumpAndSettle();

    expect(_location(router), '/sessions/abc?from=season');
    final page = t.widget<SessionDetailPage>(find.byType(SessionDetailPage));
    expect(page.sessionId, 'abc');
    expect(page.from, 'season');
    expect(find.text('Monza'), findsOneWidget);
    expect(find.text('NORRIS'), findsOneWidget);
  });

  testWidgets('사이드바 하단 프로필을 누르면 셸 안에서 계정 설정(/settings)이 열린다', (t) async {
    final router = await _pumpApp(t, user: settingsUser);

    await t.tap(find.byKey(const ValueKey('account-settings')));
    await t.pumpAndSettle();

    expect(_location(router), '/settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
  });

  testWidgets('로그아웃 상태에서 /settings는 돌아올 주소를 담아 /login으로 보낸다', (t) async {
    final router = await _pumpApp(t, user: null);

    router.go('/settings');
    await t.pumpAndSettle();

    expect(_location(router), '/login?from=%2Fsettings');
  });

  testWidgets('사이드바의 Sessions 메뉴로 이동한다', (t) async {
    final router = await _pumpApp(t);

    await t.tap(find.widgetWithText(ListTile, 'Sessions'));
    await t.pumpAndSettle();

    expect(_location(router), '/sessions');
    expect(find.byType(SessionsPage), findsOneWidget);
  });

  testWidgets('/seasons는 셸 안에서 가장 최근 진행 중인 시즌 상세를 바로 연다', (t) async {
    final repo = FakeSeasonsRepository(
      seasons: [seasonOf('se1', gameMode: 'GrandPrix', seasonNumber: 1)],
      details: {'se1': seasonDetailOf('se1', season: seasonOf('se1', gameMode: 'GrandPrix', seasonNumber: 1))},
    );
    final router = await _pumpApp(t, seasonsRepo: repo);

    router.go('/seasons');
    await t.pumpAndSettle();

    expect(_location(router), '/seasons/se1?tab=season');
    expect(find.byType(SeasonDetailPage), findsOneWidget);
    expect(repo.requests, [(page: 1, pageSize: 20)]);
    expect(find.text('Grand Prix Season 1'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
  });

  testWidgets('/seasons/:seasonId?tab=standings는 셸 안에서 시즌 상세의 Standings 탭을 연다', (t) async {
    final repo = FakeSeasonsRepository(details: {
      'abc': seasonDetailOf('abc', drivers: [driverStandingOf(1, name: 'NORRIS')]),
    });
    final router = await _pumpApp(t, seasonsRepo: repo);

    router.go('/seasons/abc?tab=standings');
    await t.pumpAndSettle();

    expect(_location(router), '/seasons/abc?tab=standings');
    expect(find.byType(SeasonDetailPage), findsOneWidget);
    expect(repo.detailRequests, ['abc']);
    expect(find.text('NORRIS'), findsOneWidget);
    expect(find.textContaining('기록된 세션 기준입니다.'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
  });

  testWidgets('사이드바의 Seasons 메뉴로 이동한다', (t) async {
    final router = await _pumpApp(t);

    await t.tap(find.widgetWithText(ListTile, 'Seasons'));
    await t.pumpAndSettle();

    expect(_location(router), '/seasons');
    expect(find.byType(SeasonsPage), findsOneWidget);
  });

  testWidgets('/laps/:lapId?tab=는 셸 안에서 랩 상세를 열고 tab을 넘긴다(Laps 메뉴 선택 유지)', (t) async {
    final repo = FakeLapDetailRepository(details: {'l1': lapDetailOf(lapOf('l1', 'Jeddah', 98448))});
    final router = await _pumpApp(t, lapDetailRepo: repo);

    router.go('/laps/l1?tab=best');
    await t.pumpAndSettle();

    expect(_location(router), '/laps/l1?tab=best');
    final page = t.widget<LapDetailPage>(find.byType(LapDetailPage));
    expect(page.lapId, 'l1');
    expect(page.tab, 'best');
    expect(repo.detailRequests, ['l1']);
    expect(find.text('Jeddah Lap 1:38.448'), findsOneWidget);
    expect(t.widget<ListTile>(find.widgetWithText(ListTile, 'Laps')).selected, isTrue);
  });

  testWidgets('/laps/tracks/:trackId도 셸 안에서 열린다', (t) async {
    final router = await _pumpApp(t);

    router.go('/laps/tracks/t1');
    await t.pumpAndSettle();

    expect(_location(router), '/laps/tracks/t1');
    expect(find.text('Dashboard'), findsOneWidget); // 사이드바가 그대로 있다.
    expect(find.byType(TrackLapsPage), findsOneWidget);
  });

  group('화면 전환 애니메이션 없음', () {
    /// 트리 안의 모든 Navigator(루트 + 셸)가 쌓은 페이지.
    List<Page<dynamic>> pagesOf(WidgetTester t) => [
          for (final nav in t.widgetList<Navigator>(find.byType(Navigator))) ...nav.pages,
        ];

    testWidgets('모든 라우트 페이지는 전환 효과가 없는 NoTransitionPage다', (t) async {
      final router = await _pumpApp(t);

      for (final location in const [
        '/',
        '/laps',
        '/laps/tracks/t1',
        '/laps/l1?tab=telemetry',
        '/seasons',
        '/sessions',
        '/leaderboard',
      ]) {
        router.go(location);
        await t.pumpAndSettle();
        final pages = pagesOf(t);
        expect(pages, isNotEmpty, reason: location);
        expect(pages.every((p) => p is NoTransitionPage), isTrue, reason: '$location → $pages');
      }
    });

    testWidgets('로그아웃 상태의 /login 페이지도 NoTransitionPage다', (t) async {
      await _pumpApp(t, user: null);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(pagesOf(t).every((p) => p is NoTransitionPage), isTrue);
    });

    testWidgets('사이드바 메뉴를 누르면 한 프레임 만에 새 화면으로 바뀐다', (t) async {
      await _pumpApp(t);
      expect(find.byType(DashboardPage), findsOneWidget);

      await t.tap(find.widgetWithText(ListTile, 'Sessions'));
      await t.pump(); // 라우터 반영
      await t.pump(); // 새 페이지 빌드

      expect(find.byType(SessionsPage), findsOneWidget);
      expect(find.byType(DashboardPage), findsNothing); // 이전 화면이 겹쳐 남지 않는다.
    });

    testWidgets('셸 안의 상세 화면 이동도 한 프레임 만에 바뀐다', (t) async {
      final router = await _pumpApp(t);
      router.go('/laps');
      await t.pumpAndSettle();
      expect(find.byType(LapsPage), findsOneWidget);

      router.go('/laps/tracks/t1');
      await t.pump();
      await t.pump();

      expect(find.byType(TrackLapsPage), findsOneWidget);
      expect(find.byType(LapsPage), findsNothing);
    });

    testWidgets('로그아웃하면 한 프레임 만에 로그인 화면으로 바뀐다', (t) async {
      await _pumpApp(t);
      expect(find.byType(AppShell), findsOneWidget);

      final container = ProviderScope.containerOf(t.element(find.byType(AppShell)));
      await container.read(authControllerProvider.notifier).logout();
      await t.pump();
      await t.pump();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });
  });
}
