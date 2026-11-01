import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../lap_detail/presentation/diagram_style.dart';
import 'engine_geometry.dart';

export 'engine_geometry.dart' show EnginePart;

/// 엔진 그림 기본 크기(논리 px).
const double kEngineDiagramExtent = 210;
const Size kEngineDiagramSize = Size.square(kEngineDiagramExtent);

/// 설계도 느낌: 몸통은 옅게 채우고 테두리는 또렷하게, 보어·권선·셀 같은 세부 선은 가늘게.
const double _bodyFillAlpha = 0.22;
const double _bodyStrokeWidth = 1.6;
const double _detailStrokeWidth = 1.1;

/// HUD 틀: 네 귀퉁이 꺾쇠 길이·굵기와 그림을 틀 안쪽으로 들이는 여백 비율.
const double _bracketLength = 14;
const double _bracketWidth = 1.5;
const double _insetFraction = 0.04;

/// 위에서 본 V6 하이브리드 파워 유닛 설계도(docs/15 §11.3 Engine Wear): 부품마다 마모 단계 색으로 옅은 채움 + 실선,
/// 실린더 보어·컴프레서 날개·권선·배터리 셀·기어는 가는 선. [frameColor]가 있으면 네 귀퉁이에 HUD 꺾쇠를 그린다.
/// 색은 위젯이 정해 넘긴다(그림은 계산만). 모양은 `engine_geometry.dart`의 단위 좌표.
class EnginePainter extends CustomPainter {
  EnginePainter({required this.partColors, required this.baseColor, this.frameColor})
      : assert(partColors.length == EnginePart.values.length, '부품 색은 EnginePart 순서대로 7개다.');

  /// [EnginePart] 순서.
  final List<Color> partColors;

  /// 부품 밑에 까는 불투명 색(카드 표면).
  final Color baseColor;

  /// 귀퉁이 꺾쇠 색. null이면 틀 없이 그림만.
  final Color? frameColor;

  static final List<DiagramShape<EnginePart>> _shapes = engineShapes();

  @override
  void paint(Canvas canvas, Size size) {
    final frame = frameColor;
    if (frame != null) {
      _paintBrackets(canvas, size, frame);
    }
    final inset = size.shortestSide * _insetFraction;
    canvas
      ..save()
      ..translate(inset, inset);
    final inner = Size(size.width - 2 * inset, size.height - 2 * inset);
    for (final shape in _shapes) {
      final path = scaleToSize(shape.path, inner);
      final color = partColors[shape.part.index];
      if (shape.kind == DiagramShapeKind.line) {
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = _detailStrokeWidth
            ..strokeCap = StrokeCap.square,
        );
        continue;
      }
      canvas
        ..drawPath(path, Paint()..color = baseColor)
        ..drawPath(path, Paint()..color = color.withValues(alpha: _bodyFillAlpha))
        ..drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = _bodyStrokeWidth
            ..strokeJoin = StrokeJoin.miter,
        );
    }
    canvas.restore();
  }

  static void _paintBrackets(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _bracketWidth;
    final w = size.width;
    final h = size.height;
    const l = _bracketLength;
    canvas.drawPath(
      Path()
        ..moveTo(0, l)
        ..lineTo(0, 0)
        ..lineTo(l, 0)
        ..moveTo(w - l, 0)
        ..lineTo(w, 0)
        ..lineTo(w, l)
        ..moveTo(w, h - l)
        ..lineTo(w, h)
        ..lineTo(w - l, h)
        ..moveTo(l, h)
        ..lineTo(0, h)
        ..lineTo(0, h - l),
      paint,
    );
  }

  @override
  bool shouldRepaint(EnginePainter oldDelegate) =>
      !listEquals(oldDelegate.partColors, partColors) ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.frameColor != frameColor;
}
