import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_corners.dart';
import 'package:simcenter_app/features/lap_detail/presentation/corner_labels.dart';

const double _radius = 100;
const Offset _center = Offset(150, 150);
const Size _box = Size(300, 300);
const Size _badge = Size(20, 12);
const double _trackHalfWidth = 4;

/// 원 한 바퀴(반지름 [_radius]px, 1m = 1px, 1m 간격) 화면 점.
List<Offset> _circle() {
  final count = (2 * math.pi * _radius).round();
  return [
    for (var i = 0; i < count; i++) _center + Offset(_radius * math.cos(i / _radius), _radius * math.sin(i / _radius)),
  ];
}

LapCorner _corner(int number, double midM) =>
    LapCorner(number: number, startM: midM - 5, endM: midM + 5, direction: CornerDirection.right);

void main() {
  group('placeCornerLabels', () {
    test('코너 번호는 코너 바깥쪽(원 밖)에 놓인다', () {
      final labels = placeCornerLabels(
        points: _circle(),
        resolutionM: 1,
        corners: [_corner(1, 100), _corner(2, 300)],
        size: _box,
        sizeOf: (_) => _badge,
      );

      expect(labels.map((l) => l.text), ['T1', 'T2']);
      for (final label in labels) {
        expect((label.center - _center).distance, greaterThan(_radius));
        expect((label.anchor - _center).distance, closeTo(_radius, 0.01));
      }
    });

    test('코너가 몰려 있어도(실버스톤 베케츠처럼) 배지끼리 겹치지 않고 트랙 선도 덮지 않는다', () {
      final circle = _circle();
      final labels = placeCornerLabels(
        points: circle,
        resolutionM: 1,
        corners: [for (var k = 0; k < 6; k++) _corner(k + 1, 100 + k * 8.0)],
        size: _box,
        sizeOf: (_) => _badge,
        trackHalfWidth: _trackHalfWidth,
      );

      final rects = [
        for (final l in labels) Rect.fromCenter(center: l.center, width: _badge.width, height: _badge.height),
      ];
      for (var a = 0; a < rects.length; a++) {
        for (var b = a + 1; b < rects.length; b++) {
          expect(rects[a].overlaps(rects[b]), isFalse, reason: 'T${a + 1}·T${b + 1} 겹침');
        }
        for (final p in circle) {
          final dx = math.max(math.max(rects[a].left - p.dx, 0.0), p.dx - rects[a].right);
          final dy = math.max(math.max(rects[a].top - p.dy, 0.0), p.dy - rects[a].bottom);
          expect(math.sqrt(dx * dx + dy * dy), greaterThanOrEqualTo(_trackHalfWidth), reason: 'T${a + 1}이 트랙을 덮음');
        }
      }
    });

    test('트랙 두 줄 사이에 낀 코너는 지시선이 다른 줄을 가로지르지 않는 쪽에 놓는다', () {
      // 위아래로 20px 떨어진(배지가 사이에 못 들어가는) 두 직선을 잇는 헤어핀. 아래 줄은 오른쪽 → 왼쪽으로 달려
      // 코너 지점(아래 줄 가운데)의 바깥쪽 = 위(다른 줄 쪽)다.
      final points = [
        for (var x = 280.0; x >= 20; x -= 1) Offset(x, 160),
        for (var x = 20.0; x <= 280; x += 1) Offset(x, 140),
      ];
      final labels = placeCornerLabels(
        points: points,
        resolutionM: 1,
        corners: [_corner(1, 130)],
        size: _box,
        sizeOf: (_) => _badge,
        trackHalfWidth: _trackHalfWidth,
      );

      expect(labels.single.center.dy, greaterThan(160));
    });

    test('배지는 상자 밖으로 나가지 않는다', () {
      final labels = placeCornerLabels(
        points: _circle(),
        resolutionM: 1,
        corners: [_corner(1, 0)],
        size: const Size(260, 300),
        sizeOf: (_) => _badge,
      );

      final rect = Rect.fromCenter(center: labels.single.center, width: _badge.width, height: _badge.height);
      expect(rect.right, lessThanOrEqualTo(260));
    });

    test('점이 모자라거나 코너가 없으면 빈 목록', () {
      expect(
        placeCornerLabels(
          points: const [],
          resolutionM: 1,
          corners: [_corner(1, 0)],
          size: _box,
          sizeOf: (_) => _badge,
        ),
        isEmpty,
      );
      expect(
        placeCornerLabels(points: _circle(), resolutionM: 1, corners: const [], size: _box, sizeOf: (_) => _badge),
        isEmpty,
      );
    });
  });
}
