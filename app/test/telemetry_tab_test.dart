import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/domain/telemetry_channels.dart';
import 'package:simcenter_app/features/lap_detail/domain/telemetry_math.dart';
import 'package:simcenter_app/features/lap_detail/presentation/telemetry_chart.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

const _telemetryLocation = '/laps/l1?tab=telemetry';
const _channelKeys = ['speed', 'throttle', 'brake', 'gear', 'steer', 'rpm'];

/// 이 랩: 표본 5개(0·5·10·15·20m), 시간 i×100ms, 속도 200+i. 비교 랩: 시간 i×90ms, 속도 300+i.
final _thisTrace = traceOf('l1');
final _bestTrace = traceOf('best', timeAt: (i) => i * 90, speedAt: (i) => 300 + i);

Future<FakeLapDetailRepository> _pump(
  WidgetTester tester, {
  LapDetail? detail,
  Map<String, LapTrace>? traces,
  AppUser? user,
  Size size = const Size(1000, 3000),
}) async {
  final repo = FakeLapDetailRepository(
    details: {'l1': detail ?? sampleDetail()},
    traces: traces ?? {'l1': _thisTrace, 'best': _bestTrace},
  );
  await pumpLapDetail(tester, detailRepo: repo, location: _telemetryLocation, user: user ?? testUser, size: size);
  return repo;
}

Finder _chart(String key) => find.byKey(ValueKey('telemetry-chart-$key'));

Finder _inChart(String key, String text) => find.descendant(of: _chart(key), matching: find.text(text));

/// 그래프 그림(CustomPaint) 영역의 가운데 = 랩 거리 10m(표본 2).
Offset _paintCenter(WidgetTester tester, String key) =>
    tester.getCenter(find.descendant(of: _chart(key), matching: find.byType(CustomPaint)).last);

TelemetryChartPainter _painterOf(WidgetTester tester, String key) => tester
    .widgetList<CustomPaint>(find.descendant(of: _chart(key), matching: find.byType(CustomPaint)))
    .map((p) => p.painter)
    .whereType<TelemetryChartPainter>()
    .single;

void main() {
  group('표시 규칙', () {
    test('채널 값 글자: 속도 단위·퍼센트·기어 N/R·RPM 천 단위', () {
      expect(TelemetryChannel.speed.format(287.4, UnitSystem.metric), '287 km/h');
      expect(TelemetryChannel.speed.format(178.2, UnitSystem.imperial), '178 mph');
      expect(TelemetryChannel.throttle.format(85, UnitSystem.metric), '85%');
      expect(TelemetryChannel.gear.format(0, UnitSystem.metric), 'N');
      expect(TelemetryChannel.gear.format(-1, UnitSystem.metric), 'R');
      expect(TelemetryChannel.gear.format(7, UnitSystem.metric), '7');
      expect(TelemetryChannel.steer.format(-34, UnitSystem.metric), '-34');
      expect(TelemetryChannel.rpm.format(11500, UnitSystem.metric), '11,500');
    });

    test('Imperial이면 속도 값을 mph로 바꾼다', () {
      expect(TelemetryChannel.speed.valuesOf(_thisTrace, UnitSystem.imperial).first, closeTo(124.27, 0.01));
      expect(TelemetryChannel.speed.valuesOf(_thisTrace, UnitSystem.metric).first, 200);
    });

    test('세로축: 스로틀 0~100, 스티어 −100~100, 기어 −1~8, 속도는 0~최댓값', () {
      expect(TelemetryChannel.throttle.rangeOf([10]).max, 100);
      expect(TelemetryChannel.steer.rangeOf([10]).min, -100);
      expect(TelemetryChannel.gear.rangeOf([3]).max, 8);
      final speed = TelemetryChannel.speed.rangeOf([120, 310]);
      expect(speed.min, 0);
      expect(speed.max, 310);
    });

    test('Delta·거리 글자', () {
      expect(formatDeltaSeconds(0.02), '+0.020s');
      expect(formatDeltaSeconds(-0.1234), '-0.123s');
      expect(formatDeltaSeconds(0.0001), '0.000s');
      expect(formatDistance(1234.6), '1,235 m');
    });

    test('seriesSegments는 값이 없는 칸에서 선을 끊고 점 하나짜리 조각은 버린다', () {
      const geometry = ChartGeometry(width: 40, height: 10, maxDistanceM: 40, range: ValueRange(0, 10));
      const series = ChartSeries(values: [1, 2, null, 3, null, 4, 5], resolutionM: 5, color: AppColors.accent);

      final segments = seriesSegments(series, geometry);

      expect(segments, hasLength(2));
      expect(segments.first, [const Offset(0, 9), const Offset(5, 8)]);
      expect(segments.last.first, const Offset(25, 6));
    });
  });

  group('Telemetry 탭', () {
    testWidgets('랩에 트레이스가 없으면(hasTrace=false) 요청 없이 안내를 보인다', (t) async {
      final repo = await _pump(t, detail: sampleDetail(lap: sampleLap(hasTrace: false)));

      expect(find.text('이 랩은 텔레메트리가 저장되지 않았어요(새 Agent로 달린 랩부터 저장돼요)'), findsOneWidget);
      expect(repo.traceRequests, isEmpty);
    });

    testWidgets('트레이스 조회가 404(없음)여도 같은 안내', (t) async {
      await _pump(t, traces: const {});

      expect(find.textContaining('텔레메트리가 저장되지 않았어요'), findsOneWidget);
      expect(_chart('speed'), findsNothing);
    });

    testWidgets('Speed · Throttle · Brake · Gear · Steering · RPM을 위에서부터 쌓고, 비교 랩 트레이스가 있으면 맨 위에 Delta', (t) async {
      final repo = await _pump(t);

      expect(repo.traceRequests, ['l1']);
      expect(repo.comparisonTraceRequests, ['best']); // 비교 랩은 공개 규칙 경로(/laps/{id}/trace, D-51)
      final keys = ['delta', ..._channelKeys];
      for (var i = 1; i < keys.length; i++) {
        expect(t.getTopLeft(_chart(keys[i - 1])).dy, lessThan(t.getTopLeft(_chart(keys[i])).dy), reason: keys[i]);
      }
      for (final title in ['Delta', 'Speed', 'Throttle', 'Brake', 'Gear', 'Steering', 'RPM']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('범례에 두 랩의 랩타임, 선 색은 이 랩 강조색·비교 랩 청록', (t) async {
      await _pump(t);

      expect(find.text('이 랩 1:38.448'), findsOneWidget);
      expect(find.text('내 최고 랩 1:38.000'), findsOneWidget);
      final painter = _painterOf(t, 'speed');
      expect(painter.series.map((s) => s.color), [AppColors.accent, t.element(_chart('speed')).palette.comparison]);
    });

    testWidgets('비교 랩에 트레이스가 없거나 비교 대상이 이 랩이면 Delta·비교 선이 없다', (t) async {
      await _pump(t, detail: sampleDetail(comparison: sampleComparison(hasTrace: false)));
      expect(_chart('delta'), findsNothing);
      expect(_painterOf(t, 'speed').series, hasLength(1));
      expect(find.textContaining('내 최고 랩'), findsNothing);

      await _pump(t, detail: sampleDetail(comparison: sampleComparison(id: 'l1')));
      expect(_chart('delta'), findsNothing);
      expect(_painterOf(t, 'speed').series, hasLength(1));
    });

    testWidgets('그래프를 누르면 모든 그래프에 같은 거리의 십자선과 두 랩의 값이 보인다', (t) async {
      await _pump(t);
      expect(_inChart('speed', '202 km/h'), findsNothing);

      await t.tapAt(_paintCenter(t, 'speed'));
      await t.pump();

      expect(find.byKey(const ValueKey('telemetry-cursor-distance')), findsOneWidget);
      expect(find.text('10 m'), findsOneWidget);
      expect(_inChart('speed', '202 km/h'), findsOneWidget);
      expect(_inChart('speed', '302 km/h'), findsOneWidget);
      expect(_inChart('throttle', '52%'), findsNWidgets(2)); // 두 랩 모두 50+i.
      expect(_inChart('brake', '2%'), findsNWidgets(2));
      expect(_inChart('gear', '6'), findsNWidgets(2));
      expect(_inChart('steer', '-2'), findsNWidgets(2));
      expect(_inChart('rpm', '11,002'), findsNWidgets(2));
      expect(_inChart('delta', '+0.020s'), findsOneWidget); // 200ms − 180ms.
      for (final key in ['delta', ..._channelKeys]) {
        expect(_painterOf(t, key).cursor.value, 10, reason: key);
      }
    });

    testWidgets('마우스를 올리면 십자선이 따라오고, 그래프 밖으로 나가면 사라진다', (t) async {
      await _pump(t);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(_paintCenter(t, 'rpm'));
      await t.pump();
      expect(_inChart('speed', '202 km/h'), findsOneWidget);

      await mouse.moveTo(const Offset(1, 1));
      await t.pump();
      expect(_inChart('speed', '202 km/h'), findsNothing);
      expect(find.byKey(const ValueKey('telemetry-cursor-distance')), findsNothing);
    });

    testWidgets('사용자 단위가 Imperial이면 속도를 mph로 보인다', (t) async {
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

      await t.tapAt(_paintCenter(t, 'speed'));
      await t.pump();

      expect(_inChart('speed', '126 mph'), findsOneWidget); // 202 km/h.
      expect(_inChart('speed', '188 mph'), findsOneWidget); // 302 km/h.
    });

    testWidgets('375px에서 십자선 값이 보여도 넘치지 않는다', (t) async {
      await _pump(t, size: const Size(375, 3000));

      await t.tapAt(_paintCenter(t, 'rpm'));
      await t.pump();

      expect(t.takeException(), isNull);
      expect(_inChart('rpm', '11,002'), findsNWidgets(2));
    });
  });
}
