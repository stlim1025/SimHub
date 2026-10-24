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
  });

  final ReplayTrack3d track;
  final List<ReplaySceneCar> cars;
  final ReplayCamera camera;
  final ValueListenable<double> time;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => fallback;
}
