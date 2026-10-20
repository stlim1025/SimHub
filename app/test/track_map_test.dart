import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/domain/track_map.dart';
import 'package:simcenter_app/features/lap_detail/presentation/track_map.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

const _telemetryLocation = '/laps/l1?tab=telemetry';
const _noPositionsText = '트랙 모양은 위치 데이터가 있는 랩부터 보여요';

/// 표본 5개(0·5·10·15·20m)가 정사각형 둘레를 도는 트레이스: (0,0) → (100,0) → (100,100) → (0,100) → (0,0).
LapTrace _positionedTrace(String lapId) {
  final base = traceOf(lapId);
  return LapTrace(
    lapId: lapId,
    resolutionM: base.resolutionM,
    timeMs: base.timeMs,
    speedKph: base.speedKph,
    throttle: base.throttle,
    brake: base.brake,
    steer: base.steer,
    gear: base.gear,
    rpm: base.rpm,
    worldPosX: const [0, 100, 100, 0, 0],
    worldPosZ: const [0, 0, 100, 100, 0],
  );
}

Finder get _mapPaint => find.byKey(const ValueKey('track-map'));

TrackMapPainter _painter(WidgetTester tester) => tester.widget<CustomPaint>(_mapPaint).painter! as TrackMapPainter;

void main() {
  group('TrackProjection', () {
    test('가로세로 비율을 지키며 가운데 놓고, Z가 클수록 위(화면 y −Z)', () {
      // 폭 200 × 높이 100 트랙을 300 × 300 상자(여백 0)에: 배율 1.5, 세로 가운데(위아래 75 여백).
      final projection = TrackProjection.fit(xs: const [0, 200], zs: const [0, 100], width: 300, height: 300);

      expect(projection.project(0, 0), const Offset(0, 225));
      expect(projection.project(200, 0), const Offset(300, 225));
      expect(projection.project(0, 100), const Offset(0, 75));
    });

    test('여백(padding) 안쪽에 맞춘다', () {
      final projection =
          TrackProjection.fit(xs: const [0, 100], zs: const [0, 100], width: 120, height: 120, padding: 10);

      expect(projection.project(0, 100), const Offset(10, 10));
      expect(projection.project(100, 0), const Offset(110, 110));
    });

    test('한 점뿐이어도 0으로 나누지 않는다', () {
      final projection = TrackProjection.fit(xs: const [5], zs: const [5], width: 100, height: 100);

      expect(projection.project(5, 5).dx.isFinite, isTrue);
    });
  });

  group('섹터 나누기', () {
    const sectors = [
      LapSector(sectorNumber: 1, sectorTimeMs: 1000),
      LapSector(sectorNumber: 2, sectorTimeMs: 500),
      LapSector(sectorNumber: 3, sectorTimeMs: 700),
    ];

    test('sectorIndexesOf: 랩 시간 < S1 → 0, < S1+S2 → 1, 그 밖 → 2', () {
      expect(sectorIndexesOf(const [0, 999, 1000, 1499, 1500, 2100], sectors), [0, 0, 1, 1, 2, 2]);
    });

    test('sectorIndexesOf: S1·S2를 모르면 null', () {
      expect(sectorIndexesOf(const [0, 100], const []), isNull);
      expect(sectorIndexesOf(const [0, 100], const [LapSector(sectorNumber: 1, sectorTimeMs: 1000)]), isNull);
    });

    test('trackSegments: 섹터가 바뀌는 곳에서 나누고 경계 점을 공유한다', () {
      const points = [Offset(0, 0), Offset(1, 0), Offset(2, 0), Offset(3, 0), Offset(4, 0), Offset(5, 0)];

      final segments = trackSegments(points, const [0, 0, 1, 1, 2, 2]);

      expect(segments.map((s) => s.sector), [0, 1, 2]);
      expect(segments[0].points, [const Offset(0, 0), const Offset(1, 0), const Offset(2, 0)]);
      expect(segments[1].points, [const Offset(2, 0), const Offset(3, 0), const Offset(4, 0)]);
      expect(segments[2].points, [const Offset(4, 0), const Offset(5, 0)]);
    });

    test('trackSegments: 섹터를 모르면 조각 하나, 점이 둘 미만이면 없음', () {
      const points = [Offset(0, 0), Offset(1, 0), Offset(2, 0)];

      expect(trackSegments(points, null).single.points, points);
      expect(trackSegments(const [Offset(0, 0)], null), isEmpty);
    });
  });

  test('lapTelemetryStatsOf: 최고·평균 속도(거리 ÷ 시간), 평균 스로틀·브레이크', () {
    // 20m를 0.4초 → 50 m/s = 180 km/h. 속도 200~204, 스로틀 50~54, 브레이크 0~4.
    final stats = lapTelemetryStatsOf(traceOf('l1'));

    expect(stats.topSpeedKph, 204);
    expect(stats.averageSpeedKph, closeTo(180, 0.001));
    expect(stats.averageThrottle, 52);
    expect(stats.averageBrake, 2);
  });

  group('TrackMap 위젯', () {
    Future<ValueNotifier<double?>> pumpMap(WidgetTester tester) async {
      final cursor = ValueNotifier<double?>(null);
      addTearDown(cursor.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: TrackMap(trace: _positionedTrace('l1'), sectors: sampleLap().sectors, cursor: cursor),
          ),
        ),
      ));
      return cursor;
    }

    testWidgets('커서가 없으면 점이 없고, 커서 거리가 바뀌면 그 표본 위치로 점이 옮겨 간다', (t) async {
      final cursor = await pumpMap(t);
      final size = t.getSize(_mapPaint);

      expect(_painter(t).dotOffset(size), isNull);

      cursor.value = 0; // 표본 0 = (0, 0) → 왼쪽 아래
      await t.pump();
      final start = _painter(t).dotOffset(size)!;

      cursor.value = 10; // 표본 2 = (100, 100) → 오른쪽 위
      await t.pump();
      final corner = _painter(t).dotOffset(size)!;

      expect(corner.dx, greaterThan(start.dx));
      expect(corner.dy, lessThan(start.dy));
      expect(find.text('Sector 1'), findsOneWidget);
    });
  });

  group('Telemetry 탭의 트랙 지도', () {
    Future<void> pump(WidgetTester tester, LapTrace trace, {Size size = const Size(1000, 3000)}) => pumpLapDetail(
          tester,
          detailRepo: FakeLapDetailRepository(
            details: {'l1': sampleDetail()},
            traces: {'l1': trace, 'best': traceOf('best')},
          ),
          location: _telemetryLocation,
          user: testUser,
          size: size,
        );

    testWidgets('위치가 있으면 Track 카드와 Lap Telemetry 통계를 나란히 보인다', (t) async {
      await pump(t, _positionedTrace('l1'));

      expect(find.byKey(const ValueKey('track-map-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('lap-telemetry-stats')), findsOneWidget);
      expect(find.text('Top Speed'), findsOneWidget);
      expect(find.text('204 km/h'), findsOneWidget);
      expect(find.text(_noPositionsText), findsNothing);
      final map = t.getRect(find.byKey(const ValueKey('track-map-card')));
      final stats = t.getRect(find.byKey(const ValueKey('lap-telemetry-stats')));
      expect(map.right, lessThanOrEqualTo(stats.left)); // 넓은 화면은 나란히
    });

    testWidgets('그래프에 마우스를 올리면 트랙 지도 점도 같은 거리로 움직인다', (t) async {
      await pump(t, _positionedTrace('l1'));
      final size = t.getSize(_mapPaint);
      expect(_painter(t).dotOffset(size), isNull);

      final speed = find.byKey(const ValueKey('telemetry-chart-speed'));
      final chartPaint = find.descendant(of: speed, matching: find.byType(CustomPaint)).last;
      await t.ensureVisible(chartPaint);
      await t.pumpAndSettle();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(chartPaint));
      await t.pump();

      expect(_painter(t).dotOffset(size), isNotNull);
    });

    testWidgets('좁은 화면이면 Track 카드 아래에 통계를 쌓는다', (t) async {
      await pump(t, _positionedTrace('l1'), size: const Size(500, 3000));

      final map = t.getRect(find.byKey(const ValueKey('track-map-card')));
      final stats = t.getRect(find.byKey(const ValueKey('lap-telemetry-stats')));
      expect(map.bottom, lessThanOrEqualTo(stats.top));
    });

    testWidgets('위치가 없는 옛 랩은 지도 없이 통계와 안내만', (t) async {
      await pump(t, traceOf('l1'));

      expect(find.byKey(const ValueKey('track-map-card')), findsNothing);
      expect(_mapPaint, findsNothing);
      expect(find.byKey(const ValueKey('lap-telemetry-stats')), findsOneWidget);
      expect(find.text(_noPositionsText), findsOneWidget);
      expect(find.byKey(const ValueKey('telemetry-chart-speed')), findsOneWidget);
    });
  });
}
