import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_palette.dart';
import '../domain/lap_detail_models.dart';
import 'car_geometry.dart';
import 'diagram_style.dart';

export 'car_geometry.dart' show CarPart, kFrontWheelCenterFactor, kRearWheelCenterFactor;

/// 차 그림의 기본 크기(논리 px).
const double kCarDiagramWidth = 200;
const double kCarDiagramHeight = kCarDiagramWidth / kCarAspect;
const Size kCarDiagramSize = Size(kCarDiagramWidth, kCarDiagramHeight);

/// 부품 → 값(docs/15 §2.3): 바퀴 = 랩 끝 타이어 마모, 날개·사이드포드·플로어·디퓨저·엔진 커버 = 손상.
/// 노즈·서스펜션·섀시는 값이 없다(중립).
double? carPartValue(CarPart part, CarSnapshot car) => switch (part) {
  CarPart.tyreFrontLeft => car.tyreWearEnd?.frontLeft,
  CarPart.tyreFrontRight => car.tyreWearEnd?.frontRight,
  CarPart.tyreRearLeft => car.tyreWearEnd?.rearLeft,
  CarPart.tyreRearRight => car.tyreWearEnd?.rearRight,
  CarPart.frontWingLeft => car.frontLeftWingDamage,
  CarPart.frontWingRight => car.frontRightWingDamage,
  CarPart.rearWing => car.rearWingDamage,
  CarPart.sidepods => car.sidepodDamage,
  CarPart.floor => car.floorDamage,
  CarPart.diffuser => car.diffuserDamage,
  CarPart.engineCover => car.engineDamage,
  CarPart.nose || CarPart.suspension || CarPart.chassis => null,
};

/// 부품 색: 마모·손상 단계 색(25/50/75%), 값이 없으면 중립 회색.
Color carColorFor(CarPart part, CarSnapshot car, AppPalette palette) =>
    diagramColorFor(carPartValue(part, car), palette);

/// 위에서 본 F1 차(docs/15 §2.3 Car & Tyres, F1Laps 참고): 부품마다 단계 색의 반투명 채움 + 실선, 조종석은 배경색.
/// 색은 위젯이 정해 넘긴다(그림은 계산만). 모양은 `car_geometry.dart`의 단위 좌표.
class CarPainter extends CustomPainter {
  CarPainter({required this.colors, required this.baseColor, required this.cockpitColor})
    : assert(CarPart.values.every(colors.containsKey), '모든 CarPart의 색이 있어야 한다.');

  final Map<CarPart, Color> colors;

  /// 부품 밑에 까는 불투명 색(카드 표면).
  final Color baseColor;
  final Color cockpitColor;

  static final List<DiagramShape<CarPart>> _shapes = carShapes();

  @override
  void paint(Canvas canvas, Size size) => paintDiagram(
    canvas,
    size,
    _shapes,
    colorOf: (part) => colors[part]!,
    baseColor: baseColor,
    holeColor: cockpitColor,
  );

  @override
  bool shouldRepaint(CarPainter oldDelegate) =>
      !mapEquals(oldDelegate.colors, colors) ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.cockpitColor != cockpitColor;
}
