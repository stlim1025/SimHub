import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ghost_replay_3d_painter.dart';
import 'replay_three_scene.dart';

/// WebGL 다시보기를 켰는지. 웹이 아니면 늘 false.
bool get replayThreeEnabled => false;

/// 웹이 아닌 곳의 three.js 다시보기: WebGL이 없으므로 [fallback](캔버스 그림)을 그대로 그린다.
class ReplayThreeView extends StatelessWidget {
  const ReplayThreeView({
    super.key,
    required this.track,
    required this.cars,
    required this.camera,
    required this.time,
    required this.fallback,
    this.overlay,
    this.grid,
  });

  final ReplayTrack3d track;

  /// 실제 출발 그리드 칸(모르면 null).
  final List<ReplayGridSlot>? grid;
  final List<ReplaySceneCar> cars;
  final ReplayCamera camera;
  final ValueListenable<double> time;
  final Widget fallback;

  /// three.js 그림 위에 얹는 위젯(이름표 등). 대체 그림을 쓸 때는 얹지 않는다(대체 그림이 직접 그린다).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) => fallback;
}
