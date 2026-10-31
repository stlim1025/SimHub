import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_corners.dart';
import 'package:simcenter_app/features/sessions/presentation/race_review_track_map.dart';

const double _radius = 100;
const Offset _center = Offset(150, 150);
const Size _box = Size(300, 300);
const Size _badge = Size(20, 12);

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

    test('붙어 있는 코너는 배지가 겹치지 않게 더 멀리 놓는다', () {
      final labels = placeCornerLabels(
        points: _circle(),
        resolutionM: 1,
        corners: [_corner(1, 100), _corner(2, 104)],
        size: _box,
        sizeOf: (_) => _badge,
      );

      final a = Rect.fromCenter(center: labels[0].center, width: _badge.width, height: _badge.height);
      final b = Rect.fromCenter(center: labels[1].center, width: _badge.width, height: _badge.height);
      expect(a.overlaps(b), isFalse);
      expect((labels[1].center - _center).distance, greaterThan((labels[0].center - _center).distance));
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
