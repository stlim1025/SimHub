import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// 차 그림의 기본 크기(논리 px).
const double kCarDiagramWidth = 120;
const double kCarDiagramHeight = 220;
const Size kCarDiagramSize = Size(kCarDiagramWidth, kCarDiagramHeight);

/// 앞바퀴·뒷바퀴 중심의 세로 위치(높이 비율). 마모 배지를 이 높이에 맞춘다.
const double kFrontWheelCenterFactor = _frontWheelTop + _frontWheelHeight / 2;
const double kRearWheelCenterFactor = _rearWheelTop + _rearWheelHeight / 2;

// 위에서 본 F1 차의 비율(폭 w·높이 h 기준). 앞이 위다.
const double _frontWingTop = 0;
const double _frontWingHeight = 0.06;
const double _frontWingInset = 0.06;
const double _frontWingCenterGap = 0.04;
const double _noseLeft = 0.42;
const double _noseRight = 0.58;
const double _noseBottom = 0.30;
const double _frontWheelTop = 0.12;
const double _frontWheelHeight = 0.17;
const double _frontWheelWidth = 0.2;
const double _frontWheelInset = 0.02;
const double _bodyLeft = 0.24;
const double _bodyRight = 0.76;
const double _bodyTop = 0.30;
const double _bodyBottom = 0.84;
const double _bodyRadius = 0.08;
const double _cockpitCenterY = 0.44;
const double _cockpitRadiusX = 0.08;
const double _cockpitRadiusY = 0.06;
const double _rearWheelTop = 0.66;
const double _rearWheelHeight = 0.18;
const double _rearWheelWidth = 0.22;
const double _rearWingLeft = 0.16;
const double _rearWingRight = 0.84;
const double _rearWingTop = 0.88;
const double _rearWingBottom = 0.95;
const double _wheelRadius = 4;
const double _outlineWidth = 1.5;

/// 바퀴 순서: FL · FR · RL · RR.
const int _frontLeft = 0;
const int _frontRight = 1;
const int _rearLeft = 2;
const int _rearRight = 3;
const int _wheelCount = 4;

/// 위에서 본 차(docs/15 §2.3 Car & Tyres): 네 바퀴는 마모 단계 색, 앞날개 좌·우는 손상 단계 색, 차체는 테마 색.
/// 색은 위젯이 정해 넘긴다(그림은 계산만 한다).
class CarPainter extends CustomPainter {
  CarPainter({
    required this.wheelColors,
    required this.frontWingLeftColor,
    required this.frontWingRightColor,
    required this.rearWingColor,
    required this.bodyColor,
    required this.outlineColor,
    required this.cockpitColor,
  }) : assert(wheelColors.length == _wheelCount, '바퀴 색은 FL·FR·RL·RR 4개다.');

  /// FL · FR · RL · RR.
  final List<Color> wheelColors;
  final Color frontWingLeftColor;
  final Color frontWingRightColor;
  final Color rearWingColor;
  final Color bodyColor;
  final Color outlineColor;
  final Color cockpitColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _outlineWidth;
    Paint fill(Color color) => Paint()..color = color;

    void shape(RRect rect, Color color) {
      canvas
        ..drawRRect(rect, fill(color))
        ..drawRRect(rect, outline);
    }

    RRect box(double left, double top, double right, double bottom, [double radius = _wheelRadius]) =>
        RRect.fromLTRBR(left, top, right, bottom, Radius.circular(radius));

    // 바퀴(차체 아래에 깔리도록 먼저).
    final frontWheelBottom = (_frontWheelTop + _frontWheelHeight) * h;
    final rearWheelBottom = (_rearWheelTop + _rearWheelHeight) * h;
    shape(box(_frontWheelInset * w, _frontWheelTop * h, (_frontWheelInset + _frontWheelWidth) * w, frontWheelBottom),
        wheelColors[_frontLeft]);
    shape(box((1 - _frontWheelInset - _frontWheelWidth) * w, _frontWheelTop * h, (1 - _frontWheelInset) * w, frontWheelBottom),
        wheelColors[_frontRight]);
    shape(box(0, _rearWheelTop * h, _rearWheelWidth * w, rearWheelBottom), wheelColors[_rearLeft]);
    shape(box((1 - _rearWheelWidth) * w, _rearWheelTop * h, w, rearWheelBottom), wheelColors[_rearRight]);

    // 차체·노즈·조종석.
    shape(box(_bodyLeft * w, _bodyTop * h, _bodyRight * w, _bodyBottom * h, _bodyRadius * w), bodyColor);
    shape(box(_noseLeft * w, _frontWingHeight * h, _noseRight * w, _noseBottom * h), bodyColor);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, _cockpitCenterY * h),
        width: _cockpitRadiusX * 2 * w,
        height: _cockpitRadiusY * 2 * h,
      ),
      fill(cockpitColor),
    );

    // 앞날개 좌·우, 뒷날개.
    final wingBottom = (_frontWingTop + _frontWingHeight) * h;
    shape(box(_frontWingInset * w, _frontWingTop * h, (0.5 - _frontWingCenterGap / 2) * w, wingBottom), frontWingLeftColor);
    shape(box((0.5 + _frontWingCenterGap / 2) * w, _frontWingTop * h, (1 - _frontWingInset) * w, wingBottom), frontWingRightColor);
    shape(box(_rearWingLeft * w, _rearWingTop * h, _rearWingRight * w, _rearWingBottom * h), rearWingColor);
  }

  @override
  bool shouldRepaint(CarPainter oldDelegate) =>
      !listEquals(oldDelegate.wheelColors, wheelColors) ||
      oldDelegate.frontWingLeftColor != frontWingLeftColor ||
      oldDelegate.frontWingRightColor != frontWingRightColor ||
      oldDelegate.rearWingColor != rearWingColor ||
      oldDelegate.bodyColor != bodyColor ||
      oldDelegate.outlineColor != outlineColor ||
      oldDelegate.cockpitColor != cockpitColor;
}
