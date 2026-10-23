import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/hex_color.dart';
import '../../../core/widgets/team_name_cell.dart';
import '../../laps/domain/lap_models.dart';
import '../domain/ghost_replay.dart';
import 'replay_circuit.dart';

/// 화면 세로 한 칸에 담는 서킷 길이(m). 화면 높이와 상관없이 같은 거리를 보여 차 크기가 일정하게 느껴진다.
const double kReplayViewHeightM = 90;

/// 내 차를 놓는 세로 위치(위에서부터 비율). 가운데보다 아래에 두어 앞쪽 길을 더 보여 준다(앞 약 65m).
const double kReplayPlayerAnchorY = 0.72;

/// 도로 양쪽 흰 가장자리 선 굵기(m).
const double _roadEdgeWidthM = 0.4;

/// 출발·결승선 굵기(m, 진행 방향).
const double _startLineDepthM = 1.2;

/// 고스트 차 몸체 불투명도와 테두리.
const double kGhostCarOpacity = 0.5;
const double _ghostOutlineOpacity = 0.75;
const double _ghostOutlineWidthM = 0.12;

/// 내 차 테두리(어두운 선) 굵기(m).
const double _playerOutlineWidthM = 0.08;

/// 서스펜션 선 굵기(m).
const double _suspensionWidthM = 0.07;

/// 서스펜션이 몸체에 붙는 곳(차 가운데선에서 m, 앞·뒤).
const double _frontSuspensionInner = 0.1;
const double _rearSuspensionInner = 0.15;

/// 화면 위쪽(진행 방향)을 가리키는 각도: 화면 y는 아래로 커지므로 −90°.
const double _screenUp = -math.pi / 2;

/// 차 그림 치수(m, 위에서 본 F1 차 — 길이 약 5.6m·폭 2.0m, 앞이 +x).
const double _carHalfLength = 2.8;
const double _carHalfWidth = 1.0;
const double _rearWingDepth = 0.45;
const double _rearWingHalfSpan = 0.75;
const double _frontWingDepth = 0.32;
const double _frontWingHalfSpan = 0.95;
const double _rearWheelFront = -1.55;
const double _rearWheelBack = -2.3;
const double _rearWheelInner = 0.6;
const double _frontWheelFront = 1.9;
const double _frontWheelBack = 1.3;
const double _frontWheelInner = 0.66;
const double _frontWheelOuter = 0.97;
const double _cockpitCenterX = 0.0;
const double _cockpitLength = 0.95;
const double _cockpitWidth = 0.4;

/// 몸체(엔진 커버·사이드포드·노즈) 윤곽 오른쪽 절반(x, y). 왼쪽은 y를 뒤집어 잇는다.
const List<(double, double)> _bodyHalf = [
  (-2.3, 0.22),
  (-1.6, 0.42),
  (-0.75, 0.72),
  (0.25, 0.66),
  (0.65, 0.28),
  (2.35, 0.12),
  (2.6, 0.0),
];

/// 팀 → 차 몸체 색: 팀 색 글자(`#RRGGBB`)가 맞으면 그 색, 아니면 팀 이름으로 아는 팀 색, 둘 다 없거나 팀이 없으면 [fallback](순수 함수).
Color replayCarColor(LapTeam? team, {required Color fallback}) {
  if (team == null) {
    return fallback;
  }
  return parseHexColor(team.color, fallback: teamColorOfName(team.name) ?? fallback);
}

/// 위에서 본 F1 차 한 대를 칠한다(차 중심이 원점, 앞이 +x, 단위 m). [opacity]는 몸체·바퀴에 적용하고, [outline]은 몸체·날개 테두리(굵기 [outlineWidth] m).
void paintReplayCar(
  Canvas canvas, {
  required Color body,
  double opacity = 1,
  Color? outline,
  double outlineWidth = _playerOutlineWidthM,
}) {
  final dark = Paint()..color = AppColors.replayCarDark.withValues(alpha: opacity);
  final bodyPaint = Paint()..color = body.withValues(alpha: body.a * opacity);

  // 서스펜션(바퀴 ↔ 몸체) — 바퀴 밑에 깔리게 먼저.
  final arms = Paint()
    ..color = dark.color
    ..strokeWidth = _suspensionWidthM
    ..style = PaintingStyle.stroke;
  for (final side in const [1.0, -1.0]) {
    final frontWheelX = (_frontWheelFront + _frontWheelBack) / 2;
    final rearWheelX = (_rearWheelFront + _rearWheelBack) / 2;
    canvas
      ..drawLine(Offset(frontWheelX, side * _frontWheelInner), Offset(frontWheelX, side * _frontSuspensionInner), arms)
      ..drawLine(Offset(rearWheelX, side * _rearWheelInner), Offset(rearWheelX, side * _rearSuspensionInner), arms);
  }

  // 바퀴 넷.
  for (final side in const [1.0, -1.0]) {
    canvas
      ..drawRect(Rect.fromLTRB(_rearWheelBack, side * _rearWheelInner, _rearWheelFront, side * _carHalfWidth), dark)
      ..drawRect(
        Rect.fromLTRB(_frontWheelBack, side * _frontWheelInner, _frontWheelFront, side * _frontWheelOuter),
        dark,
      );
  }

  // 몸체 + 앞뒤 날개(팀 색).
  final bodyPath = Path()..moveTo(_bodyHalf.first.$1, _bodyHalf.first.$2);
  for (final (x, y) in _bodyHalf.skip(1)) {
    bodyPath.lineTo(x, y);
  }
  for (final (x, y) in _bodyHalf.reversed.skip(1)) {
    bodyPath.lineTo(x, -y);
  }
  bodyPath.close();
  final rearWing = Rect.fromLTRB(
    -_carHalfLength,
    -_rearWingHalfSpan,
    -_carHalfLength + _rearWingDepth,
    _rearWingHalfSpan,
  );
  final frontWing = Rect.fromLTRB(
    _carHalfLength - _frontWingDepth,
    -_frontWingHalfSpan,
    _carHalfLength,
    _frontWingHalfSpan,
  );
  final shape = Path()
    ..addPath(bodyPath, Offset.zero)
    ..addRect(rearWing)
    ..addRect(frontWing);
  canvas.drawPath(shape, bodyPaint);
  if (outline != null) {
    canvas.drawPath(
      shape,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth,
    );
  }

  // 조종석(헤일로 안쪽).
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(_cockpitCenterX, 0), width: _cockpitLength, height: _cockpitWidth),
    dark,
  );
}

/// 고스트 재생 추격 카메라: 내 차를 가운데(약간 아래)에 두고 진행 방향이 화면 위를 향하게 돌려,
/// 내 주행선을 따라 아스팔트 길(흰 가장자리)·출발선·고스트 차(반투명)·내 차를 그린다. [time](재생 경과 ms)이 바뀌면 다시 그린다.
class GhostReplayPainter extends CustomPainter {
  GhostReplayPainter({
    required this.player,
    required this.ghost,
    required this.circuit,
    required this.time,
    required this.playerColor,
    required this.ghostColor,
  }) : super(repaint: time);

  final LapReplay player;

  /// 비교 랩 재생기. null이면 고스트 없음.
  final LapReplay? ghost;

  /// 주행 기록으로 추정한 서킷 모양(월드 좌표).
  final ReplayCircuit circuit;
  final ValueListenable<double> time;
  final Color playerColor;
  final Color ghostColor;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Offset.zero & size;
    canvas
      ..clipRect(viewport)
      ..drawRect(viewport, Paint()..color = AppColors.replayGrass);
    if (size.isEmpty) {
      return;
    }
    final elapsed = time.value;
    final frame = player.frameAt(elapsed);
    final scale = size.height / kReplayViewHeightM;

    canvas
      ..save()
      ..translate(size.width / 2, size.height * kReplayPlayerAnchorY)
      ..scale(scale)
      ..rotate(_screenUp - frame.heading)
      ..translate(-frame.x, -frame.z);

    _paintRoad(canvas);
    final ghostReplay = ghost;
    if (ghostReplay != null) {
      _paintCar(
        canvas,
        ghostReplay.frameAt(elapsed),
        body: ghostColor,
        opacity: kGhostCarOpacity,
        outline: AppColors.replayRoadEdge.withValues(alpha: _ghostOutlineOpacity),
        outlineWidth: _ghostOutlineWidthM,
      );
    }
    _paintCar(canvas, frame, body: playerColor, outline: AppColors.replayCarDark);
    canvas.restore();
  }

  /// 그래블(코너 바깥) → 아스팔트 → 연석(빨강·흰색) → 흰 가장자리 선 → 출발·결승선 순으로 칠한다.
  void _paintRoad(Canvas canvas) {
    Paint fill(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = AppColors.replayRoadEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = _roadEdgeWidthM
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(circuit.gravel, fill(AppColors.replayGravel))
      ..drawPath(circuit.asphalt, fill(AppColors.replayAsphalt))
      ..drawPath(circuit.kerbRed, fill(AppColors.replayKerbRed))
      ..drawPath(circuit.kerbWhite, fill(AppColors.replayRoadEdge))
      ..drawPath(circuit.leftEdge, edge)
      ..drawPath(circuit.rightEdge, edge);

    // 출발·결승선: 서킷 중심선 첫 점에서 길을 가로지르는 흰 띠.
    final start = circuit.center.first;
    final next = circuit.center[1];
    final width = circuit.widths.first;
    canvas
      ..save()
      ..translate(start.dx, start.dy)
      ..rotate(math.atan2(next.dy - start.dy, next.dx - start.dx))
      ..drawRect(
        Rect.fromLTRB(-_startLineDepthM / 2, -width / 2, _startLineDepthM / 2, width / 2),
        Paint()..color = AppColors.replayRoadEdge,
      )
      ..restore();
  }

  void _paintCar(
    Canvas canvas,
    ReplayFrame frame, {
    required Color body,
    double opacity = 1,
    Color? outline,
    double outlineWidth = _playerOutlineWidthM,
  }) {
    canvas
      ..save()
      ..translate(frame.x, frame.z)
      ..rotate(frame.heading);
    paintReplayCar(canvas, body: body, opacity: opacity, outline: outline, outlineWidth: outlineWidth);
    canvas.restore();
  }

  @override
  bool shouldRepaint(GhostReplayPainter oldDelegate) =>
      !identical(oldDelegate.player, player) ||
      !identical(oldDelegate.ghost, ghost) ||
      !identical(oldDelegate.circuit, circuit) ||
      oldDelegate.time != time ||
      oldDelegate.playerColor != playerColor ||
      oldDelegate.ghostColor != ghostColor;
}
