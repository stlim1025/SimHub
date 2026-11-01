import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'engine_geometry.dart';

export 'engine_geometry.dart' show EnginePart;

/// 엔진 그림 기본 크기(논리 px, 3/4 시점 그림 비율에 맞춤).
const Size kEngineDiagramSize = Size(280, 230);

/// 네온 선: 흐린 빛 번짐 위에 또렷한 선. 몸통은 카드 표면 색으로 채워 뒤 부품 선을 가린다.
const double _bodyStrokeWidth = 1.4;
const double _lineStrokeWidth = 1;
const double _glowWidth = 3.4;
const double _lineGlowWidth = 2.4;
const double _glowSigma = 2.8;
const double _glowAlpha = 0.5;

/// 몸통 안을 부품 색으로 아주 옅게 물들인다(어두운 몸체에 색이 비치는 느낌).
const double _bodyTintAlpha = 0.07;

/// 배경 격자 간격(px)과 그림을 틀 안으로 들이는 여백.
const double _gridSpacing = 18;
const double _padding = 12;

/// 앞-왼쪽 위에서 비스듬히 본 F1 V6 하이브리드 파워 유닛 네온 선화(docs/15 §11.3 Engine Wear): 부품마다 마모 단계 색으로
/// 빛나는 윤곽, 앞 부품이 뒤 부품 선을 가린다. [gridColor]가 있으면 설계도 격자를 깐다.
/// 색은 위젯이 정해 넘긴다(그림은 계산만). 모양·배치는 `engine_geometry.dart`.
class EnginePainter extends CustomPainter {
  EnginePainter({required this.partColors, required this.baseColor, this.gridColor})
      : assert(partColors.length == EnginePart.values.length, '부품 색은 EnginePart 순서대로 7개다.');

  /// [EnginePart] 순서.
  final List<Color> partColors;

  /// 몸통을 채우는 불투명 색(카드 표면).
  final Color baseColor;

  /// 배경 격자 색. null이면 격자 없이 그림만.
  final Color? gridColor;

  static final EngineDrawing _drawing = drawEngine();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = gridColor;
    if (grid != null) {
      _paintGrid(canvas, size, grid);
    }
    // 그림 비율을 지키며 가운데에 맞춘다.
    final availableW = size.width - 2 * _padding;
    final availableH = size.height - 2 * _padding;
    final aspect = _drawing.aspect;
    final width = availableW / availableH > aspect ? availableH * aspect : availableW;
    final height = width / aspect;
    final origin = Offset((size.width - width) / 2, (size.height - height) / 2);
    Offset place(Offset unit) => origin + Offset(unit.dx * width, unit.dy * height);

    Paint neon(Color color, double strokeWidth) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    Paint glow(Color color, double strokeWidth) => neon(color.withValues(alpha: _glowAlpha), strokeWidth)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _glowSigma);

    for (final stroke in _drawing.strokes) {
      final path = Path()..addPolygon([for (final p in stroke.points) place(p)], stroke.closed);
      final color = partColors[stroke.part.index];
      switch (stroke.kind) {
        case StrokeKind.body:
          canvas
            ..drawPath(path, Paint()..color = baseColor)
            ..drawPath(path, Paint()..color = color.withValues(alpha: _bodyTintAlpha))
            ..drawPath(path, glow(color, _glowWidth))
            ..drawPath(path, neon(color, _bodyStrokeWidth));
        case StrokeKind.line:
          canvas
            ..drawPath(path, glow(color, _lineGlowWidth))
            ..drawPath(path, neon(color, _lineStrokeWidth));
        case StrokeKind.tube:
          // 바깥(색) → 안(표면 색)으로 두 번 그어 테두리 두 줄만 빛나는 관을 만든다.
          final outer = stroke.tubeWidth * width;
          final inner = outer - 2 * _bodyStrokeWidth;
          canvas
            ..drawPath(path, glow(color, outer + _glowWidth))
            ..drawPath(path, neon(color, outer))
            ..drawPath(path, neon(baseColor, inner))
            ..drawPath(path, neon(color.withValues(alpha: _bodyTintAlpha), inner));
      }
    }
  }

  static void _paintGrid(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = _gridSpacing / 2; x < size.width; x += _gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = _gridSpacing / 2; y < size.height; y += _gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(EnginePainter oldDelegate) =>
      !listEquals(oldDelegate.partColors, partColors) ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.gridColor != gridColor;
}
