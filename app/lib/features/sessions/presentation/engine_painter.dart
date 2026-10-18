import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// 엔진 그림 기본 크기(논리 px).
const Size kEngineDiagramSize = Size(200, 130);

/// 그림의 부품 순서(색 목록도 이 순서). Engine Damage는 그림 대신 목록에만 있다.
enum EnginePart { ice, turboCharger, mguH, mguK, energyStore, controlElectronics, gearbox }

// 옆에서 본 파워 유닛의 비율(폭 w·높이 h 기준).
const Rect _ice = Rect.fromLTRB(0.24, 0.24, 0.62, 0.74);
const Rect _controlElectronics = Rect.fromLTRB(0.34, 0.04, 0.56, 0.18);
const Rect _mguH = Rect.fromLTRB(0.02, 0.62, 0.20, 0.76);
const Rect _mguK = Rect.fromLTRB(0.64, 0.52, 0.76, 0.74);
const Rect _energyStore = Rect.fromLTRB(0.06, 0.80, 0.72, 0.96);
const Rect _gearbox = Rect.fromLTRB(0.78, 0.30, 0.98, 0.72);
const Offset _turboCenter = Offset(0.11, 0.38);
const double _turboRadiusFactor = 0.16;
const int _cylinderLines = 3;
const double _radius = 4;
const double _outlineWidth = 1.5;

/// 엔진 그림(docs/15 §11.3 Engine Wear): 부품마다 마모 단계 색(25/50/75%). 색은 위젯이 정해 넘긴다(그림은 계산만).
/// 차 그림(`CarPainter`)과 같은 방식 — 비율 상수 + 채움 + 테두리.
class EnginePainter extends CustomPainter {
  EnginePainter({required this.partColors, required this.outlineColor})
      : assert(partColors.length == EnginePart.values.length, '부품 색은 EnginePart 순서대로 7개다.');

  /// [EnginePart] 순서.
  final List<Color> partColors;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _outlineWidth;
    Rect scaled(Rect r) => Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height);
    void block(Rect r, EnginePart part) {
      final rect = RRect.fromRectAndRadius(scaled(r), const Radius.circular(_radius));
      canvas
        ..drawRRect(rect, Paint()..color = partColors[part.index])
        ..drawRRect(rect, outline);
    }

    block(_energyStore, EnginePart.energyStore);
    block(_ice, EnginePart.ice);
    // 실린더 구분선(ICE 안).
    final ice = scaled(_ice);
    for (var i = 1; i <= _cylinderLines; i++) {
      final x = ice.left + ice.width * i / (_cylinderLines + 1);
      canvas.drawLine(Offset(x, ice.top), Offset(x, ice.bottom), outline);
    }
    block(_controlElectronics, EnginePart.controlElectronics);
    block(_mguH, EnginePart.mguH);
    block(_mguK, EnginePart.mguK);
    block(_gearbox, EnginePart.gearbox);

    final center = Offset(_turboCenter.dx * size.width, _turboCenter.dy * size.height);
    final radius = _turboRadiusFactor * size.height;
    canvas
      ..drawCircle(center, radius, Paint()..color = partColors[EnginePart.turboCharger.index])
      ..drawCircle(center, radius, outline);
  }

  @override
  bool shouldRepaint(EnginePainter oldDelegate) =>
      !listEquals(oldDelegate.partColors, partColors) || oldDelegate.outlineColor != outlineColor;
}
