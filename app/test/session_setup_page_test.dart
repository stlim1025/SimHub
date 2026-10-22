import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';
import 'package:simcenter_app/features/sessions/presentation/session_setup_page.dart';
import 'package:simcenter_app/features/sessions/presentation/setup_sections.dart';

import 'support/fakes.dart';

const _ferrari = LapTeam(name: 'Ferrari', color: '#E8002D');

/// 항상 404로 실패하는 저장소.
class _NotFoundRepository extends FakeSessionsRepository {
  @override
  Future<SessionDetail> getMySession(String sessionId) async =>
      throw ApiException('없음', statusCode: 404);
}

SessionDetail _withSetup({Map<String, Object?>? setup, String? weather = 'Clear'}) => detailOf(
      'd1',
      trackName: 'Bahrain',
      countryCode: 'BH',
      sessionType: 'Qualifying',
      sessionKind: 'Qualifying3',
      myTeam: _ferrari,
      weather: weather,
      myBestLap: const SessionBestLap(lapId: 'lap-9', lapTimeMs: 90088),
      setup: setup,
    );

const Map<String, Object?> _fullSetup = {
  'frontWing': 10,
  'rearWing': 8,
  'onThrottle': 50,
  'offThrottle': 55,
  'engineBraking': 60,
  'frontCamber': -3.5,
  'rearCamber': -2,
  'frontToe': 0.05,
  'rearToe': 0.2,
  'frontSuspension': 41,
  'rearSuspension': 3,
  'frontAntiRollBar': 10,
  'rearAntiRollBar': 1,
  'frontSuspensionHeight': 25,
  'rearSuspensionHeight': 50,
  'brakePressure': 100,
  'brakeBias': 56,
  'tyrePressureFL': 22.5,
  'tyrePressureFR': 22.5,
  'tyrePressureRL': 20.7,
  'tyrePressureRR': 20.7,
  'fuelLoad': 8.5,
  'ballast': 6,
  'mystery': 3,
};

Future<GoRouter> _pumpPage(
  WidgetTester tester,
  SessionsRepository repo, {
  Size size = const Size(1400, 3000),
  ThemeData? theme,
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: '/sessions/d1/setup', routes: [
    GoRoute(path: '/sessions', builder: (_, _) => const Text('sessions-list')),
    GoRoute(path: '/sessions/:sessionId', builder: (_, state) => Text('session:${state.pathParameters['sessionId']}')),
    GoRoute(
      path: '/sessions/:sessionId/setup',
      builder: (_, state) => Scaffold(body: SessionSetupPage(sessionId: state.pathParameters['sessionId']!)),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [sessionsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(theme: theme, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

FakeSessionsRepository _repo(SessionDetail detail) => FakeSessionsRepository(details: {'d1': detail});

String _location(GoRouter router) => router.routeInformationProvider.value.uri.toString();

Finder _group(String title) => find.byKey(ValueKey('setup-group-$title'));

Finder _inGroup(String title, String text) => find.descendant(of: _group(title), matching: find.text(text));

Offset _groupTopLeft(WidgetTester t, String title) => t.getTopLeft(_group(title));

void main() {
  group('SessionSetupPage', () {
    testWidgets('제목은 "{트랙} Setup ({날씨})", 요약 줄에 팀·세션·랩 타임·날씨·날짜', (t) async {
      await _pumpPage(t, _repo(_withSetup(setup: _fullSetup)));

      expect(find.text('Bahrain Setup (Clear)'), findsOneWidget);
      expect(find.byKey(const ValueKey('track-flag-BH')), findsOneWidget);
      Finder meta(String label, String value) =>
          find.descendant(of: find.byKey(ValueKey('setup-meta-$label')), matching: find.text(value));
      expect(meta('Team', 'Ferrari'), findsOneWidget);
      expect(meta('Session', 'Qualifying 3'), findsOneWidget);
      expect(meta('Lap Time', '1:30.088'), findsOneWidget);
      expect(meta('Conditions', 'Clear'), findsOneWidget);
      expect(find.byKey(const ValueKey('setup-meta-Date')), findsOneWidget);
    });

    testWidgets('묶음별 카드에 이름표·값(단위 포함), 모르는 키는 Other', (t) async {
      await _pumpPage(t, _repo(_withSetup(setup: _fullSetup)));

      for (final title in ['Aerodynamics', 'Transmission', 'Suspension Geometry', 'Suspension', 'Brakes', 'Tyres', 'Fuel', 'Other']) {
        expect(_group(title), findsOneWidget, reason: title);
      }
      expect(_inGroup('Aerodynamics', 'Front Wing Aero'), findsOneWidget);
      expect(_inGroup('Aerodynamics', '10'), findsOneWidget);
      expect(_inGroup('Transmission', '55%'), findsOneWidget);
      expect(_inGroup('Suspension Geometry', '-3.5°'), findsOneWidget);
      expect(_inGroup('Suspension', 'Front Ride Height'), findsOneWidget);
      expect(_inGroup('Brakes', '56%'), findsOneWidget);
      expect(_inGroup('Tyres', '22.5 psi'), findsNWidgets(2));
      expect(_inGroup('Fuel', '8.5 kg'), findsOneWidget);
      expect(_inGroup('Other', 'mystery'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('넓으면 3열, 중간 2열, 좁으면 1열', (t) async {
      await _pumpPage(t, _repo(_withSetup(setup: _fullSetup)), size: const Size(1400, 3000));
      expect(_groupTopLeft(t, 'Transmission').dy, _groupTopLeft(t, 'Aerodynamics').dy);
      expect(_groupTopLeft(t, 'Suspension Geometry').dy, _groupTopLeft(t, 'Aerodynamics').dy);
      expect(_groupTopLeft(t, 'Suspension').dy, greaterThan(_groupTopLeft(t, 'Aerodynamics').dy));

      await _pumpPage(t, _repo(_withSetup(setup: _fullSetup)), size: const Size(900, 4000));
      expect(_groupTopLeft(t, 'Transmission').dy, _groupTopLeft(t, 'Aerodynamics').dy);
      expect(_groupTopLeft(t, 'Suspension Geometry').dy, greaterThan(_groupTopLeft(t, 'Aerodynamics').dy));

      await _pumpPage(t, _repo(_withSetup(setup: _fullSetup)), size: const Size(500, 6000));
      expect(_groupTopLeft(t, 'Transmission').dy, greaterThan(_groupTopLeft(t, 'Aerodynamics').dy));
    });

    testWidgets('날씨를 모르면 제목에 괄호가 없다', (t) async {
      await _pumpPage(t, _repo(_withSetup(setup: _fullSetup, weather: null)));

      expect(find.text('Bahrain Setup'), findsOneWidget);
    });

    testWidgets('셋업이 없으면 빈 상태 + 세션 결과로 가는 링크', (t) async {
      final router = await _pumpPage(t, _repo(_withSetup()));

      expect(find.text('이 세션에는 저장된 셋업이 없어요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('setup-group-Aerodynamics')), findsNothing);

      await t.tap(find.text('세션 결과로'));
      await t.pumpAndSettle();
      expect(_location(router), '/sessions/d1');
    });

    testWidgets('← 를 누르면 세션 상세로 돌아간다', (t) async {
      final router = await _pumpPage(t, _repo(_withSetup(setup: _fullSetup)));

      await t.tap(find.byTooltip('세션 결과'));
      await t.pumpAndSettle();
      expect(_location(router), '/sessions/d1');
    });

    testWidgets('없는 세션이면 404 상태', (t) async {
      await _pumpPage(t, _NotFoundRepository());

      expect(find.text('찾을 수 없는 세션입니다.'), findsOneWidget);
    });

    for (final light in [false, true]) {
      testWidgets('375px에서 넘치지 않는다(${light ? 'light' : 'dark'})', (t) async {
        final theme = light ? AppTheme.light : AppTheme.dark;
        await _pumpPage(t, _repo(_withSetup(setup: _fullSetup)), size: const Size(375, 8000), theme: theme);
        expect(t.takeException(), isNull);
      });
    }
  });

  test('setupGridColumns: 폭에 따른 열 수', () {
    expect(setupGridColumns(kSetupThreeColumnWidth), 3);
    expect(setupGridColumns(kSetupTwoColumnWidth), 2);
    expect(setupGridColumns(kSetupTwoColumnWidth - 1), 1);
  });
}
