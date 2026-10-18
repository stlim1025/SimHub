import 'dart:ui';

import '../../lap_detail/presentation/diagram_style.dart';

/// 그림의 부품 순서(색 목록도 이 순서). Engine Damage는 그림 대신 목록에만 있다(docs/15 §11.3).
enum EnginePart { ice, turboCharger, mguH, mguK, energyStore, controlElectronics, gearbox }

// 위에서 본 F1 파워 유닛, 정사각형 단위 좌표(0~1). 앞(흡기)이 위, 기어박스가 아래, 좌우 대칭.
const double _mid = 0.5;

// ICE 블록: 위의 둥근 흡기 스템 → 어깨에서 넓어졌다 아래로 좁아지는 V 몸통.
const double _stemHalfWidth = 0.065;
const double _stemTop = 0.03;
const double _stemBottom = 0.2;
const double _shoulderHalfWidth = 0.21;
const double _shoulderY = 0.34;
const double _shoulderEase = 0.07;
const double _blockBottomHalfWidth = 0.15;
const double _blockBottom = 0.77;
const double _blockCorner = 0.05;

// 블록 안 V자 실린더 뱅크 선.
const double _bankTopHalfWidth = 0.15;
const double _bankTop = 0.38;
const double _bankBottomHalfWidth = 0.11;
const double _bankBottom = 0.73;

// 블록 안: Control Electronics(위) · Energy Store(아래).
const double _ceHalfWidth = 0.075;
const double _ceTop = 0.36;
const double _ceBottom = 0.46;
const double _esHalfWidth = 0.1;
const double _esTop = 0.51;
const double _esBottom = 0.7;
const double _innerRadius = 0.025;

// 양옆 터보·MGU-H 몸통(세로로 긴 둥근 통) + 위의 작은 캡.
const double _podOuter = 0.06;
const double _podInner = 0.23;
const double _podTop = 0.27;
const double _podBottom = 0.69;
const double _podRadius = 0.08;
const double _capOuter = 0.095;
const double _capInner = 0.195;
const double _capTop = 0.18;
const double _capBottom = 0.25;
const double _capRadius = 0.035;

// 오른쪽 블록 옆에서 시작해 아래로 휘는 배기관(중심선 3차 곡선).
const Offset _exhaustStart = Offset(0.62, 0.61);
const Offset _exhaustControl1 = Offset(0.76, 0.63);
const Offset _exhaustControl2 = Offset(0.85, 0.7);
const Offset _exhaustEnd = Offset(0.86, 0.93);
const double _exhaustHalfWidth = 0.028;

// 블록 아래 가로 MGU-K, 그 아래 기어박스 토막.
const double _mguKHalfWidth = 0.13;
const double _mguKTop = 0.795;
const double _mguKBottom = 0.85;
const double _mguKRadius = 0.028;
const double _gearboxHalfWidth = 0.075;
const double _gearboxTop = 0.87;
const double _gearboxBottom = 0.98;
const double _gearboxRadius = 0.015;

/// ICE 블록(왼쪽 절반을 그리고 거울상으로 합친다).
Path engineBlockPath() {
  final half = Path()
    ..moveTo(_mid, _stemTop)
    ..quadraticBezierTo(_mid - _stemHalfWidth, _stemTop, _mid - _stemHalfWidth, _stemTop + _stemHalfWidth)
    ..lineTo(_mid - _stemHalfWidth, _stemBottom)
    ..cubicTo(
      _mid - _stemHalfWidth,
      _stemBottom + _shoulderEase,
      _mid - _shoulderHalfWidth,
      _shoulderY - _shoulderEase,
      _mid - _shoulderHalfWidth,
      _shoulderY,
    )
    ..lineTo(_mid - _blockBottomHalfWidth, _blockBottom - _blockCorner)
    ..quadraticBezierTo(
      _mid - _blockBottomHalfWidth,
      _blockBottom,
      _mid - _blockBottomHalfWidth + _blockCorner,
      _blockBottom,
    )
    ..lineTo(_mid, _blockBottom)
    ..close();
  return symmetric(half);
}

/// 블록 안 좌우 실린더 뱅크 선(V자).
Path _cylinderBanks() {
  final left = Path()
    ..moveTo(_mid - _bankTopHalfWidth, _bankTop)
    ..lineTo(_mid - _bankBottomHalfWidth, _bankBottom);
  return Path()
    ..addPath(left, Offset.zero)
    ..addPath(mirrorX(left), Offset.zero);
}

Path _centered(double halfWidth, double top, double bottom, double radius) =>
    roundedRect(_mid - halfWidth, top, _mid + halfWidth, bottom, radius);

/// 왼쪽 몸통 + 캡(한 부품). 오른쪽은 [mirrorX].
Path enginePodPath() => Path.combine(
  PathOperation.union,
  roundedRect(_podOuter, _podTop, _podInner, _podBottom, _podRadius),
  roundedRect(_capOuter, _capTop, _capInner, _capBottom, _capRadius),
);

/// 배기관.
Path engineExhaustPath() => tubePath(_exhaustStart, _exhaustControl1, _exhaustControl2, _exhaustEnd, _exhaustHalfWidth);

/// 그리는 순서대로의 부품(뒤 → 앞). 배기관은 MGU-H 쪽(오른쪽)에 붙어 같은 색을 쓴다(MGU-H는 배기 터빈 축에 달린다).
List<DiagramShape<EnginePart>> engineShapes() {
  final pod = enginePodPath();
  return [
    DiagramShape(EnginePart.mguH, engineExhaustPath()),
    DiagramShape(EnginePart.turboCharger, pod),
    DiagramShape(EnginePart.mguH, mirrorX(pod)),
    DiagramShape(EnginePart.ice, engineBlockPath()),
    DiagramShape(EnginePart.ice, _cylinderBanks(), kind: DiagramShapeKind.line),
    DiagramShape(EnginePart.controlElectronics, _centered(_ceHalfWidth, _ceTop, _ceBottom, _innerRadius)),
    DiagramShape(EnginePart.energyStore, _centered(_esHalfWidth, _esTop, _esBottom, _innerRadius)),
    DiagramShape(EnginePart.mguK, _centered(_mguKHalfWidth, _mguKTop, _mguKBottom, _mguKRadius)),
    DiagramShape(EnginePart.gearbox, _centered(_gearboxHalfWidth, _gearboxTop, _gearboxBottom, _gearboxRadius)),
  ];
}
