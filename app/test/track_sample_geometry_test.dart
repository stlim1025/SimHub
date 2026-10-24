import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/ghost_replay.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/replay_circuit.dart';
import 'package:simcenter_app/features/tracks/domain/track_sample_geometry.dart';

/// 원 서킷(반지름 100m) 표본 형상. [pit]이면 바깥 15m에 피트 레인(점 10개)을 붙인다.
Map<String, dynamic> _geometryJson({bool pit = true}) {
  const n = 126;
  double angle(int i) => i * 5 / 100;
  return {
    'resolutionM': 5,
    'sessionCount': 1,
    'x': [for (var i = 0; i < n; i++) 100 * math.cos(angle(i))],
    'z': [for (var i = 0; i < n; i++) 100 * math.sin(angle(i))],
    'y': [for (var i = 0; i < n; i++) 2.0],
    'bandLeftM': [for (var i = 0; i < n; i++) 2.0],
    'bandRightM': [for (var i = 0; i < n; i++) 2.0],
    'kerbLeft': [for (var i = 0; i < n; i++) false],
    'kerbRight': [for (var i = 0; i < n; i++) false],
    if (pit) ...{
      'pitX': [for (var i = 0; i < 10; i++) 115 * math.cos(angle(i))],
      'pitZ': [for (var i = 0; i < 10; i++) 115 * math.sin(angle(i))],
      'pitY': [for (var i = 0; i < 10; i++) 1.5],
    },
  };
}

LapTrace _circleLap() {
  const count = 126;
  return LapTrace(
    lapId: 'lap',
    resolutionM: 5,
    timeMs: [for (var i = 0; i < count; i++) i * 100],
    speedKph: [for (var i = 0; i < count; i++) 180],
    throttle: [for (var i = 0; i < count; i++) 100],
    brake: [for (var i = 0; i < count; i++) 0],
    steer: [for (var i = 0; i < count; i++) 0],
    gear: [for (var i = 0; i < count; i++) 6],
    rpm: [for (var i = 0; i < count; i++) 11000],
    worldPosX: [for (var i = 0; i < count; i++) 100 * math.cos(i * 5 / 100)],
    worldPosZ: [for (var i = 0; i < count; i++) 100 * math.sin(i * 5 / 100)],
  );
}

void main() {
  test('피트 레인 선을 읽어 서킷에 피트 레인(점·높이·법선)을 싣는다', () {
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson())!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry);

    expect(geometry.pitLine, hasLength(10));
    expect(circuit.pitLane, hasLength(10));
    expect(circuit.pitElevations.first, 1.5);
    expect(circuit.pitNormals.first.distance, closeTo(1, 1e-9));
    expect(circuit.pitAsphalt.getBounds().isEmpty, isFalse);
  });

  test('피트 레인이 없으면 비어 있다', () {
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(pit: false))!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry);

    expect(geometry.pitX, isNull);
    expect(circuit.pitLane, isEmpty);
  });
}
