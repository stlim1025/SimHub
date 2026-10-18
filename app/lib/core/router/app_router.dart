import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/devices/presentation/telemetry_app_page.dart';
import '../../features/laps/presentation/laps_page.dart';
import '../../features/laps/presentation/track_laps_page.dart';
import '../../features/profile/presentation/settings_page.dart';
import '../../features/ranking/presentation/leaderboard_page.dart';
import '../../features/seasons/presentation/season_detail_page.dart';
import '../../features/seasons/presentation/seasons_page.dart';
import '../../features/sessions/presentation/session_detail_page.dart';
import '../../features/sessions/presentation/sessions_page.dart';
import '../shell/app_shell.dart';

/// 인증 화면(로그인 상태에서는 들어갈 수 없는 경로).
const _authGatePaths = {'/login', '/splash'};

/// 인증 상태 변화에 라우터를 재평가시키는 리스너 + 리다이렉트 가드.
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = _ref.read(authControllerProvider);
    final loc = state.matchedLocation;

    // 세션 복원 중이면 splash 유지.
    if (auth.isLoading || !auth.hasValue) {
      return loc == '/splash' ? null : '/splash';
    }

    final loggedIn = auth.value != null;

    if (!loggedIn) {
      return loc == '/login' ? null : '/login';
    }
    // 예전 홈 경로(`/home`)와 인증 화면은 모두 Dashboard(`/`)로 보낸다.
    if (loc == '/home' || _authGatePaths.contains(loc)) {
      return '/';
    }
    return null;
  }
}

/// 화면 전환 애니메이션 없이 즉시 바뀌는 페이지. 모든 화면은 이 페이지로 연다(메뉴·상세·로그인/스플래시 이동 공통).
/// key·restorationId는 기본 페이지(MaterialPage)와 같게 [GoRouterState.pageKey]를 쓴다.
Page<void> _instantPage(GoRouterState state, Widget child) => NoTransitionPage<void>(
      key: state.pageKey,
      restorationId: state.pageKey.value,
      child: child,
    );

/// [_instantPage]로 [build]가 만든 화면을 여는 경로.
GoRoute _screen(String path, Widget Function(GoRouterState state) build) =>
    GoRoute(path: path, pageBuilder: (_, state) => _instantPage(state, build(state)));

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      _screen('/splash', (_) => const SplashPage()),
      _screen('/login', (_) => const LoginPage()),
      // 예전 랭킹 경로(P5)는 셸 안의 Leaderboard로 보낸다(11 §7.4).
      GoRoute(
        path: '/rankings/:trackId',
        redirect: (_, state) => Uri(
          path: '/leaderboard',
          queryParameters: {'trackId': state.pathParameters['trackId']!},
        ).toString(),
      ),
      ShellRoute(
        pageBuilder: (_, state, child) =>
            _instantPage(state, AppShell(location: state.uri.path, child: child)),
        routes: [
          _screen('/', (_) => const DashboardPage()),
          _screen('/seasons', (_) => const SeasonsPage()),
          // 시즌 상세의 탭은 `?tab=season|results|standings`(모르는 값은 season, docs/12 §8.1).
          _screen(
            '/seasons/:seasonId',
            (state) => SeasonDetailPage(
              seasonId: state.pathParameters['seasonId']!,
              tab: state.uri.queryParameters['tab'],
            ),
          ),
          // 세션 목록의 필터는 `?type=`(모르는 값은 all, docs/12 §8.1).
          _screen('/sessions', (state) => SessionsPage(filter: state.uri.queryParameters['type'])),
          // 세션 상세의 `?from=season`은 시즌 칩에서 열었다는 표시다(뒤로 가기가 그 시즌으로, docs/12 §8.1).
          _screen(
            '/sessions/:sessionId',
            (state) => SessionDetailPage(
              sessionId: state.pathParameters['sessionId']!,
              from: state.uri.queryParameters['from'],
            ),
          ),
          _screen('/laps', (_) => const LapsPage()),
          _screen(
            '/laps/tracks/:trackId',
            (state) => TrackLapsPage(trackId: state.pathParameters['trackId']!),
          ),
          _screen(
            '/leaderboard',
            (state) => LeaderboardPage(trackId: state.uri.queryParameters['trackId']),
          ),
          _screen('/telemetry-app', (_) => const TelemetryAppPage()),
          // 계정 설정(사이드바 하단 프로필에서 연다, docs/14 §8).
          _screen(kSettingsPath, (_) => const SettingsPage()),
        ],
      ),
    ],
  );
});
