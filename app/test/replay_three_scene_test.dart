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

    test('면 종류별 층: 꼭짓점마다 위치 XYZ·무늬 좌표 UV·색 RGB, 삼각형 단위', () {
      for (final layer in mesh.layers) {
        expect(layer.positions.length % 9, 0, reason: layer.surface.name);
        expect(layer.colors.length, layer.positions.length);
        expect(layer.uvs.length, layer.vertexCount * 2);
      }
      expect(mesh.layers.map((l) => l.surface).toSet().length, mesh.layers.length);
      expect(mesh.vertexCount, greaterThan(track.length * 6));
    });

    test('바닥·아스팔트·선(가장자리와 출발선)이 있고, 넓은 바닥은 잔디 색·가장 낮은 노면 높이', () {
      final asphalt = mesh.layer(ReplaySurface.asphalt)!;
      final ground = mesh.layer(ReplaySurface.ground)!;

      expect(asphalt.colors[0], closeTo(AppColors.replayAsphalt.r, 1e-6));
      expect(ground.colors[0], closeTo(AppColors.replayGrass3d.r, 1e-6));
      expect(mesh.layer(ReplaySurface.line), isNotNull);
      expect(mesh.groundColor, AppColors.replayGrass3d);
      expect(mesh.minElevationM, 0);
      expect(mesh.street, isFalse);
    });

    test('출발선 뒤 그리드 22칸(칸마다 가로선 + 옆 다리 둘)이 흰 선 층에 들어 있고, 좌우를 번갈아 앉는다', () {
      // 반지름 100m 원은 곡률이 커서 둘레가 모두 연석이라 가장자리 선이 없다: 출발선 한 장 뒤에 그리드가 온다.
      const withoutGrid = 6;
      final line = mesh.layer(ReplaySurface.line)!;

      expect(line.vertexCount, withoutGrid + 22 * 3 * 6);
      // 첫 두 칸의 가로선 가운데는 중심선 양쪽에 있다(옆 거리 부호가 다르다).
      Offset barCenter(int slot) {
        final o = (withoutGrid + slot * 3 * 6) * 3;
        final p = line.positions;
        return Offset((p[o] + p[o + 3] + p[o + 6] + p[o + 15]) / 4, (p[o + 2] + p[o + 5] + p[o + 8] + p[o + 17]) / 4);
      }

      final first = barCenter(0).distance;
      final second = barCenter(1).distance;
      expect(first, isNot(closeTo(100, 0.5)));
      expect((first - 100).sign, isNot((second - 100).sign));
    });

    test('아스팔트 무늬 좌표: U는 중심선을 따라 늘고, V는 옆 거리(왼쪽 +, 오른쪽 −)', () {
      final uv = mesh.layer(ReplaySurface.asphalt)!.uvs;
      var maxU = 0.0;
      var minV = 0.0;
      var maxV = 0.0;
      for (var k = 0; k < uv.length; k += 2) {
        maxU = math.max(maxU, uv[k]);
        minV = math.min(minV, uv[k + 1]);
        maxV = math.max(maxV, uv[k + 1]);
      }

      // 반지름 100m 원 둘레(약 628m)를 따라 잰 거리, 길 폭 절반쯤의 옆 거리.
      expect(maxU, closeTo(2 * math.pi * 100, 30));
      expect(maxV, greaterThan(4));
      expect(minV, lessThan(-4));
    });
  });

  group('프레임 상태', () {
    test('카메라 자세 7칸 + 차 수 + 차마다 자세·색·불투명도, 숨은 차는 뺀다', () {
      const elapsed = 3000.0;
      final state = packReplayFrame(
        track,
        [
          (car: player, color: const Color(0xFFFF0000), opacity: 1, tyre: AppColors.tyreSoft),
          (car: _HiddenCar(player), color: const Color(0xFF00FF00), opacity: 0.5, tyre: null),
          (car: player, color: const Color(0xFF0000FF), opacity: 0.5, tyre: null),
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
      expect(state[17], closeTo(frame.steer, 1e-6));
      expect(state[18], closeTo(frame.distanceM, 1e-2));
      expect(state[19], closeTo(AppColors.tyreSoft.r, 1e-6));
      expect(state[8 + kReplayFrameCarStride + 11], kReplayFrameNoTyre); // 고스트는 띠 없음
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
          cars: [(car: player, color: AppColors.accent, opacity: 1, tyre: null)],
          camera: ReplayCamera.chase,
          time: ValueNotifier<double>(0),
          fallback: const Text('fallback'),
        ),
      ),
    );

    expect(find.text('fallback'), findsOneWidget);
  });
}
