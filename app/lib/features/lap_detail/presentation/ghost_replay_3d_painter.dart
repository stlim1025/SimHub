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

  /// 코너마다 길 밖 높은 곳에 선 중계 카메라: 차가 다가오면 제자리에서 고개를 돌리며 줌으로 잡고, 지나가면 다음 카메라로 바꾼다.
  broadcast,

  /// 뒤쪽 높은 곳에서 내려다보는 헬기 카메라.
  helicopter,
}

/// 코너 바깥 연석·그래블 너머 방호벽까지의 런오프 폭(m)·방호벽 높이(m).
/// 시가지 서킷은 연석 바로 바깥에 더 높은 벽(콘크리트 벽 + 펜스)이 선다.
const double _runoffM = 3;
const double _wallHeightM = 1;
const double _streetRunoffM = 0.3;
const double _streetWallHeightM = 1.6;

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

/// 점 사이 평균 거리의 최소값(m).
const double _minSpacingM = 0.01;

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

/// 차 둘레 이 거리(m) 안의 바닥 구간(중심선 가운데 기준)은 그 차보다 [_groundBeforeCarM] 먼 것으로 쳐서 먼저 칠한다.
const double _carGroundRadiusM = 14;
const double _groundBeforeCarM = 0.01;

/// 카메라 앞 자르는 면(m).
const double _nearM = 0.3;

/// 안개: 이 거리(m)부터 지평선 색으로 섞기 시작해 [_fogRangeM] 뒤 최대 [_fogMax]까지.
const double _fogStartM = 120;
const double _fogRangeM = 450;
const double _fogMax = 0.85;

/// 면 밝기 = 주변광 + 확산광 × max(0, 법선·빛).
const double _ambient = 0.6;
const double _diffuse = 0.4;

/// 차는 면이 작고 많아 명암을 더 세게 준다(곡면이 드러나게).
const double _carAmbient = 0.42;
const double _carDiffuse = 0.7;
const _V3 _light = _V3(0.35, 0.85, 0.4);
const _V3 _worldUp = _V3(0, 1, 0);

/// 카메라 방향은 차 방향보다 넓게 보고 정한다(작은 흔들림에 화면이 떨지 않게).
const double _cameraHeadingLookM = 20;

/// 중계 카메라: 대략 이 간격(m)마다 하나, 그 둘레에서 가장 급한 코너 바깥에 세운다.
/// 방호벽 밖으로 [_stationBackoffM]·노면 위 [_stationHeightM]. 차가 카메라를 [_stationPassM] 지나면 다음 카메라로 바꾼다.
const double _stationSpacingM = 180;
const double _stationBackoffM = 8;
const double _stationHeightM = 7;
const double _stationPassM = 35;

/// 중계 카메라 줌: 차 둘레 이 높이(m)가 화면 세로에 들도록 화각을 정하고, 화각은 [_minBroadcastFovDegrees]~[_maxBroadcastFovDegrees]로 자른다.
const double _broadcastFrameM = 16;
const double _minBroadcastFovDegrees = 6;
const double _maxBroadcastFovDegrees = 55;
const double _broadcastLookUpM = 0.5;

/// 중계 카메라 바로 앞(이 거리 m 안)의 방호벽은 그리지 않는다(카메라가 벽 너머에 서 있어 화면을 가리지 않게).
const double _broadcastWallClearM = 25;

/// 경사(차 앞뒤 기울기)를 잴 때 앞뒤로 보는 점 수.
const int _slopeSamples = 2;

/// 카메라마다: 눈 위치(차 기준 뒤·옆·위, m), 바라보는 곳(차 기준 앞·위, m), 세로 화각(도), 그리는 반경(m).
typedef _CameraRig = ({double back, double side, double up, double lookAhead, double lookUp, double fovDegrees, double radiusM});

const Map<ReplayCamera, _CameraRig> _rigs = {
  ReplayCamera.chase: (back: 8.5, side: 0, up: 3, lookAhead: 10, lookUp: 1, fovDegrees: 55, radiusM: 420),
  // 중계는 눈 위치·화각을 카메라 자리에서 정한다(여기서는 그리는 반경만 쓴다).
  ReplayCamera.broadcast: (back: 0, side: 0, up: 0, lookAhead: 0, lookUp: 0, fovDegrees: 0, radiusM: 360),
  ReplayCamera.helicopter: (back: 40, side: 0, up: 55, lookAhead: 25, lookUp: 0, fovDegrees: 42, radiusM: 520),
};

/// 차 면을 칠하는 색 종류: 팀 색 몸체, 카본(날개 일부·플로어·헤일로·서스펜션), 타이어, 휠, 타이어 옆 띠(컴파운드 색), 헬멧.
enum _CarPaint { body, carbon, tyre, rim, stripe, helmet }

/// 차 면 하나(차 기준 좌표: x = 앞, y = 옆, z = 위, m). [inside]는 이 면이 둘러싼 부품 안쪽 점(법선을 바깥으로 맞춘다).
typedef _CarFace = ({List<_V3> points, _V3 inside, _CarPaint paint});

/// 차 부품 하나: 면들, 차 기준 상자 범위(최소·최대), 볼록한지(볼록하면 카메라 쪽 면끼리 겹치지 않아 넣은 순서대로 칠한다 —
/// 타이어 옆면 위 휠·띠처럼 겹쳐 붙인 면이 뒤집히지 않게). 볼록하지 않은 몸통은 면끼리 거리순으로 칠한다.
typedef _CarPart = ({List<_CarFace> faces, _V3 min, _V3 max, bool convex});

/// 차 모양을 만드는 치수(m, 현행 F1 — 길이 약 5.6m·폭 2m·휠베이스 3.6m).
const double _frontAxle = 1.65;
const double _rearAxle = -1.95;
const double _frontTyreRadius = 0.36;
const double _rearTyreRadius = 0.37;
const double _rimRadius = 0.24;
const double _tyreStripeInner = 0.27;
const double _tyreStripeOuter = 0.3;
const double _wheelDecalOffset = 0.006;
const int _wheelSides = 16;
const double _haloThickness = 0.035;
const double _armThickness = 0.022;

/// 몸체 단면(앞 → 뒤): 앞뒤 위치와 오른쪽 절반 윤곽(아래 바깥 → 옆 아래 → 옆 위 → 위, 옆·위). 왼쪽은 거울로 잇는다.
/// 노즈는 가늘고 높게, 사이드포드는 아래를 파고(언더컷) 엔진 커버는 에어박스까지 솟았다가 뒤로 좁아진다.
const List<(double, List<(double, double)>)> _bodySections = [
  (2.62, [(0.05, 0.17), (0.08, 0.2), (0.08, 0.25), (0.04, 0.28)]),
  (2.1, [(0.09, 0.16), (0.13, 0.2), (0.13, 0.33), (0.07, 0.38)]),
  (1.5, [(0.13, 0.15), (0.19, 0.21), (0.19, 0.44), (0.11, 0.52)]),
  (0.9, [(0.19, 0.11), (0.29, 0.17), (0.29, 0.53), (0.17, 0.6)]),
  (0.45, [(0.28, 0.07), (0.42, 0.13), (0.42, 0.56), (0.2, 0.64)]),
  (0.15, [(0.5, 0.07), (0.78, 0.22), (0.76, 0.5), (0.28, 0.63)]),
  (-0.5, [(0.46, 0.07), (0.72, 0.18), (0.66, 0.46), (0.15, 0.8)]),
  (-1.2, [(0.32, 0.07), (0.47, 0.14), (0.41, 0.38), (0.1, 0.72)]),
  (-1.9, [(0.18, 0.09), (0.25, 0.14), (0.23, 0.32), (0.07, 0.55)]),
  (-2.45, [(0.09, 0.13), (0.12, 0.17), (0.11, 0.3), (0.04, 0.4)]),
];

/// 헬멧 단면.
const List<(double, List<(double, double)>)> _helmetSections = [
  (0.62, [(0.06, 0.6), (0.1, 0.66), (0.1, 0.75), (0.05, 0.79)]),
  (0.38, [(0.09, 0.6), (0.12, 0.66), (0.12, 0.78), (0.07, 0.83)]),
  (0.16, [(0.06, 0.62), (0.09, 0.66), (0.09, 0.74), (0.04, 0.77)]),
];

/// 차 한 대의 부품들(한 번 만들어 모든 차가 함께 쓴다).
final List<_CarPart> _carMesh = _buildCarMesh();

List<_CarPart> _buildCarMesh() {
  final parts = <_CarPart>[];
  void part(List<_CarFace> faces, {bool convex = true}) {
    final points = [for (final f in faces) ...f.points];
    parts.add((
      faces: faces,
      min: _V3(points.map((p) => p.x).reduce(math.min), points.map((p) => p.y).reduce(math.min), points.map((p) => p.z).reduce(math.min)),
      max: _V3(points.map((p) => p.x).reduce(math.max), points.map((p) => p.y).reduce(math.max), points.map((p) => p.z).reduce(math.max)),
      convex: convex,
    ));
  }

  // 단면을 이어 붙인 몸통(앞뒤 끝은 막는다).
  void loft(List<(double, List<(double, double)>)> sections, _CarPaint paint) {
    final rings = [
      for (final (x, half) in sections)
        [
          for (final (y, z) in half) _V3(x, y, z),
          for (final (y, z) in half.reversed) _V3(x, -y, z),
        ],
    ];
    _V3 middle(List<_V3> ring) => ring.reduce((a, b) => a + b) * (1 / ring.length);
    final faces = <_CarFace>[];
    for (var k = 0; k < rings.length - 1; k++) {
      final a = rings[k];
      final b = rings[k + 1];
      final inside = (middle(a) + middle(b)) * 0.5;
      for (var e = 0; e < a.length; e++) {
        final e1 = (e + 1) % a.length;
        faces.add((points: [a[e], a[e1], b[e1], b[e]], inside: inside, paint: paint));
      }
    }
    final inside = (middle(rings.first) + middle(rings.last)) * 0.5;
    faces
      ..add((points: rings.first, inside: inside, paint: paint))
      ..add((points: rings.last, inside: inside, paint: paint));
    part(faces, convex: false);
  }

  void corners(List<_V3> c, _CarPaint paint) {
    final inside = (c[0] + c[7]) * 0.5;
    part([
      for (final indices in _boxFaces) (points: [for (final k in indices) c[k]], inside: inside, paint: paint),
    ]);
  }

  // 축에 맞춘 상자(옆 [y0, y1]이 한쪽이면 [mirror]로 반대쪽도).
  void box(double x0, double x1, double y0, double y1, double z0, double z1, _CarPaint paint, {bool mirror = false}) {
    for (final sign in mirror ? const [1.0, -1.0] : const [1.0]) {
      corners([
        for (var c = 0; c < 8; c++)
          _V3(c & 1 == 0 ? x0 : x1, sign * (c & 2 == 0 ? y0 : y1), c & 4 == 0 ? z0 : z1),
      ], paint);
    }
  }

  // 두 점을 잇는 가는 막대(헤일로·서스펜션·날개 기둥). [mirror]면 옆을 뒤집은 것도.
  void beam(_V3 from, _V3 to, double thickness, {bool mirror = false}) {
    for (final sign in mirror ? const [1.0, -1.0] : const [1.0]) {
      final p0 = _V3(from.x, from.y * sign, from.z);
      final p1 = _V3(to.x, to.y * sign, to.z);
      final d = (p1 - p0).normalized;
      var a = d.cross(const _V3(0, 0, 1));
      if (a.length < 1e-3) {
        a = d.cross(const _V3(1, 0, 0));
      }
      a = a.normalized * thickness;
      final b = d.cross(a).normalized * thickness;
      corners([
        for (var c = 0; c < 8; c++) (c & 1 == 0 ? p0 : p1) + (c & 2 == 0 ? a * -1 : a) + (c & 4 == 0 ? b * -1 : b),
      ], _CarPaint.carbon);
    }
  }

  // 바퀴: 옆으로 누운 원기둥(타이어) + 바깥·안쪽 면의 휠과 컴파운드 색 띠.
  void wheel(double x, double radius, double y0, double y1) {
    for (final sign in const [1.0, -1.0]) {
      final (inner, outer) = (y0 * sign, y1 * sign);
      final center = _V3(x, (inner + outer) / 2, radius);
      final faces = <_CarFace>[];
      _V3 at(double y, double r, int k) {
        final angle = 2 * math.pi * k / _wheelSides;
        return _V3(x + r * math.cos(angle), y, radius + r * math.sin(angle));
      }

      for (var k = 0; k < _wheelSides; k++) {
        faces.add((
          points: [at(inner, radius, k), at(inner, radius, k + 1), at(outer, radius, k + 1), at(outer, radius, k)],
          inside: center,
          paint: _CarPaint.tyre,
        ));
      }
      for (final (y, out) in [(outer, sign), (inner, -sign)]) {
        final decal = y + out * _wheelDecalOffset;
        faces
          ..add((points: [for (var k = 0; k < _wheelSides; k++) at(y, radius, k)], inside: center, paint: _CarPaint.tyre))
          ..add((points: [for (var k = 0; k < _wheelSides; k++) at(decal, _rimRadius, k)], inside: center, paint: _CarPaint.rim));
        for (var k = 0; k < _wheelSides; k++) {
          faces.add((
            points: [
              at(decal, _tyreStripeInner, k),
              at(decal, _tyreStripeOuter, k),
              at(decal, _tyreStripeOuter, k + 1),
              at(decal, _tyreStripeInner, k + 1),
            ],
            inside: center,
            paint: _CarPaint.stripe,
          ));
        }
      }
      part(faces);
    }
  }

  // 플로어·몸통·조종석·헬멧.
  box(-2.3, 1.4, -0.82, 0.82, 0.03, 0.07, _CarPaint.carbon);
  loft(_bodySections, _CarPaint.body);
  part(const [
    (
      points: [_V3(0.88, 0.16, 0.602), _V3(0.88, -0.16, 0.602), _V3(0.3, -0.19, 0.645), _V3(0.3, 0.19, 0.645)],
      inside: _V3(0.6, 0, 0.4),
      paint: _CarPaint.carbon,
    ),
  ]);
  loft(_helmetSections, _CarPaint.helmet);

  // 롤 후프·에어박스, 샤크핀, 미러.
  box(-0.45, -0.1, -0.11, 0.11, 0.6, 0.93, _CarPaint.body);
  box(-0.32, -0.12, -0.07, 0.07, 0.8, 0.9, _CarPaint.carbon);
  box(-2.3, -0.6, -0.012, 0.012, 0.55, 0.82, _CarPaint.body);
  box(0.52, 0.6, 0.44, 0.6, 0.63, 0.7, _CarPaint.body, mirror: true);
  beam(const _V3(0.56, 0.3, 0.55), const _V3(0.56, 0.46, 0.65), _armThickness, mirror: true);

  // 헤일로.
  beam(const _V3(0.95, 0, 0.57), const _V3(0.72, 0, 0.86), _haloThickness);
  beam(const _V3(0.72, 0, 0.86), const _V3(0.45, 0.2, 0.85), _haloThickness, mirror: true);
  beam(const _V3(0.45, 0.2, 0.85), const _V3(0.05, 0.24, 0.76), _haloThickness, mirror: true);
  beam(const _V3(0.05, 0.24, 0.76), const _V3(-0.15, 0.24, 0.6), _haloThickness, mirror: true);

  // 앞날개: 주 날개(카본) + 플랩 두 장 + 끝판, 노즈 기둥.
  box(2.3, 2.88, -0.98, 0.98, 0.04, 0.08, _CarPaint.carbon);
  box(2.2, 2.55, 0.22, 0.95, 0.09, 0.14, _CarPaint.body, mirror: true);
  box(2.12, 2.38, 0.3, 0.95, 0.15, 0.21, _CarPaint.body, mirror: true);
  box(2.1, 2.88, 0.95, 0.99, 0.04, 0.3, _CarPaint.body, mirror: true);
  beam(const _V3(2.42, 0.07, 0.17), const _V3(2.5, 0.07, 0.08), _armThickness, mirror: true);

  // 뒷날개: 주 날개(카본) + DRS 플랩 + 끝판 + 빔 윙, 가운데 기둥.
  box(-2.98, -2.52, -0.72, 0.72, 0.8, 0.86, _CarPaint.carbon);
  box(-2.88, -2.56, -0.72, 0.72, 0.9, 0.97, _CarPaint.body);
  box(-3.0, -2.42, 0.72, 0.76, 0.4, 1.0, _CarPaint.body, mirror: true);
  box(-2.86, -2.56, -0.5, 0.5, 0.42, 0.46, _CarPaint.carbon);
  beam(const _V3(-2.35, 0, 0.32), const _V3(-2.72, 0, 0.8), _armThickness);

  // 서스펜션 암(위·아래)과 바퀴.
  for (final (x, inner, outer) in [(_frontAxle, 0.18, 0.68), (_rearAxle, 0.24, 0.6)]) {
    beam(_V3(x - 0.1, inner, 0.46), _V3(x, outer, 0.5), _armThickness, mirror: true);
    beam(_V3(x - 0.15, inner, 0.2), _V3(x, outer, 0.2), _armThickness, mirror: true);
  }
  wheel(_frontAxle, _frontTyreRadius, 0.67, 0.97);
  wheel(_rearAxle, _rearTyreRadius, 0.57, 0.97);
  return parts;
}

/// 차 기준 좌표의 축 성분(0 = 앞, 1 = 옆, 2 = 위).
double _axis(_V3 v, int axis) => switch (axis) { 0 => v.x, 1 => v.y, _ => v.z };

/// 두 부품 [a]·[b]의 칠하는 순서를 차 기준 카메라 위치 [camera]로 정한다: 어느 축으로든 서로 떨어져 있으면
/// 카메라 반대쪽 부품을 먼저(−1 = a 먼저, 1 = b 먼저). 모든 축에서 겹치면 0(거리로 정한다).
int _partOrder(_CarPart a, _CarPart b, _V3 camera) {
  for (var axis = 0; axis < 3; axis++) {
    final c = _axis(camera, axis);
    if (_axis(a.max, axis) <= _axis(b.min, axis)) {
      if (c >= _axis(b.min, axis)) {
        return -1;
      }
      if (c <= _axis(a.max, axis)) {
        return 1;
      }
    } else if (_axis(b.max, axis) <= _axis(a.min, axis)) {
      if (c >= _axis(a.min, axis)) {
        return 1;
      }
      if (c <= _axis(b.max, axis)) {
        return -1;
      }
    }
  }
  return 0;
}

/// 상자 면 6개(모서리 번호: bit0 = 앞(끝점), bit1 = 옆 +, bit2 = 위). 법선 방향은 그릴 때 바깥으로 맞춘다.
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
    required this.spacingM,
    required this.stations,
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
          (kerbs[i] ? kCircuitKerbWidthM : 0) +
          (gravelSide[i] == side ? kCircuitGravelWidthM : 0) +
          (circuit.street ? _streetRunoffM : _runoffM),
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
    // 점 사이 평균 거리. 움직이지 않은 트레이스(길이 0)는 1m로 봐서 나눗셈이 터지지 않게 한다.
    final spacing = n < 2 || length <= 0 ? 1.0 : math.max(length / (n - 1), _minSpacingM);
    final window = n < 2 ? n : (_sameStretchM / spacing).ceil();
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

    // 중계 카메라 자리: 간격마다 그 둘레(앞뒤 1/3)에서 곡률이 가장 큰 점의 코너 바깥, 방호벽 밖 높은 곳.
    final step = math.max(1, (_stationSpacingM / spacing).round());
    final picked = <int>{};
    for (var p = 0; p < (circuit.closed ? n : n - 1); p += step) {
      var best = p;
      for (var k = p - step ~/ 3; k <= p + step ~/ 3; k++) {
        final i = at(k);
        if (circuit.curvatures[i].abs() > circuit.curvatures[best].abs()) {
          best = i;
        }
      }
      picked.add(best);
    }
    final stations = [
      for (final i in picked.toList()..sort())
        () {
          // 곡률 > 0이면 코너 중심이 왼쪽 → 바깥은 오른쪽.
          final outerIsRight = circuit.curvatures[i] > 0;
          final position = outerIsRight
              ? circuit.rightPoints[i] + outwardRight[i] * (right.offsets[i] + _stationBackoffM)
              : circuit.leftPoints[i] + outwardLeft[i] * (left.offsets[i] + _stationBackoffM);
          // 높이는 이 카메라가 맡는 앞뒤 구간에서 가장 높은 노면 기준(오르막에서 언덕 아래로 묻히지 않게).
          var top = circuit.elevations[i];
          for (var k = i - step; k <= i + step; k++) {
            top = math.max(top, circuit.elevations[at(k)]);
          }
          return (index: i, position: position, height: top + _stationHeightM);
        }(),
    ];

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
      spacingM: spacing,
      stations: stations,
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

  /// 중심선 점 사이 평균 거리(m).
  final double spacingM;

  /// 중계 카메라 자리(점 번호 순): 맡는 중심선 점, 수평 위치, 높이(m).
  final List<({int index, Offset position, double height})> stations;

  /// 중심선 점 [index]에 있는 차를 찍을 중계 카메라: 차가 아직 [_stationPassM]만큼 지나치지 않은 첫 카메라.
  ({int index, Offset position, double height}) broadcastStation(int index) {
    final pass = (_stationPassM / spacingM).round();
    var chosen = stations.first;
    var nearest = double.infinity;
    for (final station in stations) {
      final ahead = station.index - index + pass;
      final distance = circuit.closed ? ((ahead % length) + length) % length : ahead;
      if (distance >= 0 && distance < nearest) {
        nearest = distance.toDouble();
        chosen = station;
      }
    }
    return chosen;
  }

  int get length => circuit.center.length;

  int wrap(int i) => circuit.closed ? (i % length + length) % length : i.clamp(0, length - 1);

  /// 수평 위치 [p]의 노면 높이(m)와 진행 방향 경사(높이 변화 ÷ 거리), 가장 가까운 중심선 점: 가장 가까운 구간에 투영해 보간한다.
  ({double elevation, double slope, int index}) locate(Offset p) {
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
    return (
      elevation: elevation,
      slope: run == 0 ? 0 : (elevations[ahead] - elevations[behind]) / run,
      index: nearest,
    );
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
    this.playerTyre,
  }) : super(repaint: time);

  final LapReplay player;
  final LapReplay? ghost;
  final ReplayTrack3d track;
  final ReplayCamera camera;
  final ValueListenable<double> time;
  final Color playerColor;
  final Color ghostColor;

  /// 내 차 타이어 옆 띠 색(컴파운드). null이면 띠 없이 고무색.
  final Color? playerTyre;

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
    final _View view;
    if (camera == ReplayCamera.broadcast) {
      // 코너 카메라: 제자리에서 차를 바라보고, 멀수록 줌을 당긴다.
      final station = track.broadcastStation(spot.index);
      final eye = _V3(station.position.dx, station.height, station.position.dy);
      final look = target + _worldUp * _broadcastLookUpM;
      final fov = 2 * math.atan(_broadcastFrameM / 2 / math.max((look - eye).length, 1));
      view = _View(
        eye: eye,
        target: look,
        fovRadians: fov.clamp(_minBroadcastFovDegrees * math.pi / 180, _maxBroadcastFovDegrees * math.pi / 180),
        size: size,
      );
    } else {
      final forward = _V3(math.cos(heading), 0, math.sin(heading));
      final side = _V3(-math.sin(heading), 0, math.cos(heading));
      view = _View(
        eye: target - forward * rig.back + side * rig.side + _worldUp * rig.up,
        target: target + forward * rig.lookAhead + _worldUp * rig.lookUp,
        fovRadians: rig.fovDegrees * math.pi / 180,
        size: size,
      );
    }

    _paintSky(canvas, size, view);

    // 바닥 구간·방호벽·차를 한데 모아 먼 것부터 칠한다(언덕 너머 낮은 구간의 벽이 앞 도로 위로 비치지 않게).
    // 차 둘레 바닥은 늘 그 차보다 먼저 칠한다(연석을 밟아 차가 비스듬할 때 바로 뒤 바닥이 바퀴를 덮지 않게).
    final ghostReplay = ghost;
    final ghostFrame = ghostReplay?.frameAt(elapsed);
    final cars = [
      if (ghostFrame != null)
        (at: Offset(ghostFrame.x, ghostFrame.z), item: _car(view, ghostFrame, ghostColor, opacity: kGhostCarOpacity)),
      (at: Offset(frame.x, frame.z), item: _car(view, frame, playerColor, tyreMark: playerTyre)),
    ];
    final items = <_Item>[for (final car in cars) car.item];
    _collectTrack(view, Offset(frame.x, frame.z), rig.radiusM, items, cars: [for (final c in cars) (at: c.at, depth: c.item.depth)]);

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
  void _paintSky(Canvas canvas, Size size, _View view) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _groundColor);
    final direction = view.direction(view.horizontalForward);
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
  void _collectTrack(
    _View view,
    Offset focus,
    double radiusM,
    List<_Item> items, {
    required List<({Offset at, double depth})> cars,
  }) {
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
        _addSegment(view, i, j, step, items, cars: cars);
      }
    }
  }

  /// 도로 밖 바닥: 시가지 서킷은 회색(보도·건물 바닥), 그 밖은 잔디.
  Color get _groundColor => track.circuit.street ? AppColors.replayStreetGround : AppColors.replayGrass3d;

  _V3 _point(int i, Offset p, [double lift = 0]) => _V3(p.dx, track.circuit.elevations[i] + lift, p.dy);

  /// 구간 하나. 바닥 묶음의 깊이는 중심선 양 끝 가운데 먼 쪽(차 밑 바닥이 차보다 먼저 칠해지게), 방호벽은 벽 가운데.
  void _addSegment(
    _View view,
    int i,
    int j,
    int step,
    List<_Item> items, {
    required List<({Offset at, double depth})> cars,
  }) {
    final circuit = track.circuit;
    final middle = (circuit.center[i] + circuit.center[j]) / 2;
    // [distance]는 실제 거리(밝기·안개), [depth]는 칠하는 순서 — 차 둘레면 그 차보다 조금 먼 것으로 친다.
    // 화면에 안 보이는 차(카메라 뒤 등, 깊이 무한)는 순서에 끼지 않는다(안 그러면 그 둘레 바닥이 맨 먼저 칠해져 덮인다).
    final distance = math.max(
      (_point(i, circuit.center[i]) - view.eye).length,
      (_point(j, circuit.center[j]) - view.eye).length,
    );
    var depth = distance;
    for (final car in cars) {
      if (car.depth.isFinite && (car.at - middle).distance < _carGroundRadiusM) {
        depth = math.max(depth, car.depth + _groundBeforeCarM);
      }
    }
    final faces = <_Face>[];
    void face(List<_V3> polygon, Color color) {
      final projected = view.projectPolygon(polygon);
      if (projected != null) {
        faces.add((points: projected, color: _shade(color, _normalUp(polygon), distance)));
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
    face([_point(i, wallLi), _point(j, wallLj), _point(j, wallRj), _point(i, wallRi)], _groundColor);

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
      final height = track.circuit.street ? _streetWallHeightM : _wallHeightM;
      final polygon = [_point(i, bi), _point(j, bj), _point(j, bj, height), _point(i, bi, height)];
      final projected = view.projectPolygon(polygon);
      if (projected == null) {
        continue;
      }
      final wallDepth = ((polygon[0] + polygon[2]) * 0.5 - view.eye).length;
      if (camera == ReplayCamera.broadcast && wallDepth < _broadcastWallClearM) {
        continue;
      }
      final normal = (polygon[1] - polygon[0]).cross(polygon[3] - polygon[0]).normalized;
      items.add((
        depth: wallDepth,
        faces: [(points: projected, color: _shade(AppColors.replayWall, normal, wallDepth, twoSided: true))],
        opacity: 1,
      ));
    }
  }

  /// 로우폴리 차 한 대: [_carMesh]를 차 방향·노면 경사대로 세우고, 카메라 쪽 면만 먼 것부터 모은다.
  /// 깊이는 차에서 카메라와 가장 가까운 점(차 밑 바닥보다 늦게 칠한다). [tyreMark]는 타이어 옆 띠 색(컴파운드).
  _Item _car(_View view, ReplayFrame frame, Color body, {Color? tyreMark, double opacity = 1}) {
    final spot = track.locate(Offset(frame.x, frame.z));
    final pitch = math.atan(spot.slope);
    final (sh, ch) = (math.sin(frame.heading), math.cos(frame.heading));
    final (sp, cp) = (math.sin(pitch), math.cos(pitch));
    final forward = _V3(ch * cp, sp, sh * cp);
    final side = _V3(-sh, 0, ch);
    final up = _V3(-ch * sp, cp, -sh * sp);
    final origin = _V3(frame.x, spot.elevation, frame.z);
    _V3 place(_V3 local) => origin + forward * local.x + side * local.y + up * local.z;
    final distance = (origin - view.eye).length;
    final colors = {
      _CarPaint.body: body,
      _CarPaint.carbon: AppColors.replayCarDark,
      _CarPaint.tyre: AppColors.replayCarTyre,
      _CarPaint.rim: AppColors.replayCarRim,
      _CarPaint.stripe: tyreMark ?? AppColors.replayCarTyre,
      _CarPaint.helmet: AppColors.replayCarHelmet,
    };
    // 카메라 위치를 차 기준 좌표로(부품 순서를 정할 때).
    final toEye = view.eye - origin;
    final camera = _V3(toEye.dot(forward), toEye.dot(side), toEye.dot(up));
    var depth = double.infinity;
    final visible = <({_CarPart part, double distance, List<_Face> faces})>[];
    for (final part in _carMesh) {
      final faces = <({double depth, _Face face})>[];
      for (final face in part.faces) {
        final polygon = [for (final p in face.points) place(p)];
        final center = polygon.reduce((a, b) => a + b) * (1 / polygon.length);
        var normal = (polygon[1] - polygon[0]).cross(polygon[polygon.length - 1] - polygon[0]).normalized;
        if (normal.dot(center - place(face.inside)) < 0) {
          normal = normal * -1;
        }
        final toFace = center - view.eye;
        if (normal.dot(toFace) >= 0) {
          continue;
        }
        final projected = view.projectPolygon(polygon);
        if (projected == null) {
          continue;
        }
        depth = math.min(depth, toFace.length);
        faces.add((
          depth: toFace.length,
          face: (
            points: projected,
            color: _shade(colors[face.paint]!, normal, distance, ambient: _carAmbient, diffuse: _carDiffuse),
          ),
        ));
      }
      if (faces.isEmpty) {
        continue;
      }
      if (!part.convex) {
        faces.sort((a, b) => b.depth.compareTo(a.depth));
      }
      visible.add((
        part: part,
        distance: (place((part.min + part.max) * 0.5) - view.eye).length,
        faces: [for (final f in faces) f.face],
      ));
    }

    // 부품 순서: 서로 떨어진 부품은 카메라 반대쪽부터(프레임마다 뒤집히지 않게), 정해지지 않으면 먼 것부터.
    final count = visible.length;
    final after = [for (var i = 0; i < count; i++) <int>[]];
    final waiting = List.filled(count, 0);
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        final order = _partOrder(visible[i].part, visible[j].part, camera);
        if (order < 0) {
          after[i].add(j);
          waiting[j]++;
        } else if (order > 0) {
          after[j].add(i);
          waiting[i]++;
        }
      }
    }
    final done = List.filled(count, false);
    final ordered = <_Face>[];
    for (var drawn = 0; drawn < count; drawn++) {
      var next = -1;
      for (final free in [true, false]) {
        for (var i = 0; i < count; i++) {
          if (!done[i] && (!free || waiting[i] == 0) && (next < 0 || visible[i].distance > visible[next].distance)) {
            next = i;
          }
        }
        if (next >= 0) {
          break;
        }
      }
      done[next] = true;
      ordered.addAll(visible[next].faces);
      for (final j in after[next]) {
        waiting[j]--;
      }
    }
    return (depth: depth, faces: ordered, opacity: opacity);
  }

  /// 바닥 면 법선(위를 향하게).
  static _V3 _normalUp(List<_V3> polygon) {
    final normal = (polygon[1] - polygon[0]).cross(polygon[3] - polygon[0]).normalized;
    return normal.y < 0 ? normal * -1 : normal;
  }

  /// 빛 방향으로 밝기를 매기고 거리만큼 지평선 색 안개를 섞는다. [twoSided]면 뒷면도 앞면처럼 밝힌다.
  static Color _shade(
    Color base,
    _V3 normal,
    double distance, {
    bool twoSided = false,
    double ambient = _ambient,
    double diffuse = _diffuse,
  }) {
    final lit = normal.dot(_light.normalized);
    final factor = ambient + diffuse * math.max(0, twoSided ? lit.abs() : lit);
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
      oldDelegate.ghostColor != ghostColor ||
      oldDelegate.playerTyre != playerTyre;
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

  /// 카메라가 보는 방향의 수평 성분(지평선 높이를 잴 때).
  _V3 get horizontalForward => _V3(-_back.x, 0, -_back.z).normalized;

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
