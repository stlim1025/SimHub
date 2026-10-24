import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../core/theme/app_colors.dart';
import '../domain/ghost_replay.dart';
import 'ghost_replay_3d_painter.dart';
import 'replay_circuit.dart';

/// 바닥 층마다 노면 위로 띄우는 높이(m): 겹친 면이 깜빡이지 않게(잔디 < 그래블 < 아스팔트 < 흰 선 < 연석).
const double _gravelLiftM = 0.02;
const double _asphaltLiftM = 0.04;
const double _edgeLineLiftM = 0.05;

/// 연석 단면 높이(m): 도로 쪽 끝, 가장 솟은 곳(폭의 [_kerbCrownAt] 지점), 바깥 끝. 살짝 솟은 둔덕 모양.
const double _kerbInnerLiftM = 0.045;
const double _kerbCrownLiftM = 0.1;
const double _kerbOuterLiftM = 0.07;
const double _kerbCrownAt = 0.35;

/// 흰 가장자리 선 폭(m, 도로 안쪽으로).
const double _edgeLineWidthM = 0.4;

/// 출발·결승선 폭(m, 진행 방향).
const double _startLineDepthM = 1.2;

/// 출발 그리드: 칸 수, 출발선에서 첫 칸까지와 칸 사이 거리(m, 진행 반대쪽), 칸 앞 가로선 폭·두께, 옆 다리 길이·두께(m),
/// 칸 가운데의 옆 위치(길 절반 폭에 대한 비, 칸마다 좌우 번갈아).
const int _gridSlots = 22;
const double _gridFirstSlotM = 8;
const double _gridSlotGapM = 8;
const double _gridBarWidthM = 2.4;
const double _gridBarDepthM = 0.2;
const double _gridLegLengthM = 1.2;
const double _gridLegWidthM = 0.15;
const double _gridSideRatio = 0.45;

/// 방호벽 위 펜스 높이(m).
const double _fenceHeightM = 2.6;

/// 피트 레인 아스팔트 색(본선보다 조금 밝게).
const double _pitLaneLighten = 0.08;

/// 프레임 상태 묶음: 카메라(눈 XYZ·목표 XYZ·세로 화각) 7칸, 차 수 1칸, 차마다 [kReplayFrameCarStride]칸.
const int _cameraFields = 7;
const int _headerFields = _cameraFields + 1;

/// 차 한 대 칸 수: 기준점 XYZ, 진행 방향, 기울기, 몸체 색 RGB, 불투명도, 스티어, 달린 거리(바퀴 회전), 타이어 띠 색 RGB.
const int kReplayFrameCarStride = 14;

/// 타이어 띠 색을 모를 때 R 칸에 넣는 값(띠를 숨긴다).
const double kReplayFrameNoTyre = -1;

/// 트랙 면 종류(three.js 쪽이 종류마다 재질·무늬를 고른다). 순서 번호를 그대로 넘긴다.
enum ReplaySurface { ground, gravel, asphalt, line, kerb, barrier, fence }

/// 한 면 종류의 삼각형 목록: 꼭짓점 위치 XYZ(월드, m), 무늬 좌표 UV(m — 길이 방향 거리, 옆 거리 또는 높이), 꼭짓점 색 RGB(0~1).
class ReplayTrackLayer {
  const ReplayTrackLayer({required this.surface, required this.positions, required this.uvs, required this.colors});

  final ReplaySurface surface;
  final Float32List positions;
  final Float32List uvs;
  final Float32List colors;

  int get vertexCount => positions.length ~/ 3;
}

/// three.js에 넘기는 트랙 메시: 면 종류별 층, 도로 밖 바닥 색, 시가지인지.
class ReplayTrackMesh {
  const ReplayTrackMesh({required this.layers, required this.groundColor, required this.minElevationM, required this.street});

  final List<ReplayTrackLayer> layers;

  /// 메시 밖 넓은 바닥 색(시가지는 회색, 그 밖은 잔디).
  final Color groundColor;

  /// 가장 낮은 노면 높이(m). 넓은 바닥을 이보다 조금 아래에 깐다.
  final double minElevationM;

  /// 시가지 서킷(방호벽을 콘크리트로, 바닥을 회색으로 그린다).
  final bool street;

  int get vertexCount => layers.fold(0, (sum, layer) => sum + layer.vertexCount);

  /// [surface] 층. 그 면이 하나도 없으면 null.
  ReplayTrackLayer? layer(ReplaySurface surface) {
    for (final l in layers) {
      if (l.surface == surface) {
        return l;
      }
    }
    return null;
  }
}

/// 그릴 차 한 대: 움직임·몸체 색·불투명도(고스트는 반투명)·타이어 옆 띠 색(컴파운드, 모르면 null).
typedef ReplaySceneCar = ({ReplayCar car, Color color, double opacity, Color? tyre});

/// 메시 꼭짓점 하나: 월드 위치와 무늬 좌표(m).
typedef _Vertex = ({double x, double y, double z, double u, double v});

/// 면 종류 하나를 쌓는 버퍼.
class _LayerBuilder {
  _LayerBuilder(this.surface);

  final ReplaySurface surface;
  final positions = <double>[];
  final uvs = <double>[];
  final colors = <double>[];

  void quad(_Vertex a, _Vertex b, _Vertex c, _Vertex d, Color color) {
    for (final p in [a, b, c, a, c, d]) {
      positions
        ..add(p.x)
        ..add(p.y)
        ..add(p.z);
      uvs
        ..add(p.u)
        ..add(p.v);
      colors
        ..add(color.r)
        ..add(color.g)
        ..add(color.b);
    }
  }

  ReplayTrackLayer build() => ReplayTrackLayer(
    surface: surface,
    positions: Float32List.fromList(positions),
    uvs: Float32List.fromList(uvs),
    colors: Float32List.fromList(colors),
  );
}

/// [track]을 three.js 메시로(순수 계산): 방호벽 사이 바닥(잔디), 그래블, 아스팔트, 흰 가장자리 선·출발선, 연석(살짝 솟은 단면),
/// 방호벽, 그 위 펜스, 피트 레인. 층마다 조금씩 띄워 겹친 면이 깜빡이지 않게 한다.
/// 무늬 좌표 U는 중심선을 따라 잰 거리, V는 중심선에서 잰 옆 거리(벽·펜스는 높이)라 무늬가 길을 따라 흐른다.
ReplayTrackMesh buildReplayTrackMesh(ReplayTrack3d track) {
  final circuit = track.circuit;
  final center = circuit.center;
  final n = center.length;
  final ground = circuit.street ? AppColors.replayStreetGround : AppColors.replayGrass3d;
  final layers = {for (final s in ReplaySurface.values) s: _LayerBuilder(s)};

  // 점마다 중심선을 따라 잰 거리(m).
  final along = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    along[i] = along[i - 1] + (center[i] - center[i - 1]).distance;
  }

  // 점 [i]에서 길이 방향 [u]인 꼭짓점: 수평 위치 [p], 노면 위 [lift]. 옆 거리는 중심선에서 잰다(왼쪽 +).
  _Vertex vertex(int i, double u, Offset p, double lift, {required bool left}) {
    final side = (p - center[i]).distance;
    return (x: p.dx, y: circuit.elevations[i] + lift, z: p.dy, u: u, v: left ? side : -side);
  }

  final segments = circuit.closed ? n : n - 1;
  for (var i = 0; i < segments; i++) {
    final j = (i + 1) % n;
    final ui = along[i];
    final uj = ui + (center[j] - center[i]).distance;
    _Vertex li(Offset p, double lift) => vertex(i, ui, p, lift, left: true);
    _Vertex lj(Offset p, double lift) => vertex(j, uj, p, lift, left: true);
    _Vertex ri(Offset p, double lift) => vertex(i, ui, p, lift, left: false);
    _Vertex rj(Offset p, double lift) => vertex(j, uj, p, lift, left: false);

    final leftI = circuit.leftPoints[i];
    final leftJ = circuit.leftPoints[j];
    final rightI = circuit.rightPoints[i];
    final rightJ = circuit.rightPoints[j];
    final oli = track.outwardLeft[i];
    final olj = track.outwardLeft[j];
    final ori = track.outwardRight[i];
    final orj = track.outwardRight[j];

    // 방호벽 사이 바닥(그래블·아스팔트 밑까지, 중심선 양쪽으로 한 장씩).
    layers[ReplaySurface.ground]!
      ..quad(li(leftI + oli * track.wallLeftM[i], 0), lj(leftJ + olj * track.wallLeftM[j], 0), lj(center[j], 0), li(center[i], 0), ground)
      ..quad(ri(center[i], 0), rj(center[j], 0), rj(rightJ + orj * track.wallRightM[j], 0), ri(rightI + ori * track.wallRightM[i], 0), ground);

    final gravel = track.gravelSide[i];
    if (gravel != 0) {
      final isLeft = gravel > 0;
      final (ei, ej, oi, oj) = isLeft ? (leftI, leftJ, oli, olj) : (rightI, rightJ, ori, orj);
      final inset = (isLeft ? circuit.kerbLeft : circuit.kerbRight)[i] ? kCircuitKerbWidthM : 0.0;
      final (wi, wj) = isLeft ? (track.wallLeftM[i], track.wallLeftM[j]) : (track.wallRightM[i], track.wallRightM[j]);
      final (vi, vj) = isLeft ? (li, lj) : (ri, rj);
      layers[ReplaySurface.gravel]!.quad(
        vi(ei + oi * math.min(inset, wi), _gravelLiftM),
        vj(ej + oj * math.min(inset, wj), _gravelLiftM),
        vj(ej + oj * math.min(inset + kCircuitGravelWidthM, wj), _gravelLiftM),
        vi(ei + oi * math.min(inset + kCircuitGravelWidthM, wi), _gravelLiftM),
        AppColors.replayGravel,
      );
    }

    layers[ReplaySurface.asphalt]!
      ..quad(li(leftI, _asphaltLiftM), lj(leftJ, _asphaltLiftM), lj(center[j], _asphaltLiftM), li(center[i], _asphaltLiftM), AppColors.replayAsphalt)
      ..quad(ri(center[i], _asphaltLiftM), rj(center[j], _asphaltLiftM), rj(rightJ, _asphaltLiftM), ri(rightI, _asphaltLiftM), AppColors.replayAsphalt);

    for (final (kerbs, ei, ej, oi, oj, vi, vj) in [
      (circuit.kerbLeft, leftI, leftJ, oli, olj, li, lj),
      (circuit.kerbRight, rightI, rightJ, ori, orj, ri, rj),
    ]) {
      if (kerbs[i]) {
        // 도로 쪽 끝 → 가장 솟은 곳 → 바깥 끝, 두 장으로 둔덕 단면을 만든다. 줄무늬는 무늬가 그린다(꼭짓점 색은 흰색).
        const crown = kCircuitKerbWidthM * _kerbCrownAt;
        layers[ReplaySurface.kerb]!
          ..quad(
            vi(ei, _kerbInnerLiftM),
            vj(ej, _kerbInnerLiftM),
            vj(ej + oj * crown, _kerbCrownLiftM),
            vi(ei + oi * crown, _kerbCrownLiftM),
            AppColors.replayRoadEdge,
          )
          ..quad(
            vi(ei + oi * crown, _kerbCrownLiftM),
            vj(ej + oj * crown, _kerbCrownLiftM),
            vj(ej + oj * kCircuitKerbWidthM, _kerbOuterLiftM),
            vi(ei + oi * kCircuitKerbWidthM, _kerbOuterLiftM),
            AppColors.replayRoadEdge,
          );
      } else {
        layers[ReplaySurface.line]!.quad(
          vi(ei - oi * _edgeLineWidthM, _edgeLineLiftM),
          vj(ej - oj * _edgeLineWidthM, _edgeLineLiftM),
          vj(ej, _edgeLineLiftM),
          vi(ei, _edgeLineLiftM),
          AppColors.replayRoadEdge,
        );
      }
    }

    for (final (standing, edges, outward, offsets) in [
      (track.hasWallLeft, circuit.leftPoints, track.outwardLeft, track.wallLeftM),
      (track.hasWallRight, circuit.rightPoints, track.outwardRight, track.wallRightM),
    ]) {
      if (!standing[i] || !standing[j]) {
        continue;
      }
      final bi = edges[i] + outward[i] * offsets[i];
      final bj = edges[j] + outward[j] * offsets[j];
      // 벽의 무늬 좌표 V는 노면에서 잰 높이, 펜스는 벽 위에서 잰 높이.
      final top = track.wallHeightM;
      _Vertex wall(int k, double u, Offset p, double height, [double base = 0]) =>
          (x: p.dx, y: circuit.elevations[k] + base + height, z: p.dy, u: u, v: height);
      layers[ReplaySurface.barrier]!.quad(wall(i, ui, bi, 0), wall(j, uj, bj, 0), wall(j, uj, bj, top), wall(i, ui, bi, top), AppColors.replayWall);
      layers[ReplaySurface.fence]!.quad(
        wall(i, ui, bi, 0, top),
        wall(j, uj, bj, 0, top),
        wall(j, uj, bj, _fenceHeightM, top),
        wall(i, ui, bi, _fenceHeightM, top),
        AppColors.replayWall,
      );
    }
  }

  // 출발·결승선: 출발점에서 길을 가로지르는 띠.
  final start = track.startIndex;
  final dir = center[track.wrap(start + 1)] - center[track.wrap(start - 1)];
  if (dir.distance > 0) {
    final half = dir / dir.distance * (_startLineDepthM / 2);
    final sl = circuit.leftPoints[start];
    final sr = circuit.rightPoints[start];
    final u = along[start];
    const d = _startLineDepthM / 2;
    _Vertex v(Offset p, double du, {required bool left}) => vertex(start, u + du, p, _edgeLineLiftM, left: left);
    layers[ReplaySurface.line]!.quad(
      v(sl - half, -d, left: true),
      v(sl + half, d, left: true),
      v(sr + half, d, left: false),
      v(sr - half, -d, left: false),
      AppColors.replayRoadEdge,
    );
  }

  // 출발 그리드: 출발선 뒤로 좌우 번갈아 칸마다 앞 가로선과 뒤로 뻗은 옆 다리 두 개(ㄷ 모양).
  final lapLength = circuit.closed ? along[n - 1] + (center[0] - center[n - 1]).distance : along[n - 1];
  for (var k = 0; k < _gridSlots; k++) {
    final spot = _pointAlong(circuit, along, lapLength, along[start] - _gridFirstSlotM - k * _gridSlotGapM);
    if (spot == null) {
      break;
    }
    final (:i, :at, :forward, :leftward, :halfWidth) = spot;
    final slot = at + leftward * (halfWidth * _gridSideRatio * (k.isEven ? 1 : -1));
    final u = along[i];
    _Vertex g(Offset p) => (x: p.dx, y: circuit.elevations[i] + _edgeLineLiftM, z: p.dy, u: u, v: 0);
    void strip(Offset from, Offset to, double width) {
      final d = to - from;
      final side = Offset(-d.dy, d.dx) / d.distance * (width / 2);
      layers[ReplaySurface.line]!.quad(g(from + side), g(to + side), g(to - side), g(from - side), AppColors.replayRoadEdge);
    }

    const halfBar = _gridBarWidthM / 2;
    strip(slot - leftward * halfBar, slot + leftward * halfBar, _gridBarDepthM);
    for (final s in const [1.0, -1.0]) {
      final end = slot + leftward * (s * (halfBar - _gridLegWidthM / 2));
      strip(end, end - forward * _gridLegLengthM, _gridLegWidthM);
    }
  }

  final lane = circuit.pitLane;
  const halfLane = kCircuitPitLaneWidthM / 2;
  final pitColor = Color.lerp(AppColors.replayAsphalt, AppColors.replayRoadEdge, _pitLaneLighten)!;
  var laneU = 0.0;
  for (var i = 0; i + 1 < lane.length; i++) {
    final step = (lane[i + 1] - lane[i]).distance;
    _Vertex pit(int k, double u, double side) {
      final p = lane[k] + circuit.pitNormals[k] * side;
      return (x: p.dx, y: circuit.pitElevations[k] + _asphaltLiftM, z: p.dy, u: u, v: side);
    }

    layers[ReplaySurface.asphalt]!.quad(
      pit(i, laneU, halfLane),
      pit(i + 1, laneU + step, halfLane),
      pit(i + 1, laneU + step, -halfLane),
      pit(i, laneU, -halfLane),
      pitColor,
    );
    laneU += step;
  }

  return ReplayTrackMesh(
    layers: [
      for (final b in layers.values)
        if (b.positions.isNotEmpty) b.build(),
    ],
    groundColor: ground,
    minElevationM: circuit.elevations.isEmpty ? 0 : circuit.elevations.reduce(math.min),
    street: circuit.street,
  );
}

/// 경과 시간 [elapsedMs]의 프레임 상태를 한 줄로 묶는다(순수 계산): 카메라 자세, 보이는 차 수, 차마다 자세·색·불투명도.
/// 카메라는 [cars] 첫 차를 [camera]로 따라간다.
Float32List packReplayFrame(ReplayTrack3d track, List<ReplaySceneCar> cars, ReplayCamera camera, double elapsedMs) {
  final pose = replayCameraPose(track, cars.first.car, camera, elapsedMs);
  final visible = [for (final c in cars) if (c.car.visibleAt(elapsedMs)) c];
  final out = Float32List(_headerFields + visible.length * kReplayFrameCarStride)
    ..[0] = pose.eye.x
    ..[1] = pose.eye.y
    ..[2] = pose.eye.z
    ..[3] = pose.target.x
    ..[4] = pose.target.y
    ..[5] = pose.target.z
    ..[6] = pose.fovRadians
    ..[7] = visible.length.toDouble();
  for (var k = 0; k < visible.length; k++) {
    final car = visible[k];
    final frame = car.car.frameAt(elapsedMs);
    final p = replayCarPose(track, frame);
    final tyre = car.tyre;
    final o = _headerFields + k * kReplayFrameCarStride;
    out
      ..[o] = p.origin.x
      ..[o + 1] = p.origin.y
      ..[o + 2] = p.origin.z
      ..[o + 3] = p.heading
      ..[o + 4] = p.pitch
      ..[o + 5] = car.color.r
      ..[o + 6] = car.color.g
      ..[o + 7] = car.color.b
      ..[o + 8] = car.opacity
      ..[o + 9] = frame.steer
      ..[o + 10] = frame.distanceM
      ..[o + 11] = tyre?.r ?? kReplayFrameNoTyre
      ..[o + 12] = tyre?.g ?? 0
      ..[o + 13] = tyre?.b ?? 0;
  }
  return out;
}

/// 중심선을 따라 [distanceM] 지점(닫힌 서킷은 한 바퀴 [lapLength]로 감는다, 열린 길 밖이면 null):
/// 가장 가까운 앞쪽 점 번호, 위치, 진행 방향·왼쪽 단위 벡터, 그 자리 길 절반 폭.
({int i, Offset at, Offset forward, Offset leftward, double halfWidth})? _pointAlong(
  ReplayCircuit circuit,
  List<double> along,
  double lapLength,
  double distanceM,
) {
  final n = along.length;
  var d = distanceM;
  if (circuit.closed) {
    d %= lapLength;
  } else if (d < 0 || d > along[n - 1]) {
    return null;
  }
  var i = 0;
  while (i + 1 < n && along[i + 1] <= d) {
    i++;
  }
  final j = (i + 1) % n;
  final a = circuit.center[i];
  final step = circuit.center[j] - a;
  if (step.distance == 0) {
    return null;
  }
  final forward = step / step.distance;
  final at = a + forward * (d - along[i]);
  // 왼쪽 가장자리 쪽에서 진행 방향 성분을 뺀 단위 벡터.
  final toLeft = circuit.leftPoints[i] - a;
  final across = toLeft - forward * (toLeft.dx * forward.dx + toLeft.dy * forward.dy);
  if (across.distance == 0) {
    return null;
  }
  return (i: i, at: at, forward: forward, leftward: across / across.distance, halfWidth: toLeft.distance);
}
