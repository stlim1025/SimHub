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

Finder _paint(String key) => find.descendant(of: _chart(key), matching: find.byType(CustomPaint)).last;

/// 그래프의 그림 영역(축 글자 칸 제외, 화면 좌표).
Rect _plotRect(WidgetTester tester, String key) =>
    telemetryPlotRect(tester.getSize(_paint(key))).shift(tester.getTopLeft(_paint(key)));

/// 그림 영역의 가운데 = 랩 거리 10m(표본 2).
Offset _paintCenter(WidgetTester tester, String key) => _plotRect(tester, key).center;

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
      expect(TelemetryChannel.ers.format(2.512, UnitSystem.metric), '2.51 MJ');
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

    test('세로축 눈금 글자: 천 단위·간격만큼 소수, 기어는 R·N', () {
      expect(formatAxisValue(12000, 2000), '12,000');
      expect(formatAxisValue(-0.2, 0.2), '-0.2');
      expect(formatAxisValue(0, 0.25), '0.00');
      expect(gearAxisLabel(0, 1), 'N');
      expect(gearAxisLabel(-1, 1), 'R');
      expect(gearAxisLabel(4, 2), '4');
      expect(TelemetryChannel.gear.axisLabel, gearAxisLabel);
      expect(TelemetryChannel.speed.axisLabel, formatAxisValue);
    });

    test('그래프 눈금: 높이·폭에 맞춰 글자가 겹치지 않는 간격', () {
      // 그림 높이 110 → 눈금 7개까지: 속도 0~330은 50 간격, 스로틀 0~100은 20 간격, 스티어 −100~100은 50 간격.
      expect(telemetryYTicks(const ValueRange(0, 330), kTelemetryChartHeight), [0, 50, 100, 150, 200, 250, 300]);
      expect(telemetryYTicks(const ValueRange(0, 100), kTelemetryChartHeight), [0, 20, 40, 60, 80, 100]);
      expect(telemetryYTicks(const ValueRange(-100, 100), kTelemetryChartHeight), [-100, -50, 0, 50, 100]);
      // 폭 900px → 눈금 15개까지: 5,300m 랩은 500m 간격. 폭 300px → 5개까지: 2,000m 간격.
      expect(telemetryXTicks(5300, 900).take(3), [0, 500, 1000]);
      expect(telemetryXTicks(5300, 900).last, 5000);
      expect(telemetryXTicks(5300, 300), [0, 2000, 4000]);
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

    testWidgets('ERS 배터리 잔량 채널이 있으면 RPM 아래에 MJ 단위 ERS Energy 그래프, 없으면 그리지 않는다', (t) async {
      final base = traceOf('l1');
      final withErs = LapTrace(
        lapId: base.lapId,
        resolutionM: base.resolutionM,
        timeMs: base.timeMs,
        speedKph: base.speedKph,
        throttle: base.throttle,
        brake: base.brake,
        steer: base.steer,
        gear: base.gear,
        rpm: base.rpm,
        ersStoreJ: [for (var i = 0; i < base.length; i++) 3000000 - i * 250000.0],
      );
      await _pump(t, traces: {'l1': withErs, 'best': _bestTrace});

      expect(find.text('ERS Energy'), findsOneWidget);
      expect(t.getTopLeft(_chart('rpm')).dy, lessThan(t.getTopLeft(_chart('ers')).dy));
      final painter = _painterOf(t, 'ers');
      expect(painter.series, hasLength(1)); // 비교 랩에는 ERS 채널이 없어 이 랩 선만
      expect(painter.series.single.values.first, 3);
    });

    testWidgets('ERS 채널이 없는 랩이면 ERS Energy 그래프가 없다', (t) async {
      await _pump(t);

      expect(_chart('ers'), findsNothing);
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

    testWidgets('그림 영역 왼쪽 끝 = 0m, 오른쪽 끝 = 랩 끝(축 칸을 빼고 거리를 잰다)', (t) async {
      await _pump(t);
      final plot = _plotRect(t, 'speed');
      expect(plot.left, greaterThan(t.getTopLeft(_paint('speed')).dx)); // 왼쪽에 값 눈금 칸

      await t.tapAt(Offset(plot.left, plot.center.dy));
      await t.pump();
      expect(_painterOf(t, 'speed').cursor.value, 0);

      await t.tapAt(Offset(plot.right - 1, plot.center.dy));
      await t.pump();
      expect(_painterOf(t, 'speed').cursor.value, closeTo(20, 0.1));
    });

    testWidgets('모든 그래프에 축(값 눈금·거리 눈금)을 그리고 기어 축은 R·N 글자를 쓴다', (t) async {
      await _pump(t);

      for (final key in ['delta', ..._channelKeys]) {
        final axes = t
            .widgetList<CustomPaint>(find.descendant(of: _chart(key), matching: find.byType(CustomPaint)))
            .map((p) => p.painter)
            .whereType<TelemetryAxesPainter>()
            .single;
        expect(axes.maxDistanceM, 20, reason: key);
      }
      final gearAxes = t
          .widgetList<CustomPaint>(find.descendant(of: _chart('gear'), matching: find.byType(CustomPaint)))
          .map((p) => p.painter)
          .whereType<TelemetryAxesPainter>()
          .single;
      expect(gearAxes.axisLabel, gearAxisLabel);
      expect(t.takeException(), isNull);
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
