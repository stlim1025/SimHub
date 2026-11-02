import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/ghost_replay.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/ghost_replay_3d_painter.dart';
import 'package:simcenter_app/features/lap_detail/presentation/replay_circuit.dart';
import 'package:simcenter_app/features/tracks/domain/track_sample_geometry.dart';
import 'package:simcenter_app/features/tracks/domain/track_width_profile.dart';

/// 원 서킷(반지름 100m) 표본 형상. [pit]이면 반지름 [pitRadius]m에 피트 레인(점 10개)을 붙인다.
/// [columns]는 칸마다 같은 값으로 채울 열(가장자리·연석 바깥·도달 폭).
Map<String, dynamic> _geometryJson({bool pit = true, double pitRadius = 115, Map<String, double> columns = const {}}) {
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
    for (final MapEntry(:key, :value) in columns.entries) key: [for (var i = 0; i < n; i++) value],
    if (pit) ...{
      'pitX': [for (var i = 0; i < 10; i++) pitRadius * math.cos(angle(i))],
      'pitZ': [for (var i = 0; i < 10; i++) pitRadius * math.sin(angle(i))],
      'pitY': [for (var i = 0; i < 10; i++) 1.5],
    },
  };
}

/// [radius]m 원을 [resolutionM]m 간격으로 한 바퀴 도는 내 랩.
LapTrace _circleLap({double radius = 100, int resolutionM = 5}) {
  final count = (2 * math.pi * radius / resolutionM).ceil();
  return LapTrace(
    lapId: 'lap',
    resolutionM: resolutionM,
    timeMs: [for (var i = 0; i < count; i++) i * 100],
    speedKph: [for (var i = 0; i < count; i++) 180],
    throttle: [for (var i = 0; i < count; i++) 100],
    brake: [for (var i = 0; i < count; i++) 0],
    steer: [for (var i = 0; i < count; i++) 0],
    gear: [for (var i = 0; i < count; i++) 6],
    rpm: [for (var i = 0; i < count; i++) 11000],
    worldPosX: [for (var i = 0; i < count; i++) radius * math.cos(i * resolutionM / radius)],
    worldPosZ: [for (var i = 0; i < count; i++) radius * math.sin(i * resolutionM / radius)],
  );
}

void main() {
  test('피트 레인 선을 읽어 서킷에 피트 레인(점·높이·법선)을 싣고, 도로 밖에서 시작·끝나면 도로 끝에서 갈라지는 입구·출구 길을 잇는다', () {
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson())!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry);
    final first = circuit.pitLane.indexOf(geometry.pitLine.first);

    expect(geometry.pitLine, hasLength(10));
    // 표본 피트 레인(반지름 115m)은 도로(바깥 끝 106.5m) 밖이라, 피트 상태가 켜지기 전 입구 길과 꺼진 뒤 출구 길이 없다.
    expect(circuit.pitLane, containsAllInOrder(geometry.pitLine));
    expect(first, greaterThan(0));
    expect(circuit.pitLane.length, greaterThan(first + geometry.pitLine.length));
    expect(circuit.pitLane.first.distance, closeTo(106.5, 0.01));
    expect(circuit.pitLane.last.distance, closeTo(106.5, 0.01));
    expect(circuit.pitElevations[first], 1.5);
    expect(circuit.pitElevations.first, 2); // 이은 길은 가까운 도로 높이
    expect(circuit.pitNormals.first.distance, closeTo(1, 1e-9));
    expect(circuit.pitAsphalt.getBounds().isEmpty, isFalse);
  });

  test('안쪽 연석 기록이 없는 급한 코너는 안쪽 도로 끝을 아스팔트 바퀴 끝에 붙여, 레이싱 라인이 꼭짓점에서 안쪽 끝을 지난다', () {
    // 원(반지름 100m)을 반시계로 돈다(왼쪽 = 안쪽). 연석 기록이 없고 차들의 아스팔트 바퀴는 라인 왼쪽 1.5m까지만 갔다
    // (Hungaroring T12·T13). 연석 단서가 없으면 도로 가운데가 라인에 머물러 안쪽 끝이 반폭 6.5m에 선다.
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(
      pit: false,
      columns: {'edgeLeftM': 1.5, 'edgeRightM': 3, 'kerbOuterLeftM': 0, 'kerbOuterRightM': 0},
    ))!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry);
    Offset at(double radius) => Offset(radius * math.cos(1.0), radius * math.sin(1.0));

    expect(circuit.asphalt.contains(at(98.7)), isTrue);
    expect(circuit.asphalt.contains(at(98.2)), isFalse);
    expect(circuit.kerbRed.contains(at(97.8)) || circuit.kerbWhite.contains(at(97.8)), isTrue);
    // 도로 폭(13m)은 바깥으로 채운다.
    expect(circuit.asphalt.contains(at(110.8)), isTrue);
  });

  test('피트 레인이 없으면 비어 있다', () {
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(pit: false))!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry);

    expect(geometry.pitX, isNull);
    expect(circuit.pitLane, isEmpty);
  });

  test('표본 형상이 있으면 지도 실측보다 표본 형상으로 도로를 그린다(지도가 옛 레이아웃일 수 있다)', () {
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(pit: false))!;
    // 지도 실측: 같은 원, 좌우 9m(표본 형상 도로 반폭 5m보다 넓다).
    final real = TrackWidthProfile(
      center: geometry.line,
      leftM: List.filled(geometry.length, 9),
      rightM: List.filled(geometry.length, 9),
    );
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), real: real, samples: geometry, baseWidthM: 10);
    Offset at(double radius) => Offset(radius * math.cos(1.0), radius * math.sin(1.0));

    expect(circuit.asphalt.contains(at(104)), isTrue);
    expect(circuit.asphalt.contains(at(107)), isFalse);
  });

  test('바퀴 가장자리 열이 있으면 아스팔트는 바퀴가 닿은 끝까지, 연석을 밟은 차는 연석 위에 오도록 넓힌다', () {
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(
      pit: false,
      columns: {'edgeLeftM': 7, 'edgeRightM': 3, 'kerbOuterLeftM': 0, 'kerbOuterRightM': 8},
    ))!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry, baseWidthM: 10);
    Offset at(double radius) => Offset(radius * math.cos(1.0), radius * math.sin(1.0));

    expect(geometry.edgeLeftM, isNotNull);
    // 왼쪽(안쪽): 바퀴가 아스팔트를 밟은 끝 7m(기본 반폭 5m보다 넓다).
    expect(circuit.asphalt.contains(at(93.5)), isTrue);
    expect(circuit.asphalt.contains(at(92.5)), isFalse);
    // 오른쪽: 연석 바깥 끝 8m − 연석 폭 1.5m(바퀴 가장자리 3m보다 넓다).
    expect(circuit.asphalt.contains(at(106)), isTrue);
    expect(circuit.asphalt.contains(at(107.5)), isFalse);
  });

  test('연석이 있는 칸은 아스팔트가 연석 안쪽 끝까지, 연석은 그 바깥에 그린다(그 너머 포장 런오프는 도로가 아니다)', () {
    final json = _geometryJson(
      pit: false,
      // 안쪽(왼쪽)은 아스팔트 바퀴 끝 3.5m — 안쪽 끝에 붙여도 연석 안쪽 끝(6.5m)까지 도로 폭 10m가 찬다.
      columns: {'edgeLeftM': 3.5, 'edgeRightM': 20, 'kerbOuterLeftM': 0, 'kerbOuterRightM': 8},
    );
    json['kerbRight'] = [for (var i = 0; i < (json['x'] as List).length; i++) true];
    final circuit = ReplayCircuit.build(
      LapReplay(_circleLap()),
      samples: TrackSampleGeometry.fromJsonOrNull(json)!,
      baseWidthM: 10,
    );
    Offset at(double radius) => Offset(radius * math.cos(1.0), radius * math.sin(1.0));

    // 오른쪽(바깥): 포장 런오프로 20m까지 나간 차가 있어도 아스팔트는 연석 안쪽 끝(8m − 1.5m)까지, 연석은 그 바깥 1.5m.
    expect(circuit.asphalt.contains(at(106)), isTrue);
    expect(circuit.asphalt.contains(at(107)), isFalse);
    expect(circuit.kerbRed.contains(at(107.2)) || circuit.kerbWhite.contains(at(107.2)), isTrue);
    expect(circuit.asphalt.contains(at(115)), isFalse);
  });

  test('양쪽 연석이 다 밟힌 코너는 안쪽 연석에 도로 가장자리를 맞춰, 레이싱 라인이 꼭짓점에서 연석을 타고 지난다', () {
    // 원을 반시계로 돈다(왼쪽 = 안쪽). 모든 칸에서 양쪽 연석이 밟혔고, 연석 바깥 끝은 라인에서 2.5m(안쪽 끝 1m).
    final json = _geometryJson(
      pit: false,
      columns: {'edgeLeftM': 1, 'edgeRightM': 1, 'kerbOuterLeftM': 2.5, 'kerbOuterRightM': 2.5},
    );
    final n = (json['x'] as List).length;
    json['kerbLeft'] = [for (var i = 0; i < n; i++) true];
    json['kerbRight'] = [for (var i = 0; i < n; i++) true];
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: TrackSampleGeometry.fromJsonOrNull(json)!);
    Offset at(double radius) => Offset(radius * math.cos(1.0), radius * math.sin(1.0));

    // 안쪽 가장자리 = 라인에서 1m(두 쪽을 평균하면 라인이 도로 가운데로 돌아와 안쪽 가장자리가 6.5m에 선다).
    expect(circuit.asphalt.contains(at(99.5)), isTrue);
    expect(circuit.asphalt.contains(at(98.5)), isFalse);
    expect(circuit.kerbRed.contains(at(98.3)) || circuit.kerbWhite.contains(at(98.3)), isTrue);
  });

  test('에이펙스 안쪽 연석 앞뒤로 바깥 연석이 밟혀도 안쪽 가장자리는 연석 안쪽 끝에 붙고, 도로 폭은 바깥으로 채운다', () {
    // 원을 반시계로 돈다(왼쪽 = 안쪽). 40~44칸은 안쪽 연석(에이펙스), 그 앞뒤 34~37·47~50칸은 바깥 연석(진입·탈출).
    // 연석 바깥 끝은 모두 라인에서 2.5m(안쪽 끝 1m). 고른 가운데 이동은 두 단서가 섞여 꼭짓점에서 0 가까이 무뎌진다.
    final json = _geometryJson(
      pit: false,
      columns: {'edgeLeftM': 1, 'edgeRightM': 1, 'kerbOuterLeftM': 2.5, 'kerbOuterRightM': 2.5},
    );
    final n = (json['x'] as List).length;
    json['kerbLeft'] = [for (var i = 0; i < n; i++) i >= 40 && i <= 44];
    json['kerbRight'] = [for (var i = 0; i < n; i++) (i >= 34 && i <= 37) || (i >= 47 && i <= 50)];
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: TrackSampleGeometry.fromJsonOrNull(json)!);
    Offset at(double radius) => Offset(radius * math.cos(42 * 0.05), radius * math.sin(42 * 0.05));

    // 꼭짓점(42칸): 안쪽 가장자리 = 라인에서 1m, 그 안쪽은 연석(고른 가운데 이동만 쓰면 반폭 6.5m에 가까이 선다).
    // 바깥은 도로 폭(13m)이 되도록 넓어진다 — 앞뒤 바깥 연석이 있어도 도로가 좁아지지 않는다.
    expect(circuit.asphalt.contains(at(99.3)), isTrue);
    expect(circuit.asphalt.contains(at(98.7)), isFalse);
    expect(circuit.kerbRed.contains(at(98.3)) || circuit.kerbWhite.contains(at(98.3)), isTrue);
    expect(circuit.asphalt.contains(at(111.5)), isTrue);
  });

  test('에이펙스 연석 칸에서는 내 랩이 연석 바로 옆을 지나도 차 반폭만큼 도로를 넓혀 연석을 밀어내지 않는다', () {
    // 원을 반시계로 돈다(왼쪽 = 안쪽). 모든 칸에서 안쪽 연석이 밟혔고 연석 안쪽 끝은 라인에서 0.5m(바깥 끝 2m).
    // 내 랩은 라인 위를 달리고 연석 접촉 기록이 없다 — 차 반폭(1m)이 아스팔트 안에 들게 넓히면 연석이 1m 넘게 밀려난다.
    final json = _geometryJson(
      pit: false,
      columns: {'edgeLeftM': 0.5, 'edgeRightM': 1, 'kerbOuterLeftM': 2, 'kerbOuterRightM': 0},
    );
    final n = (json['x'] as List).length;
    json['kerbLeft'] = [for (var i = 0; i < n; i++) true];
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: TrackSampleGeometry.fromJsonOrNull(json)!);
    Offset at(double radius) => Offset(radius * math.cos(1.0), radius * math.sin(1.0));

    expect(circuit.asphalt.contains(at(99.7)), isTrue);
    expect(circuit.asphalt.contains(at(99.2)), isFalse);
    expect(circuit.kerbRed.contains(at(99.0)) || circuit.kerbWhite.contains(at(99.0)), isTrue);
  });

  test('한두 칸만 튄 가장자리(피트 입구로 갈라지는 차 등)는 앞뒤 가운데값으로 눌러 도로가 부풀지 않는다', () {
    final json = _geometryJson(
      pit: false,
      columns: {'edgeLeftM': 3, 'edgeRightM': 3, 'kerbOuterLeftM': 0, 'kerbOuterRightM': 0},
    );
    (json['edgeLeftM'] as List)[60] = 20.0;
    final circuit = ReplayCircuit.build(
      LapReplay(_circleLap()),
      samples: TrackSampleGeometry.fromJsonOrNull(json)!,
      baseWidthM: 10,
    );
    Offset polar(double radius, double angle) => Offset(radius * math.cos(angle), radius * math.sin(angle));

    expect(circuit.asphalt.contains(polar(97.5, 3.0)), isTrue); // 안쪽 아스팔트 바퀴 끝 3m 안
    expect(circuit.asphalt.contains(polar(88, 3.0)), isFalse); // 칸 60(300m)에서 20m로 튄 값은 누른다
  });

  test('표본 형상은 주행선에 다시 맞추지 않고 그 칸 그대로 쓰고, 주행선은 폭을 넓혀 담는다', () {
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(pit: false))!;
    // 내 랩: 6m 바깥을 10m 간격으로 돈다(예전에는 표본 형상을 이 선에 맞춰 키우고 내 랩 점으로 옮겨 담았다).
    final circuit = ReplayCircuit.build(LapReplay(_circleLap(radius: 106, resolutionM: 10)), samples: geometry, baseWidthM: 10);
    Offset at(double radius) => Offset(radius * math.cos(1.0), radius * math.sin(1.0));

    expect(circuit.isMeasured, isTrue);
    expect(circuit.center, hasLength(geometry.length));
    for (final p in circuit.center) {
      expect(p.distance, closeTo(100, 0.01));
    }
    expect(circuit.asphalt.contains(at(106.8)), isTrue); // 내 랩 차(가운데 106m + 반폭 1m)도 아스팔트 위
  });

  test('표본 연석은 짧은 틈을 이어 그리고, 안쪽 연석 기록이 없는 급한 코너는 곡률로 안쪽 연석을 그린다', () {
    final json = _geometryJson(pit: false);
    final n = (json['x'] as List).length;
    // 오른쪽(바깥) 연석: 20~29칸과 31~40칸(가운데 한 칸만 비었다). 안쪽(왼쪽) 기록은 없다.
    json['kerbRight'] = [for (var i = 0; i < n; i++) (i >= 20 && i <= 29) || (i >= 31 && i <= 40)];
    // 내 랩: 연석 접촉 기록은 있지만 밟은 곳이 없다(기록이 아예 없어 곡률로 양쪽에 그리는 경우와 다르다).
    final lap = _circleLap();
    final trace = LapTrace(
      lapId: lap.lapId,
      resolutionM: lap.resolutionM,
      timeMs: lap.timeMs,
      speedKph: lap.speedKph,
      throttle: lap.throttle,
      brake: lap.brake,
      steer: lap.steer,
      gear: lap.gear,
      rpm: lap.rpm,
      worldPosX: lap.worldPosX,
      worldPosZ: lap.worldPosZ,
      kerbContact: [for (var i = 0; i < lap.length; i++) false],
    );
    final circuit = ReplayCircuit.build(LapReplay(trace), samples: TrackSampleGeometry.fromJsonOrNull(json)!, baseWidthM: 10);

    expect(circuit.kerbRight[30], isTrue); // 한 칸 틈은 잇는다
    expect(circuit.kerbRight[80], isFalse);
    // 원(반지름 100m, 왼쪽으로 굽는다)은 안쪽 연석 기록이 없어 곡률로 안쪽(왼쪽)에 그린다.
    expect(circuit.kerbLeft.every((kerb) => kerb), isTrue);
  });

  test('방호벽은 차 몸체가 닿은 가장 먼 자리보다 바깥에 선다', () {
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(
      pit: false,
      columns: {'reachLeftM': 2, 'reachRightM': 30},
    ))!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry, baseWidthM: 10);
    final track = ReplayTrack3d.build(circuit);
    // 도달 폭 열이 없는(예전 서버) 같은 서킷: 연석·런오프로만 정한 벽.
    final plain = ReplayTrack3d.build(ReplayCircuit.build(
      LapReplay(_circleLap()),
      samples: TrackSampleGeometry.fromJsonOrNull(_geometryJson(pit: false))!,
      baseWidthM: 10,
    ));

    for (var i = 0; i < circuit.center.length; i++) {
      // 오른쪽: 30m 밖까지 나간 차가 있어 연석·런오프로 정한 자리보다 멀리.
      expect(circuit.rightWidths[i] + track.wallRightM[i], greaterThanOrEqualTo(30.3 - 1e-9));
      expect(track.wallRightM[i], greaterThan(plain.wallRightM[i]));
      // 왼쪽: 닿은 차가 도로 안이라 그대로.
      expect(track.wallLeftM[i], closeTo(plain.wallLeftM[i], 1e-9));
    }
    expect(track.hasWallRight.every((standing) => standing), isTrue);
  });

  test('피트 레인이 나란한 쪽 방호벽은 피트 레인을 가로지르지 않고 도로와 피트 레인 사이에 선다', () {
    // 도로(반지름 100m, 폭 10m) 바깥 10m에 피트 레인(폭 7m): 도로 가장자리 105m, 피트 레인 안쪽 끝 106.5m —
    // 런오프(3m)대로 세우면 108m라 피트 레인 한가운데를 지난다.
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(pitRadius: 110))!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry, baseWidthM: 10);
    final track = ReplayTrack3d.build(circuit);
    final plain = ReplayTrack3d.build(ReplayCircuit.build(
      LapReplay(_circleLap()),
      samples: TrackSampleGeometry.fromJsonOrNull(_geometryJson(pit: false))!,
      baseWidthM: 10,
    ));

    for (var i = 2; i <= 7; i++) {
      final wallRadius = 100 + circuit.rightWidths[i] + track.wallRightM[i];
      expect(track.hasWallRight[i], isTrue);
      expect(wallRadius, lessThan(106.5));
      expect(wallRadius, greaterThan(100 + circuit.rightWidths[i]));
    }
    // 피트 레인과 먼 곳(반대편)은 피트 레인이 없는 서킷과 같다.
    final far = circuit.center.length ~/ 2;
    expect(track.wallRightM[far], closeTo(plain.wallRightM[far], 1e-9));
    expect(track.wallLeftM[far], closeTo(plain.wallLeftM[far], 1e-9));
  });

  test('차가 닿은 자리가 피트 레인 너머여도 방호벽은 피트 레인 안쪽에 서고, 런오프 끝 벽과 잇지 않고 끊긴다', () {
    // 도로(반지름 100m, 폭 10m) 바깥 40m에 피트 레인, 피트 레인 차까지 45m 밖에 닿았다 — 차가 닿은 자리대로 세우면 벽이 피트 레인 너머에 선다.
    final geometry = TrackSampleGeometry.fromJsonOrNull(_geometryJson(pitRadius: 140, columns: {'reachLeftM': 2, 'reachRightM': 45}))!;
    final circuit = ReplayCircuit.build(LapReplay(_circleLap()), samples: geometry, baseWidthM: 10);
    final track = ReplayTrack3d.build(circuit);
    final n = circuit.center.length;

    for (var i = 2; i <= 7; i++) {
      final wallRadius = 100 + circuit.rightWidths[i] + track.wallRightM[i];
      expect(track.hasWallRight[i], isTrue);
      expect(wallRadius, lessThan(140 - kCircuitPitLaneWidthM / 2));
    }
    // 피트 레인 앞뒤(도로에서 갈라지는 입구·출구 길 끝)에서 피트 월과 런오프 끝 벽(약 40m)을 비스듬히 잇지 않는다.
    expect([for (var i = n ~/ 2; i < n; i++) track.hasWallRight[i]], contains(false));
    expect([for (var i = 10; i < n ~/ 2; i++) track.hasWallRight[i]], contains(false));
    // 피트 레인과 먼 곳은 차가 닿은 자리 바깥에 그대로 선다.
    expect(circuit.rightWidths[n ~/ 2] + track.wallRightM[n ~/ 2], greaterThanOrEqualTo(45.3 - 1e-9));
  });
}
