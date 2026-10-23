import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/tracks/domain/track_outline.dart';

void main() {
  test('앱에 넣은 서킷 윤곽 asset은 시드 트랙 31개를 모두 담고, 점은 0~1 안이다', () {
    final json = jsonDecode(File('assets/track_outlines/track_outlines.json').readAsStringSync()) as Map<String, dynamic>;
    final outlines = parseTrackOutlines(json);

    expect(outlines.length, 31);
    for (final name in ['Melbourne', 'Montreal', 'Madrid (Madring)', 'Zandvoort (Reverse)', 'Portimão']) {
      expect(outlines, contains(name));
    }
    for (final outline in outlines.values) {
      expect(outline.points.length, greaterThan(50));
      expect(outline.points.every((p) => p.dx >= 0 && p.dx <= 1 && p.dy >= 0 && p.dy <= 1), isTrue);
      expect([outline.width, outline.height].reduce((a, b) => a > b ? a : b), closeTo(1, 0.0001));
    }
  });

  test('형식이 틀린 항목은 건너뛴다', () {
    final outlines = parseTrackOutlines({
      'tracks': {
        'Good': {'w': 1, 'h': 0.5, 'points': [[0, 0], [1, 0.5]]},
        'NoPoints': {'w': 1, 'h': 1},
        'Bad': 'x',
      },
    });

    expect(outlines.keys, ['Good']);
  });
}
