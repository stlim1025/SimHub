import 'dart:math' as math;
import 'dart:ui';

import '../../lap_detail/presentation/diagram_style.dart';

/// 그림의 부품 순서(색 목록도 이 순서). Engine Damage는 그림 대신 목록에만 있다(docs/15 §11.3).
enum EnginePart { ice, turboCharger, mguH, mguK, energyStore, controlElectronics, gearbox }

// 위에서 본 F1 V6 하이브리드 파워 유닛 설계도(Cockpit HUD), 정사각형 단위 좌표(0~1). 앞(흡기)이 위, 기어박스가 아래.
// 모서리는 둥글리지 않고 깎는다(카드·버튼과 같은 언어).
const double _mid = 0.5;

// ICE: 위 흡기 플레넘(육각) + 좌우로 벌어진 실린더 뱅크(V) + 아래 크랭크케이스.
const double _plenumHalfTop = 0.07;
const double _plenumHalfWide = 0.12;
const double _plenumTop = 0.03;
const double _plenumShoulder = 0.08;
const double _plenumBottom = 0.22;
const Offset _bankOuterTop = Offset(0.19, 0.2);
const Offset _bankInnerTop = Offset(0.44, 0.2);
const Offset _bankInnerBottom = Offset(0.455, 0.64);
const Offset _bankOuterBottom = Offset(0.26, 0.64);
const double _bankChamfer = 0.03;
const double _crankHalfWidth = 0.22;
const double _crankTop = 0.6;
const double _crankBottom = 0.7;
const double _crankChamfer = 0.03;

// 뱅크 바깥의 배기 헤더(보어마다 한 줄)와 그 줄들이 모이는 컬렉터(뱅크 바깥 변에서 조금 떨어져 나란히).
const double _collectorGap = 0.03;
const double _headerDrop = 0.03;
const double _collectorTop = 0.25;
const double _collectorBottom = 0.68;

// 뱅크마다 실린더 보어 3개(뱅크 가운데 선을 따라).
const List<double> _boreSteps = [0.2, 0.5, 0.8];
const double _boreRadius = 0.043;

// 왼쪽: 터보 컴프레서(하우징 원 + 날개 6장 + 플레넘으로 가는 흡기관).
const Offset _turboCenter = Offset(0.095, 0.41);
const double _turboRadius = 0.075;
const double _turboHubRadius = 0.018;
const int _turboBladeCount = 6;
const double _turboBladeSweep = 0.9;
const double _turboBladeReach = 0.85;
const double _turboBladeBend = 0.6;
const double _turboBladeBendSweep = 0.2;
const Offset _turboDuctStart = Offset(0.095, 0.335);
const Offset _turboDuctControl1 = Offset(0.095, 0.2);
const Offset _turboDuctControl2 = Offset(0.2, 0.1);
const Offset _turboDuctEnd = Offset(0.38, 0.1);
const double _turboDuctHalfWidth = 0.018;

// 오른쪽: MGU-H(축에 달린 전기 모터 — 깎은 몸통 + 권선 줄 + 블록으로 가는 축).
const double _mguHLeft = 0.83;
const double _mguHRight = 0.97;
const double _mguHTop = 0.31;
const double _mguHBottom = 0.53;
const double _mguHChamfer = 0.025;
const int _mguHWindings = 4;
const double _mguHShaftY = 0.42;
const double _mguHShaftStart = 0.75;

// 오른쪽 뱅크 옆에서 아래로 내려가는 배기관(MGU-H 터빈으로 가는 배기 — MGU-H 색).
const Offset _exhaustStart = Offset(0.74, 0.6);
const Offset _exhaustControl1 = Offset(0.86, 0.62);
const Offset _exhaustControl2 = Offset(0.9, 0.72);
const Offset _exhaustEnd = Offset(0.9, 0.95);
const double _exhaustHalfWidth = 0.026;

// V 골 안: Energy Store(배터리 팩, 셀 줄).
const double _esHalfWidth = 0.045;
const double _esTop = 0.22;
const double _esBottom = 0.56;
const double _esChamfer = 0.015;
const int _esCells = 5;

// 왼쪽 아래: Control Electronics(칩 + 양옆 핀).
const double _ceLeft = 0.05;
const double _ceRight = 0.2;
const double _ceTop = 0.6;
const double _ceBottom = 0.74;
const double _ceChamfer = 0.02;
const int _cePins = 4;
const double _cePinLength = 0.025;
const double _ceOuterPinShare = 0.6;

// 크랭크케이스 아래 MGU-K(가로 모터, 세로 리브).
const double _mguKHalfWidth = 0.17;
const double _mguKTop = 0.73;
const double _mguKBottom = 0.8;
const double _mguKChamfer = 0.02;
const int _mguKRibs = 6;

// 맨 아래 기어박스(사다리꼴 케이스 + 기어 2개).
const double _gearboxTopHalf = 0.13;
const double _gearboxBottomHalf = 0.09;
const double _gearboxTop = 0.83;
const double _gearboxBottom = 0.98;
const double _gearRadius = 0.034;
const double _gearOffsetX = 0.045;
const double _gearY = 0.9;

/// 네 모서리를 [c]만큼 깎은 직사각형.
Path _chamferRect(double left, double top, double right, double bottom, double c) => Path()
  ..moveTo(left + c, top)
  ..lineTo(right - c, top)
  ..lineTo(right, top + c)
  ..lineTo(right, bottom - c)
  ..lineTo(right - c, bottom)
  ..lineTo(left + c, bottom)
  ..lineTo(left, bottom - c)
  ..lineTo(left, top + c)
  ..close();

Path _centeredChamfer(double halfWidth, double top, double bottom, double c) =>
    _chamferRect(_mid - halfWidth, top, _mid + halfWidth, bottom, c);

/// 다각형의 모서리를 [c]만큼 깎는다(각 꼭짓점에서 이웃 변을 따라 c씩 들어온 두 점을 잇는다).
Path _chamferPolygon(List<Offset> corners, double c) {
  final path = Path();
  for (var i = 0; i < corners.length; i++) {
    final cur = corners[i];
    Offset toward(Offset target) {
      final d = target - cur;
      return cur + d / d.distance * c;
    }

    final a = toward(corners[(i - 1 + corners.length) % corners.length]);
    final b = toward(corners[(i + 1) % corners.length]);
    if (i == 0) {
      path.moveTo(a.dx, a.dy);
    } else {
      path.lineTo(a.dx, a.dy);
    }
    path.lineTo(b.dx, b.dy);
  }
  return path..close();
}

Path _circle(Offset center, double radius) => Path()..addOval(Rect.fromCircle(center: center, radius: radius));

/// 왼쪽 실린더 뱅크(깎은 사변형).
Path _leftBank() => _chamferPolygon([_bankOuterTop, _bankInnerTop, _bankInnerBottom, _bankOuterBottom], _bankChamfer);

/// ICE 블록: 플레넘 + 두 뱅크 + 크랭크케이스(좌우 대칭).
Path engineBlockPath() {
  final plenum = Path()
    ..moveTo(_mid - _plenumHalfTop, _plenumTop)
    ..lineTo(_mid + _plenumHalfTop, _plenumTop)
    ..lineTo(_mid + _plenumHalfWide, _plenumShoulder)
    ..lineTo(_mid + _plenumHalfWide, _plenumBottom)
    ..lineTo(_mid - _plenumHalfWide, _plenumBottom)
    ..lineTo(_mid - _plenumHalfWide, _plenumShoulder)
    ..close();
  final crank = _centeredChamfer(_crankHalfWidth, _crankTop, _crankBottom, _crankChamfer);
  return Path.combine(PathOperation.union, Path.combine(PathOperation.union, plenum, symmetric(_leftBank())), crank);
}

/// 양쪽 뱅크의 실린더 보어 6개(선).
Path _bores() {
  final left = Path();
  final top = (_bankOuterTop + _bankInnerTop) / 2;
  final bottom = (_bankOuterBottom + _bankInnerBottom) / 2;
  for (final t in _boreSteps) {
    left.addPath(_circle(Offset.lerp(top, bottom, t)!, _boreRadius), Offset.zero);
  }
  return Path()
    ..addPath(left, Offset.zero)
    ..addPath(mirrorX(left), Offset.zero);
}

/// 왼쪽 뱅크 바깥 변에서 [y]의 x.
double _bankOuterX(double y) =>
    _bankOuterTop.dx + (y - _bankOuterTop.dy) * (_bankOuterBottom.dx - _bankOuterTop.dx) / (_bankOuterBottom.dy - _bankOuterTop.dy);

/// 양쪽 배기 헤더(보어 바깥쪽 → 컬렉터)와 컬렉터 선.
Path _exhaustHeaders() {
  final left = Path()
    ..moveTo(_bankOuterX(_collectorTop) - _collectorGap, _collectorTop)
    ..lineTo(_bankOuterX(_collectorBottom) - _collectorGap, _collectorBottom);
  final top = (_bankOuterTop + _bankInnerTop) / 2;
  final bottom = (_bankOuterBottom + _bankInnerBottom) / 2;
  for (final t in _boreSteps) {
    final bore = Offset.lerp(top, bottom, t)!;
    final y = bore.dy + _headerDrop;
    left
      ..moveTo(bore.dx - _boreRadius, bore.dy)
      ..lineTo(_bankOuterX(y) - _collectorGap, y);
  }
  return Path()
    ..addPath(left, Offset.zero)
    ..addPath(mirrorX(left), Offset.zero);
}

/// 터보 컴프레서 하우징(원) + 플레넘으로 가는 흡기관.
Path engineTurboPath() => Path.combine(
      PathOperation.union,
      _circle(_turboCenter, _turboRadius),
      tubePath(_turboDuctStart, _turboDuctControl1, _turboDuctControl2, _turboDuctEnd, _turboDuctHalfWidth),
    );

/// 컴프레서 날개(휘어진 선 6개) + 허브 원.
Path _turboBlades() {
  Offset polar(double angle, double radius) => _turboCenter + Offset(math.cos(angle), math.sin(angle)) * radius;
  final path = _circle(_turboCenter, _turboHubRadius);
  for (var i = 0; i < _turboBladeCount; i++) {
    final angle = 2 * math.pi * i / _turboBladeCount;
    final from = polar(angle, _turboHubRadius);
    final control = polar(angle + _turboBladeSweep * _turboBladeBendSweep, _turboRadius * _turboBladeBend);
    final tip = polar(angle + _turboBladeSweep, _turboRadius * _turboBladeReach);
    path
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, tip.dx, tip.dy);
  }
  return path;
}

/// MGU-H 몸통.
Path engineMguHPath() => _chamferRect(_mguHLeft, _mguHTop, _mguHRight, _mguHBottom, _mguHChamfer);

/// MGU-H 권선 줄 + 블록으로 가는 축.
Path _mguHDetail() {
  final path = Path()
    ..moveTo(_mguHShaftStart, _mguHShaftY)
    ..lineTo(_mguHLeft, _mguHShaftY);
  final step = (_mguHBottom - _mguHTop) / (_mguHWindings + 1);
  for (var i = 1; i <= _mguHWindings; i++) {
    final y = _mguHTop + step * i;
    path
      ..moveTo(_mguHLeft + _mguHChamfer, y)
      ..lineTo(_mguHRight - _mguHChamfer, y);
  }
  return path;
}

/// 배기관.
Path engineExhaustPath() => tubePath(_exhaustStart, _exhaustControl1, _exhaustControl2, _exhaustEnd, _exhaustHalfWidth);

/// Energy Store 팩.
Path engineEnergyStorePath() => _centeredChamfer(_esHalfWidth, _esTop, _esBottom, _esChamfer);

/// 배터리 셀 구분선.
Path _esCellsPath() {
  final path = Path();
  final step = (_esBottom - _esTop) / _esCells;
  for (var i = 1; i < _esCells; i++) {
    final y = _esTop + step * i;
    path
      ..moveTo(_mid - _esHalfWidth, y)
      ..lineTo(_mid + _esHalfWidth, y);
  }
  return path;
}

/// Control Electronics 칩.
Path engineControlElectronicsPath() => _chamferRect(_ceLeft, _ceTop, _ceRight, _ceBottom, _ceChamfer);

/// 칩 양옆 핀(왼쪽은 그림 가장자리에 닿지 않게 짧게).
Path _cePinsPath() {
  final path = Path();
  final step = (_ceBottom - _ceTop) / (_cePins + 1);
  for (var i = 1; i <= _cePins; i++) {
    final y = _ceTop + step * i;
    path
      ..moveTo(_ceLeft - _cePinLength * _ceOuterPinShare, y)
      ..lineTo(_ceLeft, y)
      ..moveTo(_ceRight, y)
      ..lineTo(_ceRight + _cePinLength, y);
  }
  return path;
}

/// MGU-K 몸통.
Path engineMguKPath() => _centeredChamfer(_mguKHalfWidth, _mguKTop, _mguKBottom, _mguKChamfer);

/// MGU-K 냉각 리브.
Path _mguKRibsPath() {
  final path = Path();
  final step = 2 * _mguKHalfWidth / (_mguKRibs + 1);
  for (var i = 1; i <= _mguKRibs; i++) {
    final x = _mid - _mguKHalfWidth + step * i;
    path
      ..moveTo(x, _mguKTop + _mguKChamfer / 2)
      ..lineTo(x, _mguKBottom - _mguKChamfer / 2);
  }
  return path;
}

/// 기어박스 케이스(사다리꼴).
Path engineGearboxPath() => Path()
  ..moveTo(_mid - _gearboxTopHalf, _gearboxTop)
  ..lineTo(_mid + _gearboxTopHalf, _gearboxTop)
  ..lineTo(_mid + _gearboxBottomHalf, _gearboxBottom)
  ..lineTo(_mid - _gearboxBottomHalf, _gearboxBottom)
  ..close();

/// 기어박스 안 기어 2개.
Path _gearsPath() => Path()
  ..addPath(_circle(const Offset(_mid - _gearOffsetX, _gearY), _gearRadius), Offset.zero)
  ..addPath(_circle(const Offset(_mid + _gearOffsetX, _gearY), _gearRadius), Offset.zero);

/// 그리는 순서대로의 부품(뒤 → 앞). 배기관은 MGU-H 색(MGU-H는 배기 터빈 축에 달린다).
List<DiagramShape<EnginePart>> engineShapes() => [
      DiagramShape(EnginePart.mguH, engineExhaustPath()),
      DiagramShape(EnginePart.ice, engineBlockPath()),
      DiagramShape(EnginePart.ice, _bores(), kind: DiagramShapeKind.line),
      DiagramShape(EnginePart.ice, _exhaustHeaders(), kind: DiagramShapeKind.line),
      DiagramShape(EnginePart.turboCharger, engineTurboPath()),
      DiagramShape(EnginePart.turboCharger, _turboBlades(), kind: DiagramShapeKind.line),
      DiagramShape(EnginePart.mguH, engineMguHPath()),
      DiagramShape(EnginePart.mguH, _mguHDetail(), kind: DiagramShapeKind.line),
      DiagramShape(EnginePart.energyStore, engineEnergyStorePath()),
      DiagramShape(EnginePart.energyStore, _esCellsPath(), kind: DiagramShapeKind.line),
      DiagramShape(EnginePart.controlElectronics, engineControlElectronicsPath()),
      DiagramShape(EnginePart.controlElectronics, _cePinsPath(), kind: DiagramShapeKind.line),
      DiagramShape(EnginePart.mguK, engineMguKPath()),
      DiagramShape(EnginePart.mguK, _mguKRibsPath(), kind: DiagramShapeKind.line),
      DiagramShape(EnginePart.gearbox, engineGearboxPath()),
      DiagramShape(EnginePart.gearbox, _gearsPath(), kind: DiagramShapeKind.line),
    ];
