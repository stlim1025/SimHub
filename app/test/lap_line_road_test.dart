import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_line_road.dart';

const double _widthM = 13;
const double _kerbWidthM = 1.5;

/// 위치와 연석 접촉만 의미 있는 트레이스(표본 5m 간격). [driverLeft]·[driverRight] = 운전자 왼쪽·오른쪽 바퀴가 연석을 밟은 표본.
/// [sides]가 false면 바퀴 쪽 기록이 없는 트레이스.
LapTrace _trace(
  List<Offset> points, {
  Set<int> driverLeft = const {},
  Set<int> driverRight = const {},
  bool sides = true,
}) {
  final n = points.length;
  List<int> filled(int v) => List.filled(n, v);
  final left = [for (var i = 0; i < n; i++) driverLeft.contains(i)];
  final right = [for (var i = 0; i < n; i++) driverRight.contains(i)];
  return LapTrace(
    lapId: 'lap',
    resolutionM: 5,
    timeMs: [for (var i = 0; i < n; i++) i * 100],
    speedKph: filled(200),
    throttle: filled(100),
    brake: filled(0),
    steer: filled(0),
    gear: filled(7),
    rpm: filled(11000),
    worldPosX: [for (final p in points) p.dx],
    worldPosZ: [for (final p in points) p.dy],
    kerbContact: [for (var i = 0; i < n; i++) left[i] || right[i]],
    kerbContactLeft: sides ? left : const [],
    kerbContactRight: sides ? right : const [],
  );
}

LapLineRoad _road(LapTrace player, {LapTrace? ghost}) =>
    roadFromLapLines(player, ghost: ghost, widthM: _widthM, cornerExtraWidthM: 0, kerbWidthM: _kerbWidthM);

/// +x로 곧게 가는 주행선([count]개 표본, 5m 간격). 왼쪽(법선 쪽) = +y.
List<Offset> _straight(int count) => [for (var i = 0; i < count; i++) Offset(i * 5.0, 0)];

/// [p]에서 왼쪽·오른쪽 도로 끝까지 남은 거리(m): 가장 가까운 가운데 점의 법선으로 잰다.
({double left, double right}) _gaps(LapLineRoad road, Offset p) {
  final center = road.center;
  final n = center.length;
  var k = 0;
  for (var i = 1; i < n; i++) {
    if ((center[i] - p).distance < (center[k] - p).distance) {
      k = i;
    }
  }
  int at(int i) => road.closed ? (i % n + n) % n : i.clamp(0, n - 1);
  final tangent = center[at(k + 1)] - center[at(k - 1)];
  final normal = Offset(-tangent.dy, tangent.dx) / tangent.distance;
  final lateral = (p.dx - center[k].dx) * normal.dx + (p.dy - center[k].dy) * normal.dy;
  return (left: road.leftM[k] - lateral, right: road.rightM[k] + lateral);
}

/// 이웃한 가운데 선분 사이에서 방향이 가장 크게 꺾인 각(도).
double _sharpestTurnDeg(LapLineRoad road) {
  final center = road.center;
  final n = center.length;
  var sharpest = 0.0;
  for (var i = 0; i < (road.closed ? n : n - 2); i++) {
    final a = center[(i + 1) % n] - center[i];
    final b = center[(i + 2) % n] - center[(i + 1) % n];
    final turn = (math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)).abs() * 180 / math.pi;
    sharpest = math.max(sharpest, math.min(turn, 360 - turn));
  }
  return sharpest;
}

void main() {
  group('주행선으로 추정한 도로', () {
    test('코너 앞에서는 바깥 끝, 에이펙스에서는 안쪽 끝, 빠져나온 뒤에는 다시 바깥 끝에 붙고 긴 직선에서는 가운데로 지난다', () {
      // +x로 300m → 반지름 60m로 왼쪽(+y 쪽) 90° → +y로 300m.
      const radius = 60.0;
      const arcSteps = 19;
      final points = [
        for (var i = 0; i < 60; i++) Offset(i * 5.0, 0),
        for (var i = 0; i <= arcSteps; i++)
          Offset(300 + radius * math.sin(math.pi / 2 * i / arcSteps), radius - radius * math.cos(math.pi / 2 * i / arcSteps)),
        for (var i = 1; i <= 60; i++) Offset(300 + radius, radius + i * 5.0),
      ];
      final road = _road(_trace(points));

      expect(road.closed, isFalse);
      final apex = _gaps(road, Offset(300 + radius * math.sin(math.pi / 4), radius - radius * math.cos(math.pi / 4)));
      expect(apex.left, closeTo(1.2, 0.4)); // 안쪽(왼쪽) 끝 옆
      expect(apex.right, greaterThan(10));
      final entry = _gaps(road, const Offset(255, 0));
      expect(entry.right, closeTo(2, 0.7)); // 바깥(오른쪽) 끝 옆
      final exit = _gaps(road, const Offset(300 + radius, radius + 45));
      expect(exit.right, closeTo(2, 0.7));
      final far = _gaps(road, const Offset(50, 0));
      expect(far.left, closeTo(_widthM / 2, 0.1));
      expect(far.right, closeTo(_widthM / 2, 0.1));
    });

    test('연석을 밟은 자리에서는 밟은 바퀴 쪽 도로 끝이 차 바로 옆에 온다(운전자 왼쪽 바퀴 = 그림의 오른쪽 끝)', () {
      final road = _road(_trace(_straight(80), driverLeft: {40, 41, 42, 43}));

      final touched = _gaps(road, const Offset(205, 0));
      expect(touched.right, closeTo(0.3, 0.15));
      expect(touched.left, greaterThan(12));
      // 먼 곳은 주행선이 도로 가운데.
      expect(_gaps(road, const Offset(10, 0)).right, closeTo(_widthM / 2, 0.1));
    });

    test('비교 랩이 밟은 연석도 쓴다: 그 차 자리 옆에 도로 끝', () {
      // 비교 랩은 내 랩보다 왼쪽(+y)으로 3m 떨어져 달리며 운전자 오른쪽 바퀴(그림의 왼쪽)로 연석을 밟았다.
      final ghost = _trace([for (final p in _straight(80)) p + const Offset(0, 3)], driverRight: {40, 41, 42});
      final road = _road(_trace(_straight(80)), ghost: ghost);

      expect(_gaps(road, const Offset(205, 3)).left, closeTo(0.3, 0.15));
    });

    test('양쪽 연석을 연달아 밟는 좁은 시케인은 도로를 좁혀 두 연석을 다 차 옆에 둔다', () {
      final road = _road(_trace(_straight(100), driverRight: {40, 41, 42}, driverLeft: {46, 47, 48}));

      // 30m 사이에 도로 폭(13m)만큼 가운데를 옮길 수 없으니, 연석을 밟은 자리에서 그 쪽 폭을 줄인다.
      final first = _gaps(road, const Offset(205, 0));
      expect(first.left, closeTo(0.3, 0.3));
      expect(first.left + first.right, lessThan(_widthM - 1));
      final second = _gaps(road, const Offset(235, 0));
      expect(second.right, closeTo(0.3, 0.3));
      expect(second.left + second.right, lessThan(_widthM - 1));
      final far = _gaps(road, const Offset(480, 0));
      expect(far.left + far.right, closeTo(_widthM, 0.01));
    });

    test('간격이 고르지 않은 표본(겹친 자리·두 칸 간격)도 고른 간격의 가운데 선이 된다', () {
      // 두 표본씩 같은 자리(0·10m 간격이 번갈아).
      final points = [for (var i = 0; i < 80; i++) Offset((i ~/ 2) * 10.0, 0)];
      final road = _road(_trace(points));

      for (var i = 1; i < road.center.length; i++) {
        expect((road.center[i] - road.center[i - 1]).distance, closeTo(5, 0.2));
      }
    });

    test('혼자 옆으로 튄 위치 표본은 도로를 꺾지 않는다', () {
      final points = _straight(80)..[30] = const Offset(150, 2.2);
      final road = _road(_trace(points));

      expect(road.center.every((p) => p.dy.abs() < 0.2), isTrue);
    });

    test('랩 시작과 끝의 좌우 자리가 달라도 결승선에서 도로가 꺾이지 않는다', () {
      // 직선 400m 두 개를 반지름 80m 반원으로 이은 닫힌 서킷. 마지막 100m에서 왼쪽으로 4m까지 벗어나 끝난다.
      const radius = 80.0;
      const half = 200.0;
      final arc = (math.pi * radius / 5).round();
      final loop = <Offset>[
        for (var i = 0; i < 40; i++) Offset(i * 5.0, 0),
        for (var i = 0; i < arc; i++)
          Offset(half + radius * math.sin(math.pi * i / arc), radius - radius * math.cos(math.pi * i / arc)),
        for (var i = 0; i < 80; i++) Offset(half - i * 5.0, 2 * radius),
        for (var i = 0; i < arc; i++)
          Offset(-half - radius * math.sin(math.pi * i / arc), radius + radius * math.cos(math.pi * i / arc)),
        for (var i = 0; i < 39; i++) Offset(-half + i * 5.0, 0),
      ];
      final n = loop.length;
      final points = [
        for (var i = 0; i < n; i++) i >= n - 20 ? loop[i] + Offset(0, 4 * (i - (n - 20)) / 19) : loop[i],
      ];
      final road = _road(_trace(points));

      expect(road.closed, isTrue);
      // 반원(반지름 80m)을 5m씩 도는 꺾임은 3.6°.
      expect(_sharpestTurnDeg(road), lessThan(8));
    });

    test('한 바퀴 내내 한쪽으로 굽은 주행선(원)은 가운데로 지난다', () {
      const radius = 200.0;
      final count = (2 * math.pi * radius / 5).round();
      final points = [
        for (var i = 0; i < count; i++) Offset(radius * math.cos(2 * math.pi * i / count), radius * math.sin(2 * math.pi * i / count)),
      ];
      final road = _road(_trace(points));

      expect(road.closed, isTrue);
      final gaps = _gaps(road, points[40]);
      expect(gaps.left, closeTo(_widthM / 2, 0.2));
      expect(gaps.right, closeTo(_widthM / 2, 0.2));
    });
  });

  group('연석을 밟은 표본', () {
    test('이어진 접촉은 처음 닿은 바퀴 쪽 연석 하나다: 깊게 타 반대쪽 바퀴만 닿아도 같은 연석', () {
      // 10~11: 운전자 오른쪽 바퀴만, 12: 양쪽, 13: 왼쪽 바퀴만(연석을 넘어갔다). 30: 떨어진 다른 연석(왼쪽 바퀴).
      final trace = _trace(_straight(50), driverRight: {10, 11, 12}, driverLeft: {12, 13, 30});

      final touches = kerbTouches(trace, kerbWidthM: _kerbWidthM);

      expect([for (final t in touches) t.sample], [10, 11, 12, 13, 30]);
      // 운전자 오른쪽 바퀴 = 그림의 왼쪽 도로 끝.
      expect([for (final t in touches) t.left], [true, true, true, true, false]);
      expect(touches[0].gapM, closeTo(0.3, 1e-9));
      expect(touches[2].gapM, closeTo(-_kerbWidthM / 2, 1e-9)); // 연석 한가운데
      expect(touches[3].gapM, lessThan(-_kerbWidthM)); // 연석 바깥 끝 너머
      expect(touches[4].gapM, closeTo(0.3, 1e-9));
    });

    test('한 표본 빈 틈은 같은 연석으로 잇고, 바퀴 쪽 기록이 없으면 빈 목록', () {
      final trace = _trace(_straight(50), driverRight: {10}, driverLeft: {12});
      expect([for (final t in kerbTouches(trace, kerbWidthM: _kerbWidthM)) t.left], [true, true]);

      final unknown = _trace(_straight(50), driverRight: {10}, sides: false);
      expect(kerbTouches(unknown, kerbWidthM: _kerbWidthM), isEmpty);
    });
  });
}
