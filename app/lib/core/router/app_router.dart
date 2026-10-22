import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/devices/presentation/telemetry_app_page.dart';
import '../../features/lap_detail/domain/lap_compare.dart';
import '../../features/lap_detail/presentation/lap_detail_page.dart';
import '../../features/lap_detail/presentation/shared_lap_page.dart';
import '../../features/laps/presentation/laps_page.dart';
import '../../features/laps/presentation/track_laps_page.dart';
import '../../features/profile/presentation/settings_page.dart';
import '../../features/ranking/presentation/leaderboard_page.dart';
import '../../features/seasons/presentation/season_detail_page.dart';
import '../../features/seasons/presentation/seasons_page.dart';
import '../../features/sessions/presentation/session_detail_page.dart';
import '../../features/sessions/presentation/session_setup_page.dart';
import '../../features/sessions/presentation/sessions_page.dart';
import '../../features/setups/domain/setups_display.dart';
import '../../features/setups/presentation/setup_detail_page.dart';
import '../../features/setups/presentation/setup_track_page.dart';
import '../../features/setups/presentation/setups_page.dart';
import '../../features/tracks/presentation/track_overview_page.dart';
import '../../features/tracks/presentation/tracks_page.dart';
import '../shell/app_shell.dart';
import 'auth_redirect.dart';

/// 인증 상태 변화에 라우터를 재평가시키는 리스너 + 리다이렉트 가드.
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;

  /// 세션 복원·로그인으로 보낼 때 원래 주소를 `from`으로 지켜 돌아온다(공유 링크·새로고침, [resolveAuthRedirect]).
  String? redirect(BuildContext context, GoRouterState state) {
    final auth = _ref.read(authControllerProvider);
    return resolveAuthRedirect(
      loading: auth.isLoading || !auth.hasValue,
      loggedIn: auth.value != null,
      uri: state.uri,
    );
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
      // 공유 링크 랩(로그인 없음): 셸 밖 화면이고 리다이렉트하지 않는다([isSharePath]). 탭은 `?tab=details|telemetry`.
      _screen(
        '/share/laps/:lapId',
        (state) => SharedLapPage(
          lapId: state.pathParameters['lapId']!,
          tab: state.uri.queryParameters['tab'],
        ),
      ),
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
          // 세션 셋업(세션 상세 Details 카드의 View Setup, F1Laps 셋업 페이지 모양). 뒤로 가기는 그 세션 상세로.
          _screen(
            '/sessions/:sessionId/setup',
            (state) => SessionSetupPage(sessionId: state.pathParameters['sessionId']!),
          ),
          _screen('/laps',(_) => const LapsPage()),
          _screen(
            '/laps/tracks/:trackId',
            (state) => TrackLapsPage(trackId: state.pathParameters['trackId']!),
          ),
          // 랩 상세의 탭은 `?tab=details|telemetry|best`(모르는 값은 details, docs/15 §2.3),
          // 비교 대상·필터는 `?compare=…&compareLapId=…&sameTeam=true…`(docs/15 §10, D-51).
          _screen(
            '/laps/:lapId',
            (state) => LapDetailPage(
              lapId: state.pathParameters['lapId']!,
              tab: state.uri.queryParameters['tab'],
              compare: LapCompareSelection.fromQuery(state.uri.queryParameters),
            ),
          ),
          _screen(
            '/leaderboard',
            (state) => LeaderboardPage(trackId: state.uri.queryParameters['trackId']),
          ),
          // 셋업 모음(F1Laps 상위 셋업). 조건은 `?condition=wet`(그 밖은 Dry).
          _screen(
            kSetupsPath,
            (state) => SetupsPage(condition: state.uri.queryParameters[kSetupConditionQuery]),
          ),
          _screen(
            '$kSetupsPath/:trackId',
            (state) => SetupTrackPage(
              trackId: state.pathParameters['trackId']!,
              condition: state.uri.queryParameters[kSetupConditionQuery],
            ),
          ),
          _screen(
            '$kSetupsPath/:trackId/:setupId',
            (state) => SetupDetailPage(
              trackId: state.pathParameters['trackId']!,
              setupId: state.pathParameters['setupId']!,
            ),
          ),
          // 트랙 목록·트랙 개요(F1Laps Tracks 모양).
          _screen(kTracksPath, (_) => const TracksPage()),
          _screen(
            '$kTracksPath/:trackId',
            (state) => TrackOverviewPage(trackId: state.pathParameters['trackId']!),
          ),
          _screen('/telemetry-app', (_) => const TelemetryAppPage()),
          // 계정 설정(사이드바 하단 프로필에서 연다, docs/14 §8).
          _screen(kSettingsPath, (_) => const SettingsPage()),
        ],
      ),
    ],
  );
});
