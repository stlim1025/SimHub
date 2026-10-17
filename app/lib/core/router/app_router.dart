import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/laps/presentation/my_laps_page.dart';
import '../../features/ranking/presentation/leaderboard_page.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
          GoRoute(
            path: '/laps',
            builder: (_, state) => MyLapsPage(
              trackId: state.uri.queryParameters['trackId'],
              trackName: state.uri.queryParameters['trackName'],
            ),
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (_, state) => LeaderboardPage(trackId: state.uri.queryParameters['trackId']),
          ),
        ],
      ),
    ],
  );
});
