import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/features/lap_detail/domain/ghost_replay.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/ghost_replay_3d_painter.dart';
import 'package:simcenter_app/features/lap_detail/presentation/replay_circuit.dart';
import 'package:simcenter_app/features/lap_detail/presentation/replay_three_scene.dart';
import 'package:simcenter_app/features/lap_detail/presentation/replay_three_view.dart';

/// 반지름 100m 원을 도는 랩(표본 5m 간격, 100ms마다).
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

/// 늘 숨는 차(기록이 끊긴 구간을 흉내 낸다).
class _HiddenCar implements ReplayCar {
  _HiddenCar(this.inner);

  final ReplayCar inner;

  @override
  ReplayFrame frameAt(double elapsedMs) => inner.frameAt(elapsedMs);

  @override
  double headingAt(double elapsedMs, {required double lookM}) => inner.headingAt(elapsedMs, lookM: lookM);

  @override
  bool visibleAt(double elapsedMs) => false;
}

void main() {
  final player = LapReplay(_circleLap());
  final track = ReplayTrack3d.build(ReplayCircuit.build(player));

  group('트랙 메시', () {
    final mesh = buildReplayTrackMesh(track);

    test('삼각형 목록: 꼭짓점마다 위치 XYZ와 색 RGB, 꼭짓점 수는 3의 배수', () {
      expect(mesh.positions.length % 9, 0);
      expect(mesh.colors.length, mesh.positions.length);
      expect(mesh.vertexCount, greaterThan(track.length * 6));
    });

    test('아스팔트·바닥 색을 쓰고, 넓은 바닥은 잔디 색·가장 낮은 노면 높이', () {
      bool hasColor(Color c) {
        for (var i = 0; i < mesh.colors.length; i += 3) {
          if ((mesh.colors[i] - c.r).abs() < 1e-6 && (mesh.colors[i + 1] - c.g).abs() < 1e-6 && (mesh.colors[i + 2] - c.b).abs() < 1e-6) {
            return true;
          }
        }
        return false;
      }

      expect(hasColor(AppColors.replayAsphalt), isTrue);
      expect(hasColor(AppColors.replayGrass3d), isTrue);
      expect(mesh.groundColor, AppColors.replayGrass3d);
      expect(mesh.minElevationM, 0);
    });
  });

  group('프레임 상태', () {
    test('카메라 자세 7칸 + 차 수 + 차마다 자세·색·불투명도, 숨은 차는 뺀다', () {
      const elapsed = 3000.0;
      final state = packReplayFrame(
        track,
        [
          (car: player, color: const Color(0xFFFF0000), opacity: 1),
          (car: _HiddenCar(player), color: const Color(0xFF00FF00), opacity: 0.5),
          (car: player, color: const Color(0xFF0000FF), opacity: 0.5),
        ],
        ReplayCamera.chase,
        elapsed,
      );
      final pose = replayCameraPose(track, player, ReplayCamera.chase, elapsed);
      final frame = player.frameAt(elapsed);

      expect(state.length, 8 + 2 * kReplayFrameCarStride);
      expect(state[0], closeTo(pose.eye.x, 1e-3));
      expect(state[4], closeTo(pose.target.y, 1e-3));
      expect(state[6], closeTo(pose.fovRadians, 1e-6));
      expect(state[7], 2);
      expect(state[8], closeTo(frame.x, 1e-3));
      expect(state[10], closeTo(frame.z, 1e-3));
      expect(state[11], closeTo(frame.heading, 1e-5));
      expect(state[13], 1); // 첫 차 빨강
      expect(state[8 + kReplayFrameCarStride + 7], 1); // 둘째로 보이는 차 파랑
      expect(state[8 + kReplayFrameCarStride + 8], 0.5);
    });

    test('추격 카메라는 차 뒤 위에서 차 앞을 본다', () {
      final pose = replayCameraPose(track, player, ReplayCamera.chase, 3000);
      final frame = player.frameAt(3000);
      final toTarget = Offset(pose.target.x - pose.eye.x, pose.target.z - pose.eye.z);
      final forward = Offset(math.cos(frame.heading), math.sin(frame.heading));

      expect(pose.eye.y, greaterThan(pose.target.y));
      expect(toTarget.dx * forward.dx + toTarget.dy * forward.dy, greaterThan(0));
    });
  });

  testWidgets('웹이 아니면 WebGL 다시보기를 켜지 않고 대신 그림을 그린다', (tester) async {
    expect(replayThreeEnabled, isFalse);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ReplayThreeView(
          track: track,
          cars: [(car: player, color: AppColors.accent, opacity: 1)],
          camera: ReplayCamera.chase,
          time: ValueNotifier<double>(0),
          fallback: const Text('fallback'),
        ),
      ),
    );

    expect(find.text('fallback'), findsOneWidget);
  });
}
