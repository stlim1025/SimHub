import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/laps/presentation/my_laps_page.dart';
import '../../features/ranking/presentation/home_page.dart';
import '../../features/ranking/presentation/today_ranking_page.dart';

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
    final atAuthGate = loc == '/login' || loc == '/splash';

    if (!loggedIn) {
      return loc == '/login' ? null : '/login';
    }
    if (atAuthGate) {
      return '/home';
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
      GoRoute(path: '/home', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/rankings/:trackId',
        builder: (_, state) => TodayRankingPage(
          trackId: state.pathParameters['trackId']!,
          trackName: state.uri.queryParameters['trackName'] ?? '랭킹',
        ),
      ),
      GoRoute(
        path: '/my-laps',
        builder: (_, state) => MyLapsPage(
          trackId: state.uri.queryParameters['trackId'],
          trackName: state.uri.queryParameters['trackName'],
        ),
      ),
    ],
  );
});
