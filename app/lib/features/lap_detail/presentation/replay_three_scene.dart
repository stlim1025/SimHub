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
const double _kerbLiftM = 0.06;

/// 흰 가장자리 선 폭(m, 도로 안쪽으로).
const double _edgeLineWidthM = 0.4;

/// 프레임 상태 묶음: 카메라(눈 XYZ·목표 XYZ·세로 화각) 7칸, 차 수 1칸, 차마다 [kReplayFrameCarStride]칸.
const int _cameraFields = 7;
const int _headerFields = _cameraFields + 1;

/// 차 한 대 칸 수: 기준점 XYZ, 진행 방향, 기울기, 몸체 색 RGB, 불투명도.
const int kReplayFrameCarStride = 9;

/// three.js에 넘기는 트랙 메시(삼각형 목록): 꼭짓점 위치 XYZ(월드, m)와 꼭짓점 색 RGB(0~1), 도로 밖 바닥 색.
class ReplayTrackMesh {
  const ReplayTrackMesh({required this.positions, required this.colors, required this.groundColor, required this.minElevationM});

  final Float32List positions;
  final Float32List colors;

  /// 메시 밖 넓은 바닥 색(시가지는 회색, 그 밖은 잔디).
  final Color groundColor;

  /// 가장 낮은 노면 높이(m). 넓은 바닥을 이보다 조금 아래에 깐다.
  final double minElevationM;

  int get vertexCount => positions.length ~/ 3;
}

/// 그릴 차 한 대: 움직임·몸체 색·불투명도(고스트는 반투명).
typedef ReplaySceneCar = ({ReplayCar car, Color color, double opacity});

/// [track]을 three.js 메시로(순수 계산): 방호벽 사이 바닥, 그래블, 아스팔트, 흰 가장자리 선, 연석(빨강·흰색 번갈아),
/// 방호벽, 피트 레인. 층마다 조금씩 띄워 겹친 면이 깜빡이지 않게 한다.
ReplayTrackMesh buildReplayTrackMesh(ReplayTrack3d track) {
  final circuit = track.circuit;
  final n = circuit.center.length;
  final positions = <double>[];
  final colors = <double>[];
  final ground = circuit.street ? AppColors.replayStreetGround : AppColors.replayGrass3d;

  void triangle(List<(double, double, double)> points, Color color) {
    for (final (x, y, z) in points) {
      positions
        ..add(x)
        ..add(y)
        ..add(z);
      colors
        ..add(color.r)
        ..add(color.g)
        ..add(color.b);
    }
  }

  void quad((double, double, double) a, (double, double, double) b, (double, double, double) c, (double, double, double) d, Color color) {
    triangle([a, b, c], color);
    triangle([a, c, d], color);
  }

  (double, double, double) at(int i, Offset p, double lift) => (p.dx, circuit.elevations[i] + lift, p.dy);

  final segments = circuit.closed ? n : n - 1;
  for (var i = 0; i < segments; i++) {
    final j = (i + 1) % n;
    final li = circuit.leftPoints[i];
    final lj = circuit.leftPoints[j];
    final ri = circuit.rightPoints[i];
    final rj = circuit.rightPoints[j];
    final oli = track.outwardLeft[i];
    final olj = track.outwardLeft[j];
    final ori = track.outwardRight[i];
    final orj = track.outwardRight[j];

    // 방호벽 사이 바닥(그래블·아스팔트 밑까지 한 장).
    quad(
      at(i, li + oli * track.wallLeftM[i], 0),
      at(j, lj + olj * track.wallLeftM[j], 0),
      at(j, rj + orj * track.wallRightM[j], 0),
      at(i, ri + ori * track.wallRightM[i], 0),
      ground,
    );

    final gravel = track.gravelSide[i];
    if (gravel != 0) {
      final isLeft = gravel > 0;
      final (ei, ej, oi, oj) = isLeft ? (li, lj, oli, olj) : (ri, rj, ori, orj);
      final inset = (isLeft ? circuit.kerbLeft : circuit.kerbRight)[i] ? kCircuitKerbWidthM : 0.0;
      final (wi, wj) = isLeft ? (track.wallLeftM[i], track.wallLeftM[j]) : (track.wallRightM[i], track.wallRightM[j]);
      quad(
        at(i, ei + oi * math.min(inset, wi), _gravelLiftM),
        at(j, ej + oj * math.min(inset, wj), _gravelLiftM),
        at(j, ej + oj * math.min(inset + kCircuitGravelWidthM, wj), _gravelLiftM),
        at(i, ei + oi * math.min(inset + kCircuitGravelWidthM, wi), _gravelLiftM),
        AppColors.replayGravel,
      );
    }

    quad(at(i, li, _asphaltLiftM), at(j, lj, _asphaltLiftM), at(j, rj, _asphaltLiftM), at(i, ri, _asphaltLiftM), AppColors.replayAsphalt);

    for (final (kerbs, ei, ej, oi, oj) in [
      (circuit.kerbLeft, li, lj, oli, olj),
      (circuit.kerbRight, ri, rj, ori, orj),
    ]) {
      if (kerbs[i]) {
        quad(
          at(i, ei, _kerbLiftM),
          at(j, ej, _kerbLiftM),
          at(j, ej + oj * kCircuitKerbWidthM, _kerbLiftM),
          at(i, ei + oi * kCircuitKerbWidthM, _kerbLiftM),
          i.isEven ? AppColors.replayKerbRed : AppColors.replayRoadEdge,
        );
      } else {
        quad(
          at(i, ei - oi * _edgeLineWidthM, _edgeLineLiftM),
          at(j, ej - oj * _edgeLineWidthM, _edgeLineLiftM),
          at(j, ej, _edgeLineLiftM),
          at(i, ei, _edgeLineLiftM),
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
      quad(at(i, bi, 0), at(j, bj, 0), at(j, bj, track.wallHeightM), at(i, bi, track.wallHeightM), AppColors.replayWall);
    }
  }

  final lane = circuit.pitLane;
  const half = kCircuitPitLaneWidthM / 2;
  for (var i = 0; i + 1 < lane.length; i++) {
    (double, double, double) pit(int k, double side) {
      final p = lane[k] + circuit.pitNormals[k] * side;
      return (p.dx, circuit.pitElevations[k] + _asphaltLiftM, p.dy);
    }

    quad(pit(i, half), pit(i + 1, half), pit(i + 1, -half), pit(i, -half), AppColors.replayAsphalt);
  }

  return ReplayTrackMesh(
    positions: Float32List.fromList(positions),
    colors: Float32List.fromList(colors),
    groundColor: ground,
    minElevationM: circuit.elevations.isEmpty ? 0 : circuit.elevations.reduce(math.min),
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
    final p = replayCarPose(track, car.car.frameAt(elapsedMs));
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
      ..[o + 8] = car.opacity;
  }
  return out;
}
