import 'dart:math' as math;
import 'dart:ui' show VertexMode, Vertices;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/ghost_replay.dart';
import 'ghost_replay_painter.dart';
import 'replay_circuit.dart';

/// 고스트 재생 3D 시점의 카메라.
enum ReplayCamera {
  /// 차 바로 뒤 위(게임 추격 카메라).
  chase,

  /// 길 옆 멀리서 망원으로 따라가는 중계 카메라.
  broadcast,

  /// 뒤쪽 높은 곳에서 내려다보는 헬기 카메라.
  helicopter,
}

/// 코너 바깥 연석·그래블 너머 방호벽까지의 런오프 폭(m)·방호벽 높이(m).
const double _runoffM = 3;
const double _wallHeightM = 1;

/// 방호벽 위치(가장자리에서 m)를 고르는 범위(점 수): 앞뒤 가장 먼 값으로 넓힌 뒤 평균해 그래블 끝에서 들쭉날쭉하지 않게.
const int _wallSmoothSamples = 4;

/// 방호벽이 다른 구간 도로(가장자리 + 이 여유 m) 안에 들어가면 가장자리 쪽으로 당긴다(모나코처럼 길이 붙은 곳).
/// 이 길이(m) 안의 앞뒤 점은 같은 구간으로 보고 견주지 않는다.
const double _wallClearanceM = 1.5;
const double _sameStretchM = 10;

/// 다른 구간과 겹칠 때 방호벽 거리를 줄여 보는 비율(큰 것부터). 끝까지 겹치면 그 자리에는 벽을 세우지 않는다.
const List<double> _wallShrinkSteps = [0.8, 0.6, 0.4, 0.25, 0.1];

/// 가까운 중심선 점을 찾는 격자 칸 크기(m).
const double _gridCellM = 20;

/// 흰 가장자리 선 폭(m, 도로 안쪽으로).
const double _edgeLineWidthM = 0.4;

/// 출발·결승선 굵기(m, 진행 방향).
const double _startLineDepthM = 1.2;

/// 먼 구간은 점을 건너뛰어 그린다: 이 점 수 묶음 안에서는 같은 간격을 쓴다(간격이 바뀌는 곳에 틈이 생기지 않게).
const int _lodBlock = 4;
const double _lodFineM = 120;
const double _lodMidM = 250;

/// 카메라 뒤로 이보다 먼(m) 묶음은 건너뛴다.
const double _behindCullM = 30;

/// 카메라 앞 자르는 면(m).
const double _nearM = 0.3;

/// 안개: 이 거리(m)부터 지평선 색으로 섞기 시작해 [_fogRangeM] 뒤 최대 [_fogMax]까지.
const double _fogStartM = 120;
const double _fogRangeM = 450;
const double _fogMax = 0.85;

/// 면 밝기 = 주변광 + 확산광 × max(0, 법선·빛).
const double _ambient = 0.6;
const double _diffuse = 0.4;
const _V3 _light = _V3(0.35, 0.85, 0.4);
const _V3 _worldUp = _V3(0, 1, 0);

/// 카메라 방향은 차 방향보다 넓게 보고 정한다(작은 흔들림에 화면이 떨지 않게).
const double _cameraHeadingLookM = 20;

/// 경사(차 앞뒤 기울기)를 잴 때 앞뒤로 보는 점 수.
const int _slopeSamples = 2;

/// 카메라마다: 눈 위치(차 기준 뒤·옆·위, m), 바라보는 곳(차 기준 앞·위, m), 세로 화각(도), 그리는 반경(m).
typedef _CameraRig = ({double back, double side, double up, double lookAhead, double lookUp, double fovDegrees, double radiusM});

const Map<ReplayCamera, _CameraRig> _rigs = {
  ReplayCamera.chase: (back: 8.5, side: 0, up: 3, lookAhead: 10, lookUp: 1, fovDegrees: 55, radiusM: 420),
  ReplayCamera.broadcast: (back: 18, side: 38, up: 12, lookAhead: 0, lookUp: 0.5, fovDegrees: 28, radiusM: 320),
  ReplayCamera.helicopter: (back: 40, side: 0, up: 55, lookAhead: 25, lookUp: 0, fovDegrees: 42, radiusM: 520),
};

/// 로우폴리 F1 차 상자들(차 기준 m: 앞뒤 [f0, f1]·옆 [s0, s1]·위 [u0, u1], 앞 = +, 길이 약 5.6m·폭 2m). body = 팀 색, 아니면 어두운 색.
const List<({double f0, double f1, double s0, double s1, double u0, double u1, bool body})> _carBoxes = [
  (f0: -2.2, f1: 2.0, s0: -0.75, s1: 0.75, u0: 0.05, u1: 0.15, body: false), // 플로어
  (f0: -0.6, f1: 1.0, s0: -0.42, s1: 0.42, u0: 0.15, u1: 0.62, body: true), // 모노코크
  (f0: 1.0, f1: 2.5, s0: -0.18, s1: 0.18, u0: 0.2, u1: 0.45, body: true), // 노즈
  (f0: -1.2, f1: 0.3, s0: 0.42, s1: 0.75, u0: 0.15, u1: 0.52, body: true), // 사이드포드
  (f0: -1.2, f1: 0.3, s0: -0.75, s1: -0.42, u0: 0.15, u1: 0.52, body: true),
  (f0: -2.0, f1: -0.6, s0: -0.3, s1: 0.3, u0: 0.15, u1: 0.78, body: true), // 엔진 커버
  (f0: -0.7, f1: -0.3, s0: -0.15, s1: 0.15, u0: 0.62, u1: 0.95, body: true), // 에어박스
  (f0: -0.1, f1: 0.35, s0: -0.14, s1: 0.14, u0: 0.62, u1: 0.84, body: false), // 헬멧·헤일로
  (f0: 2.3, f1: 2.8, s0: -0.95, s1: 0.95, u0: 0.05, u1: 0.15, body: true), // 앞날개
  (f0: -2.8, f1: -2.4, s0: -0.75, s1: 0.75, u0: 0.72, u1: 0.95, body: true), // 뒷날개
  (f0: -2.8, f1: -2.3, s0: 0.7, s1: 0.78, u0: 0.25, u1: 0.95, body: false), // 뒷날개 끝판
  (f0: -2.8, f1: -2.3, s0: -0.78, s1: -0.7, u0: 0.25, u1: 0.95, body: false),
  (f0: 1.3, f1: 2.0, s0: 0.62, s1: 0.98, u0: 0, u1: 0.7, body: false), // 앞바퀴
  (f0: 1.3, f1: 2.0, s0: -0.98, s1: -0.62, u0: 0, u1: 0.7, body: false),
  (f0: -2.3, f1: -1.55, s0: 0.58, s1: 1.0, u0: 0, u1: 0.72, body: false), // 뒷바퀴
  (f0: -2.3, f1: -1.55, s0: -1.0, s1: -0.58, u0: 0, u1: 0.72, body: false),
];

/// 상자 면 6개(모서리 번호: bit0 = 앞, bit1 = 옆 +, bit2 = 위). 법선 방향은 그릴 때 바깥으로 맞춘다.
const List<List<int>> _boxFaces = [
  [1, 3, 7, 5], // 앞
  [0, 4, 6, 2], // 뒤
  [2, 6, 7, 3], // 옆 +
  [0, 1, 5, 4], // 옆 −
  [4, 5, 7, 6], // 위
  [0, 2, 3, 1], // 아래
];

/// 3D 시점에 쓰는 서킷 모양: [ReplayCircuit]의 가장자리·연석·그래블·높이에 방호벽 위치를 더한다(한 번 만들어 둔다).
class ReplayTrack3d {
  ReplayTrack3d._({
    required this.circuit,
    required this.outwardLeft,
    required this.outwardRight,
    required this.wallLeftM,
    required this.wallRightM,
    required this.hasWallLeft,
    required this.hasWallRight,
    required this.gravelSide,
    required this.startIndex,
  });

  factory ReplayTrack3d.build(ReplayCircuit circuit) {
    final center = circuit.center;
    final n = center.length;
    int at(int i) => circuit.closed ? (i % n + n) % n : i.clamp(0, n - 1);
    Offset outward(Offset edge, int i) {
      final d = edge - center[i];
      if (d.distance > 0) {
        return d / d.distance;
      }
      final t = center[at(i + 1)] - center[at(i - 1)];
      return t.distance == 0 ? Offset.zero : Offset(-t.dy, t.dx) / t.distance;
    }

    // 그래블은 코너 바깥: 곡률 > 0이면 오른쪽(−1), 아니면 왼쪽(+1). 없으면 0.
    final gravelSide = [
      for (var i = 0; i < n; i++)
        if (!circuit.gravelAt[i]) 0 else if (circuit.curvatures[i] > 0) -1 else 1,
    ];
    List<double> smoothWall(List<bool> kerbs, int side) {
      final raw = [
        for (var i = 0; i < n; i++)
          (kerbs[i] ? kCircuitKerbWidthM : 0) + (gravelSide[i] == side ? kCircuitGravelWidthM : 0) + _runoffM,
      ];
      final widened = [
        for (var i = 0; i < n; i++)
          [for (var k = i - _wallSmoothSamples; k <= i + _wallSmoothSamples; k++) raw[at(k)]].reduce(math.max),
      ];
      return [
        for (var i = 0; i < n; i++)
          [for (var k = i - _wallSmoothSamples; k <= i + _wallSmoothSamples; k++) widened[at(k)]].reduce((a, b) => a + b) /
              (_wallSmoothSamples * 2 + 1),
      ];
    }

    // 다른 구간 도로와 겹치지 않는 거리로 줄인다(격자로 가까운 중심선 점만 본다).
    final grid = <(int, int), List<int>>{};
    (int, int) cell(Offset p) => ((p.dx / _gridCellM).floor(), (p.dy / _gridCellM).floor());
    for (var i = 0; i < n; i++) {
      grid.putIfAbsent(cell(center[i]), () => []).add(i);
    }
    var length = 0.0;
    for (var i = 1; i < n; i++) {
      length += (center[i] - center[i - 1]).distance;
    }
    final window = n < 2 ? n : (_sameStretchM / (length / (n - 1))).ceil();
    bool onOtherRoad(Offset p, int i) {
      final (cx, cz) = cell(p);
      for (var dx = -1; dx <= 1; dx++) {
        for (var dz = -1; dz <= 1; dz++) {
          for (final k in grid[(cx + dx, cz + dz)] ?? const <int>[]) {
            final gap = (k - i).abs();
            if ((circuit.closed ? math.min(gap, n - gap) : gap) <= window) {
              continue;
            }
            final half = math.max(circuit.leftWidths[k], circuit.rightWidths[k]) + _wallClearanceM;
            if ((center[k] - p).distanceSquared < half * half) {
              return true;
            }
          }
        }
      }
      return false;
    }

    ({List<double> offsets, List<bool> standing}) wall(List<Offset> edges, List<Offset> outward, List<bool> kerbs, int side) {
      final smooth = smoothWall(kerbs, side);
      final offsets = <double>[];
      final standing = <bool>[];
      for (var i = 0; i < n; i++) {
        var offset = smooth[i];
        var clear = !onOtherRoad(edges[i] + outward[i] * offset, i);
        for (final f in _wallShrinkSteps) {
          if (clear) {
            break;
          }
          offset = smooth[i] * f;
          clear = !onOtherRoad(edges[i] + outward[i] * offset, i);
        }
        offsets.add(offset);
        standing.add(clear);
      }
      return (offsets: offsets, standing: standing);
    }

    final outwardLeft = [for (var i = 0; i < n; i++) outward(circuit.leftPoints[i], i)];
    final outwardRight = [for (var i = 0; i < n; i++) outward(circuit.rightPoints[i], i)];
    final left = wall(circuit.leftPoints, outwardLeft, circuit.kerbLeft, 1);
    final right = wall(circuit.rightPoints, outwardRight, circuit.kerbRight, -1);

    var start = 0;
    var startDistance = double.infinity;
    for (var i = 0; i < n; i++) {
      final d = (center[i] - circuit.startPoint).distanceSquared;
      if (d < startDistance) {
        startDistance = d;
        start = i;
      }
    }
    return ReplayTrack3d._(
      circuit: circuit,
      outwardLeft: outwardLeft,
      outwardRight: outwardRight,
      wallLeftM: left.offsets,
      wallRightM: right.offsets,
      hasWallLeft: left.standing,
      hasWallRight: right.standing,
      gravelSide: gravelSide,
      startIndex: start,
    );
  }

  final ReplayCircuit circuit;

  /// 점마다 왼쪽·오른쪽 가장자리에서 바깥을 향하는 단위 방향.
  final List<Offset> outwardLeft;
  final List<Offset> outwardRight;

  /// 점마다 가장자리에서 방호벽(과 잔디 끝)까지 거리(m)·그 자리에 벽을 세우는지(다른 구간 도로와 겹치면 세우지 않는다).
  final List<double> wallLeftM;
  final List<double> wallRightM;
  final List<bool> hasWallLeft;
  final List<bool> hasWallRight;

  /// 점마다 그래블이 있는 쪽(+1 왼쪽, −1 오른쪽, 0 없음).
  final List<int> gravelSide;

  /// 출발·결승선 점 번호.
  final int startIndex;

  int get length => circuit.center.length;

  int wrap(int i) => circuit.closed ? (i % length + length) % length : i.clamp(0, length - 1);

  /// 수평 위치 [p]의 노면 높이(m)와 진행 방향 경사(높이 변화 ÷ 거리): 가장 가까운 중심선 구간에 투영해 보간한다.
  ({double elevation, double slope}) locate(Offset p) {
    final center = circuit.center;
    final elevations = circuit.elevations;
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < length; i++) {
      final d = (center[i] - p).distanceSquared;
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    var elevation = elevations[nearest];
    for (final (a, b) in [(wrap(nearest - 1), nearest), (nearest, wrap(nearest + 1))]) {
      final ab = center[b] - center[a];
      final lengthSquared = ab.distanceSquared;
      if (lengthSquared == 0) {
        continue;
      }
      final ap = p - center[a];
      final t = (ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared;
      if (t >= 0 && t <= 1) {
        elevation = elevations[a] + (elevations[b] - elevations[a]) * t;
        break;
      }
    }
    final ahead = wrap(nearest + _slopeSamples);
    final behind = wrap(nearest - _slopeSamples);
    final run = (center[ahead] - center[behind]).distance;
    return (elevation: elevation, slope: run == 0 ? 0 : (elevations[ahead] - elevations[behind]) / run);
  }
}

/// 고스트 재생 3D 시점: [camera]로 서킷(높낮이·잔디·그래블·아스팔트·연석·흰 선·출발선·낮은 방호벽)과
/// 로우폴리 차(고스트는 반투명)를 원근 투영해 그린다. 먼 것부터 칠하고(화가 알고리즘), [time]이 바뀌면 다시 그린다.
class GhostReplay3dPainter extends CustomPainter {
  GhostReplay3dPainter({
    required this.player,
    required this.ghost,
    required this.track,
    required this.camera,
    required this.time,
    required this.playerColor,
    required this.ghostColor,
  }) : super(repaint: time);

  final LapReplay player;
  final LapReplay? ghost;
  final ReplayTrack3d track;
  final ReplayCamera camera;
  final ValueListenable<double> time;
  final Color playerColor;
  final Color ghostColor;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Offset.zero & size;
    canvas.clipRect(viewport);
    if (size.isEmpty) {
      return;
    }
    final elapsed = time.value;
    final frame = player.frameAt(elapsed);
    final spot = track.locate(Offset(frame.x, frame.z));
    final target = _V3(frame.x, spot.elevation, frame.z);
    final heading = player.headingAtDistance(frame.distanceM, lookM: _cameraHeadingLookM);
    final rig = _rigs[camera]!;
    final forward = _V3(math.cos(heading), 0, math.sin(heading));
    final side = _V3(-math.sin(heading), 0, math.cos(heading));
    final view = _View(
      eye: target - forward * rig.back + side * rig.side + _worldUp * rig.up,
      target: target + forward * rig.lookAhead + _worldUp * rig.lookUp,
      fovRadians: rig.fovDegrees * math.pi / 180,
      size: size,
    );

    _paintSky(canvas, size, view, forward);

    // 바닥 구간·방호벽·차를 한데 모아 먼 것부터 칠한다(언덕 너머 낮은 구간의 벽이 앞 도로 위로 비치지 않게).
    final items = <_Item>[];
    _collectTrack(view, Offset(frame.x, frame.z), rig.radiusM, items);
    final ghostReplay = ghost;
    if (ghostReplay != null) {
      items.add(_car(view, ghostReplay.frameAt(elapsed), ghostColor, opacity: kGhostCarOpacity));
    }
    items.add(_car(view, frame, playerColor));

    final batch = _Batch();
    items.sort((a, b) => b.depth.compareTo(a.depth));
    for (final item in items) {
      if (item.opacity < 1) {
        batch.flush(canvas);
        canvas.saveLayer(viewport, Paint()..color = Color.fromRGBO(0, 0, 0, item.opacity));
        batch
          ..addAll(item.faces)
          ..flush(canvas);
        canvas.restore();
      } else {
        batch.addAll(item.faces);
      }
    }
    batch.flush(canvas);
  }

  /// 잔디로 채운 뒤 지평선 위를 하늘 그라데이션으로 칠한다(카메라는 기울지 않아 지평선은 수평).
  void _paintSky(Canvas canvas, Size size, _View view, _V3 forward) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.replayGrass3d);
    final direction = view.direction(forward);
    if (direction.z >= 0) {
      return;
    }
    final horizon = (view.centerY - view.focal * direction.y / -direction.z).clamp(0.0, size.height);
    if (horizon <= 0) {
      return;
    }
    final sky = Rect.fromLTRB(0, 0, size.width, horizon);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.replaySkyTop, AppColors.replaySkyHorizon],
        ).createShader(sky),
    );
  }

  /// 카메라 둘레 [radiusM] 안의 서킷 구간을 바닥 면(잔디·그래블·아스팔트·연석·선) 묶음과 방호벽으로 모은다.
  void _collectTrack(_View view, Offset focus, double radiusM, List<_Item> items) {
    final circuit = track.circuit;
    final n = track.length;
    final segments = circuit.closed ? n : n - 1;
    for (var block = 0; block < segments; block += _lodBlock) {
      final distance = (circuit.center[block] - focus).distance;
      if (distance > radiusM || view.toCamera(_point(block, circuit.center[block])).z > _behindCullM) {
        continue;
      }
      final step = distance < _lodFineM ? 1 : (distance < _lodMidM ? 2 : _lodBlock);
      for (var i = block; i < math.min(block + _lodBlock, segments); i += step) {
        final j = circuit.closed ? math.min(i + step, n) % n : math.min(i + step, n - 1);
        _addSegment(view, i, j, step, items);
      }
    }
  }

  _V3 _point(int i, Offset p, [double lift = 0]) => _V3(p.dx, track.circuit.elevations[i] + lift, p.dy);

  /// 구간 하나. 바닥 묶음의 깊이는 중심선 양 끝 가운데 먼 쪽(차 밑 바닥이 차보다 먼저 칠해지게), 방호벽은 벽 가운데.
  void _addSegment(_View view, int i, int j, int step, List<_Item> items) {
    final circuit = track.circuit;
    final depth = math.max(
      (_point(i, circuit.center[i]) - view.eye).length,
      (_point(j, circuit.center[j]) - view.eye).length,
    );
    final faces = <_Face>[];
    void face(List<_V3> polygon, Color color) {
      final projected = view.projectPolygon(polygon);
      if (projected != null) {
        faces.add((points: projected, color: _shade(color, _normalUp(polygon), depth)));
      }
    }

    final li = circuit.leftPoints[i];
    final lj = circuit.leftPoints[j];
    final ri = circuit.rightPoints[i];
    final rj = circuit.rightPoints[j];
    final oli = track.outwardLeft[i];
    final olj = track.outwardLeft[j];
    final ori = track.outwardRight[i];
    final orj = track.outwardRight[j];

    // 잔디(방호벽 사이 전체) → 그래블 → 아스팔트.
    final wallLi = li + oli * track.wallLeftM[i];
    final wallLj = lj + olj * track.wallLeftM[j];
    final wallRi = ri + ori * track.wallRightM[i];
    final wallRj = rj + orj * track.wallRightM[j];
    face([_point(i, wallLi), _point(j, wallLj), _point(j, wallRj), _point(i, wallRi)], AppColors.replayGrass3d);

    final gravel = track.gravelSide[i];
    if (gravel != 0) {
      final isLeft = gravel > 0;
      final (ei, ej, oi, oj) = isLeft ? (li, lj, oli, olj) : (ri, rj, ori, orj);
      final inset = (isLeft ? circuit.kerbLeft : circuit.kerbRight)[i] ? kCircuitKerbWidthM : 0.0;
      // 그래블은 방호벽(다른 구간과 겹쳐 당긴 곳 포함)을 넘지 않는다.
      final (wi, wj) = isLeft ? (track.wallLeftM[i], track.wallLeftM[j]) : (track.wallRightM[i], track.wallRightM[j]);
      face([
        _point(i, ei + oi * math.min(inset, wi)),
        _point(j, ej + oj * math.min(inset, wj)),
        _point(j, ej + oj * math.min(inset + kCircuitGravelWidthM, wj)),
        _point(i, ei + oi * math.min(inset + kCircuitGravelWidthM, wi)),
      ], AppColors.replayGravel);
    }
    face([_point(i, li), _point(j, lj), _point(j, rj), _point(i, ri)], AppColors.replayAsphalt);

    // 연석(빨강·흰색 번갈아) 또는 흰 가장자리 선.
    final stripes = step == 1 ? 2 : 1;
    for (final (kerbs, ei, ej, oi, oj) in [
      (circuit.kerbLeft, li, lj, oli, olj),
      (circuit.kerbRight, ri, rj, ori, orj),
    ]) {
      if (kerbs[i]) {
        for (var s = 0; s < stripes; s++) {
          final t0 = s / stripes;
          final t1 = (s + 1) / stripes;
          final a = Offset.lerp(ei, ej, t0)!;
          final b = Offset.lerp(ei, ej, t1)!;
          final oa = Offset.lerp(oi, oj, t0)! * kCircuitKerbWidthM;
          final ob = Offset.lerp(oi, oj, t1)! * kCircuitKerbWidthM;
          final color = ((i ~/ step) * stripes + s).isEven ? AppColors.replayKerbRed : AppColors.replayRoadEdge;
          face([_point(i, a), _point(j, b), _point(j, b + ob), _point(i, a + oa)], color);
        }
      } else if (step < _lodBlock) {
        face([
          _point(i, ei - oi * _edgeLineWidthM),
          _point(j, ej - oj * _edgeLineWidthM),
          _point(j, ej),
          _point(i, ei),
        ], AppColors.replayRoadEdge);
      }
    }

    // 출발·결승선: 이 구간에 출발점이 있으면 길을 가로지르는 흰 띠.
    final start = track.startIndex;
    if (start >= i && start < i + step) {
      final along = circuit.center[track.wrap(start + 1)] - circuit.center[track.wrap(start - 1)];
      final unit = along.distance == 0 ? Offset.zero : along / along.distance * (_startLineDepthM / 2);
      final sl = circuit.leftPoints[start];
      final sr = circuit.rightPoints[start];
      face(
        [_point(start, sl - unit), _point(start, sl + unit), _point(start, sr + unit), _point(start, sr - unit)],
        AppColors.replayRoadEdge,
      );
    }
    if (faces.isNotEmpty) {
      items.add((depth: depth, faces: faces, opacity: 1));
    }

    // 낮은 방호벽(양쪽).
    for (final (bi, bj, standing) in [
      (wallLi, wallLj, track.hasWallLeft[i] && track.hasWallLeft[j]),
      (wallRi, wallRj, track.hasWallRight[i] && track.hasWallRight[j]),
    ]) {
      if (!standing) {
        continue;
      }
      final polygon = [_point(i, bi), _point(j, bj), _point(j, bj, _wallHeightM), _point(i, bi, _wallHeightM)];
      final projected = view.projectPolygon(polygon);
      if (projected == null) {
        continue;
      }
      final wallDepth = ((polygon[0] + polygon[2]) * 0.5 - view.eye).length;
      final normal = (polygon[1] - polygon[0]).cross(polygon[3] - polygon[0]).normalized;
      items.add((
        depth: wallDepth,
        faces: [(points: projected, color: _shade(AppColors.replayWall, normal, wallDepth, twoSided: true))],
        opacity: 1,
      ));
    }
  }

  /// 로우폴리 차 한 대: 상자들을 차 방향·노면 경사대로 세우고, 카메라 쪽 면만 먼 것부터 모은다.
  /// 깊이는 차에서 카메라와 가장 가까운 모서리(차 밑 바닥보다 늦게 칠한다).
  _Item _car(_View view, ReplayFrame frame, Color body, {double opacity = 1}) {
    final spot = track.locate(Offset(frame.x, frame.z));
    final pitch = math.atan(spot.slope);
    final (sh, ch) = (math.sin(frame.heading), math.cos(frame.heading));
    final (sp, cp) = (math.sin(pitch), math.cos(pitch));
    final forward = _V3(ch * cp, sp, sh * cp);
    final side = _V3(-sh, 0, ch);
    final up = _V3(-ch * sp, cp, -sh * sp);
    final origin = _V3(frame.x, spot.elevation, frame.z);
    final shade = (origin - view.eye).length;
    var depth = double.infinity;
    final faces = <({double depth, _Face face})>[];
    for (final box in _carBoxes) {
      final corners = [
        for (var c = 0; c < 8; c++)
          origin +
              forward * (c & 1 == 0 ? box.f0 : box.f1) +
              side * (c & 2 == 0 ? box.s0 : box.s1) +
              up * (c & 4 == 0 ? box.u0 : box.u1),
      ];
      for (final corner in corners) {
        depth = math.min(depth, (corner - view.eye).length);
      }
      final color = box.body ? body : AppColors.replayCarDark;
      final boxCenter = (corners[0] + corners[7]) * 0.5;
      for (final indices in _boxFaces) {
        final polygon = [for (final k in indices) corners[k]];
        final faceCenter = (polygon[0] + polygon[2]) * 0.5;
        // 법선은 상자 가운데에서 바깥을 향하게 맞춘다.
        var normal = (polygon[1] - polygon[0]).cross(polygon[3] - polygon[0]).normalized;
        if (normal.dot(faceCenter - boxCenter) < 0) {
          normal = normal * -1;
        }
        if (normal.dot(faceCenter - view.eye) >= 0) {
          continue;
        }
        final projected = view.projectPolygon(polygon);
        if (projected != null) {
          faces.add((
            depth: (faceCenter - view.eye).length,
            face: (points: projected, color: _shade(color, normal, shade)),
          ));
        }
      }
    }
    faces.sort((a, b) => b.depth.compareTo(a.depth));
    return (depth: depth, faces: [for (final f in faces) f.face], opacity: opacity);
  }

  /// 바닥 면 법선(위를 향하게).
  static _V3 _normalUp(List<_V3> polygon) {
    final normal = (polygon[1] - polygon[0]).cross(polygon[3] - polygon[0]).normalized;
    return normal.y < 0 ? normal * -1 : normal;
  }

  /// 빛 방향으로 밝기를 매기고 거리만큼 지평선 색 안개를 섞는다. [twoSided]면 뒷면도 앞면처럼 밝힌다.
  static Color _shade(Color base, _V3 normal, double distance, {bool twoSided = false}) {
    final lit = normal.dot(_light.normalized);
    final factor = _ambient + _diffuse * math.max(0, twoSided ? lit.abs() : lit);
    final shaded = Color.from(
      alpha: base.a,
      red: (base.r * factor).clamp(0, 1),
      green: (base.g * factor).clamp(0, 1),
      blue: (base.b * factor).clamp(0, 1),
    );
    final fog = ((distance - _fogStartM) / _fogRangeM).clamp(0.0, _fogMax);
    return Color.lerp(shaded, AppColors.replaySkyHorizon, fog)!;
  }

  @override
  bool shouldRepaint(GhostReplay3dPainter oldDelegate) =>
      !identical(oldDelegate.player, player) ||
      !identical(oldDelegate.ghost, ghost) ||
      !identical(oldDelegate.track, track) ||
      oldDelegate.camera != camera ||
      oldDelegate.time != time ||
      oldDelegate.playerColor != playerColor ||
      oldDelegate.ghostColor != ghostColor;
}

/// 3차원 벡터(월드: X·Z 수평, Y 위).
@immutable
class _V3 {
  const _V3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 operator *(double s) => _V3(x * s, y * s, z * s);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) => _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));

  _V3 get normalized {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }
}

/// 원근 카메라: [eye]에서 목표를 바라본다(위 = 월드 Y, 기울지 않음). 카메라 좌표는 오른쪽 x·위 y·뒤 z(앞은 −z).
class _View {
  _View({required this.eye, required _V3 target, required double fovRadians, required Size size})
      : centerX = size.width / 2,
        centerY = size.height / 2,
        focal = size.height / 2 / math.tan(fovRadians / 2) {
    _back = (eye - target).normalized;
    _right = _worldUp.cross(_back).normalized;
    _up = _back.cross(_right);
  }

  final _V3 eye;
  final double centerX;
  final double centerY;
  final double focal;
  late final _V3 _back;
  late final _V3 _right;
  late final _V3 _up;

  /// 월드 방향 → 카메라 좌표 방향.
  _V3 direction(_V3 d) => _V3(d.dot(_right), d.dot(_up), d.dot(_back));

  _V3 toCamera(_V3 p) => direction(p - eye);

  Offset _project(_V3 c) => Offset(centerX + focal * c.x / -c.z, centerY - focal * c.y / -c.z);

  /// 월드 다각형을 카메라 앞 면으로 자른 뒤 화면에 투영한다. 다 잘려 나가면 null.
  List<Offset>? projectPolygon(List<_V3> polygon) {
    final input = [for (final p in polygon) toCamera(p)];
    if (input.every((c) => c.z <= -_nearM)) {
      return [for (final c in input) _project(c)];
    }
    final clipped = <_V3>[];
    for (var k = 0; k < input.length; k++) {
      final a = input[k];
      final b = input[(k + 1) % input.length];
      final aIn = a.z <= -_nearM;
      final bIn = b.z <= -_nearM;
      if (aIn) {
        clipped.add(a);
      }
      if (aIn != bIn) {
        final t = (-_nearM - a.z) / (b.z - a.z);
        clipped.add(a + (b - a) * t);
      }
    }
    return clipped.length < 3 ? null : [for (final c in clipped) _project(c)];
  }
}

/// 화면에 투영한 볼록 다각형과 색.
typedef _Face = ({List<Offset> points, Color color});

/// 한 번에 칠할 묶음: 깊이(카메라에서 m, 먼 것부터 칠한다), 면들(이 순서대로), 불투명도(고스트).
typedef _Item = ({double depth, List<_Face> faces, double opacity});

/// 면들을 삼각형으로 모아 한 번에 칠한다(같은 색 면 사이 이음선이 생기지 않고, 면 수천 개도 가볍다). 넣은 순서대로 덮어 칠한다.
class _Batch {
  final List<Offset> _positions = [];
  final List<Color> _colors = [];

  void addAll(List<_Face> faces) {
    for (final face in faces) {
      final p = face.points;
      for (var k = 1; k < p.length - 1; k++) {
        _positions
          ..add(p[0])
          ..add(p[k])
          ..add(p[k + 1]);
        _colors
          ..add(face.color)
          ..add(face.color)
          ..add(face.color);
      }
    }
  }

  void flush(Canvas canvas) {
    if (_positions.isEmpty) {
      return;
    }
    canvas.drawVertices(Vertices(VertexMode.triangles, _positions, colors: _colors), BlendMode.dst, Paint());
    _positions.clear();
    _colors.clear();
  }
}
