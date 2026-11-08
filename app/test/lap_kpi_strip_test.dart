import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_compare.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_display.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/lap_kpi_strip.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

const _strip = ValueKey('lap-kpi-strip');

Finder _cell(String key) => find.byKey(ValueKey('lap-kpi-$key'));

Finder _inCell(String key, String text) => find.descendant(of: _cell(key), matching: find.text(text));

Color? _colorIn(WidgetTester tester, String key, String text) => tester.widget<Text>(_inCell(key, text)).style?.color;

Future<FakeLapDetailRepository> _pump(
  WidgetTester tester, {
  LapDetail? detail,
  Map<String, LapTrace>? traces,
  String location = '/laps/l1',
  Size size = const Size(1000, 3000),
  AppUser? user = testUser,
}) async {
  final repo = FakeLapDetailRepository(
    details: {'l1': detail ?? sampleDetail()},
    traces: traces ?? {'l1': traceOf('l1')},
  );
  await pumpLapDetail(tester, detailRepo: repo, location: location, size: size, user: user);
  return repo;
}

void main() {
  test('kpiGridColumns: 들어가는 칸 수로 줄마다 고르게 나눈다', () {
    expect(kpiGridColumns(299, 6), 3); // 375px 화면: 3열 × 2줄
    expect(kpiGridColumns(500, 6), 3); // 5칸이 들어가도 3 + 3
    expect(kpiGridColumns(620, 6), 6); // 한 줄
    expect(kpiGridColumns(500, 5), 5); // 비교 안 함(5칸)이면 한 줄
    expect(kpiGridColumns(400, 5), 3); // 4칸이 들어가도 3 + 2
    expect(kpiGridColumns(150, 6), 1);
    expect(kpiGridColumns(40, 6), 1);
    expect(kpiGridColumns(300, 0), 1);
  });

  for (final tab in ['details', 'telemetry', 'analysis', 'best']) {
    testWidgets('$tab 탭에서도 머리줄과 탭 막대 사이에 KPI 띠가 있다', (t) async {
      await _pump(t, location: '/laps/l1?tab=$tab');

      expect(find.byKey(_strip), findsOneWidget);
      expect(t.getTopLeft(find.text('Jeddah Lap 1:38.448')).dy, lessThan(t.getTopLeft(find.byKey(_strip)).dy));
      expect(t.getBottomLeft(find.byKey(_strip)).dy, lessThan(t.getTopLeft(find.byType(TabBar)).dy));
    });
  }

  testWidgets('랩 정체 · vs PB 차이 · 섹터(차이 색) · 최고 속도 · 타이어(컴파운드 · 사용 랩 · 평균 마모)', (t) async {
    // 이 랩 98.448(31.000 · 33.448 · 34.000) vs 최고 98.000(30.500 · 33.300 · 34.200), Soft 3랩, 마모 평균 38.25%.
    await _pump(t);
    final palette = t.element(find.byKey(_strip)).palette;

    expect(find.descendant(of: find.byKey(_strip), matching: find.text('Jeddah · Time Trial L5')), findsOneWidget);
    expect(t.widget<Text>(_cell('lap-time')).data, '1:38.448');
    expect(_inCell('compare', 'VS PB'), findsOneWidget);
    expect(_colorIn(t, 'compare', '+0.448'), palette.danger);
    expect(_inCell('compare', '1:38.000'), findsOneWidget);
    for (final (n, time, delta, color) in [
      (1, '31.000', '+0.500', palette.danger),
      (2, '33.448', '+0.148', palette.danger),
      (3, '34.000', '-0.200', palette.success),
    ]) {
      expect(_inCell('sector-$n', 'S$n'), findsOneWidget);
      expect(_inCell('sector-$n', time), findsOneWidget, reason: 'S$n');
      expect(_colorIn(t, 'sector-$n', delta), color, reason: 'S$n');
    }
    expect(_inCell('top-speed', 'TOP SPEED'), findsOneWidget);
    expect(_inCell('top-speed', '204'), findsOneWidget);
    expect(_inCell('top-speed', 'km/h'), findsOneWidget);
    expect(_inCell('tyre', 'TYRE'), findsOneWidget);
    expect(find.descendant(of: _cell('tyre-badge'), matching: find.text('S')), findsOneWidget);
    expect(_inCell('tyre', '3랩 · 38%'), findsOneWidget);
  });

  testWidgets('트레이스가 없는 랩은 요청 없이 최고 속도 —', (t) async {
    final repo = await _pump(t, detail: sampleDetail(lap: sampleLap(hasTrace: false)));

    expect(_inCell('top-speed', '—'), findsOneWidget);
    expect(_inCell('top-speed', 'km/h'), findsNothing);
    expect(repo.traceRequests, isEmpty);
  });

  testWidgets('트레이스 조회가 404(없음)여도 최고 속도 —', (t) async {
    await _pump(t, traces: const {});

    expect(_inCell('top-speed', '—'), findsOneWidget);
  });

  testWidgets('사용자 단위가 Imperial이면 최고 속도를 mph로', (t) async {
    const imperial = AppUser(
      userId: 'u1',
      displayName: '홍길동',
      preferences: UserPreferences(
        showOnLeaderboard: true,
        avatarTeam: null,
        preferredGame: 'F1_25',
        controller: ControllerType.wheel,
        console: ConsolePlatform.pc,
        units: UnitSystem.imperial,
        timeZoneId: 'Asia/Seoul',
        theme: ThemePreference.dark,
      ),
    );
    await _pump(t, user: imperial);

    expect(_inCell('top-speed', '127'), findsOneWidget); // 204 km/h
    expect(_inCell('top-speed', 'mph'), findsOneWidget);
  });

  testWidgets('이 랩이 내 최고면 랩타임이 보라색이고 비교 칸은 0.000 · 이 랩이 PB(섹터 차이 없음)', (t) async {
    await _pump(t, detail: sampleDetail(comparison: sampleComparison(id: 'l1')));

    expect(t.widget<Text>(_cell('lap-time')).style?.color, AppColors.fastestLap);
    expect(_colorIn(t, 'compare', '0.000'), AppColors.fastestLap);
    expect(_inCell('compare', '이 랩이 PB'), findsOneWidget);
    expect(_inCell('sector-1', '+0.500'), findsNothing);
  });

  testWidgets('비교 안 함이면 비교 칸이 없다', (t) async {
    await _pump(t, location: '/laps/l1?compare=none');

    expect(find.byKey(_strip), findsOneWidget);
    expect(_cell('compare'), findsNothing);
    expect(_inCell('sector-1', '31.000'), findsOneWidget);
  });

  testWidgets('비교할 랩이 없으면 — · 비교 랩 없음', (t) async {
    await _pump(t, detail: sampleDetail(withComparison: false));

    expect(_inCell('compare', '—'), findsOneWidget);
    expect(_inCell('compare', '비교 랩 없음'), findsOneWidget);
  });

  testWidgets('같은 세션의 다른 차와 비교하면 vs 드라이버 · 그 차 랩타임과의 차이, 섹터 차이는 없다', (t) async {
    final location = lapDetailLocation('l1', compare: const LapCompareSelection.car(
      sessionId: '0190a000-0000-7000-8000-000000000001',
      carIndex: 3,
      name: 'Verstappen',
      lapTimeMs: 98100,
    ));
    await _pump(t, location: location);

    expect(_inCell('compare', 'VS VERSTAPPEN'), findsOneWidget);
    expect(_inCell('compare', '+0.348'), findsOneWidget);
    expect(_inCell('compare', '1:38.100'), findsOneWidget);
    expect(_inCell('sector-1', '+0.500'), findsNothing);
  });

  testWidgets('넓으면 랩 정체와 칸이 한 줄에 놓인다', (t) async {
    await _pump(t, size: const Size(1400, 3000));

    final top = t.getTopLeft(_cell('compare')).dy;
    for (final key in ['sector-1', 'sector-2', 'sector-3', 'top-speed', 'tyre']) {
      expect(t.getTopLeft(_cell(key)).dy, top, reason: key);
    }
    expect(t.getTopLeft(_cell('identity')).dx, lessThan(t.getTopLeft(_cell('compare')).dx));
  });

  testWidgets('375px에서는 랩 정체 아래로 칸이 3열 × 2줄로 흐르고 넘치지 않는다', (t) async {
    await _pump(t, size: const Size(375, 3000));

    expect(t.takeException(), isNull);
    final identityBottom = t.getBottomLeft(_cell('identity')).dy;
    for (final key in ['compare', 'sector-1', 'sector-2', 'sector-3', 'top-speed', 'tyre']) {
      expect(t.getTopLeft(_cell(key)).dy, greaterThan(identityBottom), reason: key);
    }
    final firstRow = t.getTopLeft(_cell('compare')).dy;
    expect(t.getTopLeft(_cell('sector-2')).dy, firstRow);
    expect(t.getTopLeft(_cell('sector-3')).dy, greaterThan(firstRow));
    expect(t.getTopLeft(_cell('sector-3')).dx, t.getTopLeft(_cell('compare')).dx);
    expect(t.getRect(find.byKey(_strip)).right, lessThanOrEqualTo(375));
  });
}
