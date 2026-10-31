import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/layout/viewport_pinned.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_corners.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/domain/track_map.dart';
import 'package:simcenter_app/features/lap_detail/presentation/telemetry_tab.dart';
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

/// 페이지(탭을 담은 ListView)의 스크롤 위치.
ScrollPosition _pageScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.ancestor(of: find.byKey(const ValueKey('telemetry-chart-speed')), matching: find.byType(Scrollable)).first,
    )
    .position;

void main() {
  group('TrackProjection', () {
    test('가로세로 비율을 지키며 가운데 놓고, Z가 클수록 아래(화면 y +Z, 좌우 뒤집힘 없음)', () {
      // 폭 200 × 높이 100 트랙을 300 × 300 상자(여백 0)에: 배율 1.5, 세로 가운데(위아래 75 여백).
      final projection = TrackProjection.fit(xs: const [0, 200], zs: const [0, 100], width: 300, height: 300);

      expect(projection.project(0, 0), const Offset(0, 75));
      expect(projection.project(200, 0), const Offset(300, 75));
      expect(projection.project(0, 100), const Offset(0, 225));
    });

    test('여백(padding) 안쪽에 맞춘다', () {
      final projection =
          TrackProjection.fit(xs: const [0, 100], zs: const [0, 100], width: 120, height: 120, padding: 10);

      expect(projection.project(0, 0), const Offset(10, 10));
      expect(projection.project(100, 100), const Offset(110, 110));
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

      cursor.value = 0; // 표본 0 = (0, 0) → 왼쪽 위
      await t.pump();
      final start = _painter(t).dotOffset(size)!;

      cursor.value = 10; // 표본 2 = (100, 100) → 오른쪽 아래
      await t.pump();
      final corner = _painter(t).dotOffset(size)!;

      expect(corner.dx, greaterThan(start.dx));
      expect(corner.dy, greaterThan(start.dy));
      expect(find.text('Sector 1'), findsOneWidget);
      expect(_painter(t).labelStyle, isNull); // 코너를 안 주면(작은 지도) 번호 없음
    });

    testWidgets('코너를 주면 지도에 코너 번호를 그리고, 번호 자리만큼 여백을 더 둔다', (t) async {
      final cursor = ValueNotifier<double?>(0);
      addTearDown(cursor.dispose);
      const corners = [LapCorner(number: 1, startM: 0, endM: 10, direction: CornerDirection.right)];
      Future<Offset> dotWith(List<LapCorner> corners) async {
        await t.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TrackMap(trace: _positionedTrace('l1'), sectors: sampleLap().sectors, cursor: cursor, corners: corners),
            ),
          ),
        ));
        return _painter(t).dotOffset(t.getSize(_mapPaint))!;
      }

      final plain = await dotWith(const []);
      final labelled = await dotWith(corners);

      expect(_painter(t).corners, corners);
      expect(_painter(t).labelStyle, isNotNull);
      // 표본 0 = 왼쪽 위 모서리: 여백이 커져 안쪽으로 들어온다.
      expect(labelled.dy, greaterThan(plain.dy));
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

    testWidgets('위치가 있으면 Track 카드와 Lap Telemetry 통계를 나란히 보인다(그래프 옆 칸이 생기기 전 폭)', (t) async {
      await pump(t, _positionedTrace('l1'), size: const Size(860, 3000));

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

    testWidgets('넓은 화면: 지도·통계 칸이 그래프 오른쪽에 있고, 페이지를 내려도 화면 안에 붙어 있다', (t) async {
      const viewportHeight = 700.0;
      await pump(t, _positionedTrace('l1'), size: const Size(1500, viewportHeight));

      final aside = find.byKey(const ValueKey('telemetry-aside'));
      final speed = find.byKey(const ValueKey('telemetry-chart-speed'));
      expect(find.byKey(const ValueKey('telemetry-wide-layout')), findsOneWidget);
      expect(find.descendant(of: aside, matching: _mapPaint), findsOneWidget);
      expect(t.getRect(speed).right, lessThanOrEqualTo(t.getRect(aside).left)); // 그래프 옆
      expect(t.getRect(aside).width, kTelemetryAsideWidth);

      final position = _pageScroll(t);
      expect(position.maxScrollExtent, greaterThan(viewportHeight)); // 충분히 스크롤된다
      final layout = find.byKey(const ValueKey('telemetry-wide-layout'));
      for (final pixels in [viewportHeight, position.maxScrollExtent]) {
        position.jumpTo(pixels);
        await t.pump();
        final mapTop = t.getTopLeft(_mapPaint).dy;
        expect(mapTop, greaterThanOrEqualTo(0), reason: '$pixels');
        expect(mapTop, lessThan(viewportHeight), reason: '$pixels');
        expect(t.getRect(aside).bottom, lessThanOrEqualTo(t.getRect(layout).bottom + 0.01), reason: '$pixels');
      }
      // 중간쯤에서는 화면 위쪽 + 여백에 붙는다(끝에서는 그래프 아래 끝을 넘지 않게 멈춘다).
      position.jumpTo(viewportHeight);
      await t.pump();
      expect(t.getTopLeft(aside).dy, closeTo(kViewportPinnedMargin, 0.01));
      // 스크롤 뒤에도 그래프 마우스 십자선이 지도 점을 움직인다.
      final chartPaint = find.descendant(of: speed, matching: find.byType(CustomPaint)).last;
      await t.ensureVisible(chartPaint);
      await t.pump();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(chartPaint));
      await t.pump();
      expect(_painter(t).dotOffset(t.getSize(_mapPaint)), isNotNull);
    });

    testWidgets('좁은 화면: 큰 지도를 지나치면 오른쪽 아래에 작은 지도, 접기·펼치기', (t) async {
      const viewportHeight = 700.0;
      await pump(t, _positionedTrace('l1'), size: const Size(500, viewportHeight));
      final mini = find.byKey(const ValueKey('mini-track-map'));
      final expand = find.byKey(const ValueKey('mini-track-map-expand'));

      expect(find.byKey(const ValueKey('telemetry-narrow-layout')), findsOneWidget);
      expect(mini, findsNothing);

      final position = _pageScroll(t);
      final panelBottom = t.getRect(find.byKey(const ValueKey('lap-telemetry-stats'))).bottom;
      position.jumpTo(panelBottom + 1);
      await t.pump();
      await t.pump();

      expect(mini, findsOneWidget);
      final rect = t.getRect(mini);
      expect(rect.width, kMiniTrackMapSize);
      expect(rect.bottom, lessThanOrEqualTo(viewportHeight)); // 보이는 영역 안
      expect(rect.right, lessThanOrEqualTo(500));
      expect(find.descendant(of: mini, matching: find.byKey(const ValueKey('mini-track-map-paint'))), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('mini-track-map-collapse')));
      await t.pump();
      expect(mini, findsNothing);
      expect(expand, findsOneWidget);

      await t.tap(expand);
      await t.pump();
      expect(mini, findsOneWidget);

      position.jumpTo(0);
      await t.pump();
      await t.pump();
      expect(mini, findsNothing);
      expect(expand, findsNothing);
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
