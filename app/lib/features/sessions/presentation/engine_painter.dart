import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../lap_detail/presentation/diagram_style.dart';
import 'engine_geometry.dart';

export 'engine_geometry.dart' show EnginePart;

/// 엔진 그림 기본 크기(논리 px).
const double kEngineDiagramExtent = 170;
const Size kEngineDiagramSize = Size.square(kEngineDiagramExtent);

/// 위에서 본 파워 유닛 그림(docs/15 §11.3 Engine Wear, F1Laps 참고): 부품마다 마모 단계 색의 반투명 채움 + 실선.
/// 색은 위젯이 정해 넘긴다(그림은 계산만). 모양은 `engine_geometry.dart`의 단위 좌표.
class EnginePainter extends CustomPainter {
  EnginePainter({required this.partColors, required this.baseColor})
    : assert(partColors.length == EnginePart.values.length, '부품 색은 EnginePart 순서대로 7개다.');

  /// [EnginePart] 순서.
  final List<Color> partColors;

  /// 부품 밑에 까는 불투명 색(카드 표면).
  final Color baseColor;

  static final List<DiagramShape<EnginePart>> _shapes = engineShapes();

  @override
  void paint(Canvas canvas, Size size) =>
      paintDiagram(canvas, size, _shapes, colorOf: (part) => partColors[part.index], baseColor: baseColor);

  @override
  bool shouldRepaint(EnginePainter oldDelegate) =>
      !listEquals(oldDelegate.partColors, partColors) || oldDelegate.baseColor != baseColor;
}
