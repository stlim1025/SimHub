import 'dart:ui';

import 'diagram_style.dart';

/// 차 그림의 부품(색 단위). 손상 값이 없는 부품(노즈·서스펜션·섀시)은 중립 회색(docs/15 §2.3).
enum CarPart {
  frontWingLeft,
  frontWingRight,
  nose,
  suspension,
  chassis,
  sidepods,
  floor,
  engineCover,
  diffuser,
  rearWing,
  tyreFrontLeft,
  tyreFrontRight,
  tyreRearLeft,
  tyreRearRight,
}

/// 그림 폭/높이 비율(세로로 긴 위에서 본 차). 둥근 모서리의 세로 반경을 맞출 때 쓴다.
const double kCarAspect = 200 / 320;

// 위에서 본 현대 F1 차, 단위 좌표(0~1). 앞이 위, 좌우 대칭 — 왼쪽 절반을 만들고 거울상으로 오른쪽을 얻는다.
const double _mid = 0.5;

// 바퀴(앞·뒤). 뒷바퀴가 더 넓다.
const double _frontTyreOuter = 0.03;
const double _frontTyreInner = 0.19;
const double _frontTyreTop = 0.11;
const double _frontTyreBottom = 0.23;
const double _rearTyreOuter = 0.015;
const double _rearTyreInner = 0.2;
const double _rearTyreTop = 0.72;
const double _rearTyreBottom = 0.865;
const double _tyreRadius = 0.035;

/// 앞·뒷바퀴 중심의 세로 위치(높이 비율). 마모 배지를 이 높이에 맞춘다.
const double kFrontWheelCenterFactor = (_frontTyreTop + _frontTyreBottom) / 2;
const double kRearWheelCenterFactor = (_rearTyreTop + _rearTyreBottom) / 2;

/// 서스펜션 암: 바퀴 안쪽 한 점에서 섀시 두 점으로 벌어지는 위시본.
const Offset _frontHub = Offset(_frontTyreInner, (_frontTyreTop + _frontTyreBottom) / 2);
const Offset _frontArmFore = Offset(0.455, 0.14);
const Offset _frontArmAft = Offset(0.44, 0.27);
const Offset _rearHub = Offset(_rearTyreInner, (_rearTyreTop + _rearTyreBottom) / 2);
const Offset _rearArmFore = Offset(0.42, 0.74);
const Offset _rearArmAft = Offset(0.43, 0.85);

/// 차 전체를 뒤 → 앞 순서로 그릴 부품 목록.
List<DiagramShape<CarPart>> carShapes() => [
  DiagramShape(CarPart.floor, _floor()),
  DiagramShape(CarPart.suspension, _wishbone(_frontHub, _frontArmFore, _frontArmAft), kind: DiagramShapeKind.line),
  DiagramShape(
    CarPart.suspension,
    mirrorX(_wishbone(_frontHub, _frontArmFore, _frontArmAft)),
    kind: DiagramShapeKind.line,
  ),
  DiagramShape(CarPart.suspension, _wishbone(_rearHub, _rearArmFore, _rearArmAft), kind: DiagramShapeKind.line),
  DiagramShape(
    CarPart.suspension,
    mirrorX(_wishbone(_rearHub, _rearArmFore, _rearArmAft)),
    kind: DiagramShapeKind.line,
  ),
  DiagramShape(CarPart.tyreFrontLeft, _frontTyre()),
  DiagramShape(CarPart.tyreFrontRight, mirrorX(_frontTyre())),
  DiagramShape(CarPart.tyreRearLeft, _rearTyre()),
  DiagramShape(CarPart.tyreRearRight, mirrorX(_rearTyre())),
  DiagramShape(CarPart.sidepods, Path.combine(PathOperation.union, _sidepod(), mirrorX(_sidepod()))),
  DiagramShape(CarPart.diffuser, symmetric(_diffuserHalf())),
  DiagramShape(CarPart.nose, symmetric(_noseHalf())),
  DiagramShape(CarPart.chassis, symmetric(_chassisHalf())),
  DiagramShape(CarPart.engineCover, symmetric(_engineCoverHalf())),
  DiagramShape(CarPart.chassis, _cockpit(), kind: DiagramShapeKind.hole),
  DiagramShape(CarPart.chassis, _halo(), kind: DiagramShapeKind.line),
  DiagramShape(CarPart.frontWingLeft, _frontWing()),
  DiagramShape(CarPart.frontWingRight, mirrorX(_frontWing())),
  DiagramShape(CarPart.rearWing, symmetric(_rearWingHalf())),
];

Path _frontTyre() =>
    roundedRect(_frontTyreOuter, _frontTyreTop, _frontTyreInner, _frontTyreBottom, _tyreRadius, aspect: kCarAspect);

Path _rearTyre() =>
    roundedRect(_rearTyreOuter, _rearTyreTop, _rearTyreInner, _rearTyreBottom, _tyreRadius, aspect: kCarAspect);

Path _wishbone(Offset hub, Offset fore, Offset aft) => Path()
  ..moveTo(fore.dx, fore.dy)
  ..lineTo(hub.dx, hub.dy)
  ..lineTo(aft.dx, aft.dy);

/// 앞날개 왼쪽 판: 가운데에서 바깥으로 갈수록 뒤로 휘는 날개 + 바깥 끝판.
Path _frontWing() {
  final plate = Path()
    ..moveTo(0.475, 0.02)
    ..quadraticBezierTo(0.26, 0.012, 0.07, 0.04)
    ..lineTo(0.07, 0.088)
    ..quadraticBezierTo(0.26, 0.07, 0.475, 0.062)
    ..close();
  return Path.combine(PathOperation.union, plate, roundedRect(0.035, 0.028, 0.075, 0.105, 0.015, aspect: kCarAspect));
}

/// 노즈 콘: 둥근 끝에서 섀시 쪽으로 조금씩 넓어진다.
Path _noseHalf() => Path()
  ..moveTo(_mid, 0.03)
  ..quadraticBezierTo(0.468, 0.03, 0.466, 0.07)
  ..lineTo(0.445, 0.29)
  ..lineTo(_mid, 0.29)
  ..close();

/// 모노코크(조종석 둘레).
Path _chassisHalf() => Path()
  ..moveTo(_mid, 0.27)
  ..lineTo(0.445, 0.27)
  ..quadraticBezierTo(0.405, 0.3, 0.405, 0.36)
  ..lineTo(0.405, 0.53)
  ..quadraticBezierTo(0.405, 0.57, 0.44, 0.58)
  ..lineTo(_mid, 0.58)
  ..close();

/// 사이드포드(왼쪽): 조종석 옆에서 넓게 벌어졌다가 뒤로 좁아지는 콜라병 모양.
Path _sidepod() => Path()
  ..moveTo(0.42, 0.355)
  ..cubicTo(0.3, 0.355, 0.205, 0.375, 0.2, 0.44)
  ..lineTo(0.2, 0.54)
  ..cubicTo(0.2, 0.64, 0.33, 0.7, 0.4, 0.8)
  ..lineTo(0.42, 0.8)
  ..close();

/// 플로어: 사이드포드 바깥으로 보이는 바닥 가장자리, 뒷바퀴 앞에서 안으로 꺾여 디퓨저로 이어진다.
Path _floor() {
  final half = Path()
    ..moveTo(_mid, 0.33)
    ..lineTo(0.42, 0.33)
    ..cubicTo(0.28, 0.335, 0.18, 0.36, 0.175, 0.43)
    ..lineTo(0.175, 0.6)
    ..cubicTo(0.175, 0.66, 0.2, 0.69, 0.235, 0.71)
    ..lineTo(0.27, 0.86)
    ..lineTo(_mid, 0.86)
    ..close();
  return symmetric(half);
}

/// 엔진 커버(에어박스 척추): 조종석 뒤에서 시작해 뒤로 가늘어진다.
Path _engineCoverHalf() => Path()
  ..moveTo(_mid, 0.46)
  ..quadraticBezierTo(0.425, 0.46, 0.415, 0.53)
  ..cubicTo(0.41, 0.65, 0.45, 0.76, 0.465, 0.87)
  ..lineTo(_mid, 0.87)
  ..close();

/// 조종석 구멍.
Path _cockpit() => roundedRect(0.45, 0.385, 0.55, 0.5, 0.05, aspect: kCarAspect);

/// 헤일로: 조종석을 감싸는 고리 + 앞 기둥.
Path _halo() => Path()
  ..addRRect(RRect.fromLTRBR(0.435, 0.37, 0.565, 0.505, const Radius.elliptical(0.065, 0.065 * kCarAspect)))
  ..moveTo(_mid, 0.37)
  ..lineTo(_mid, 0.335);

/// 디퓨저: 뒤 끝의 넓은 사다리꼴.
Path _diffuserHalf() => Path()
  ..moveTo(_mid, 0.85)
  ..lineTo(0.3, 0.85)
  ..lineTo(0.28, 0.9)
  ..quadraticBezierTo(0.28, 0.915, 0.3, 0.915)
  ..lineTo(_mid, 0.915)
  ..close();

/// 뒷날개: 맨 아래 넓은 판 + 양끝 끝판.
Path _rearWingHalf() {
  final plate = Path()
    ..moveTo(_mid, 0.93)
    ..lineTo(0.2, 0.93)
    ..lineTo(0.2, 0.975)
    ..lineTo(_mid, 0.975)
    ..close();
  return Path.combine(PathOperation.union, plate, roundedRect(0.17, 0.915, 0.205, 0.99, 0.012, aspect: kCarAspect));
}
