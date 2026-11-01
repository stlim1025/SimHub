import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'engine_geometry.dart';

export 'engine_geometry.dart' show EnginePart;

/// 엔진 그림 기본 크기(논리 px, 3/4 시점 모델 비율에 맞춤).
const Size kEngineDiagramSize = Size(260, 250);

/// 네온 선: 흐린 빛 번짐 위에 또렷한 선. 면은 카드 표면 색으로 채워 뒤쪽 선을 가린다.
const double _strokeWidth = 1.3;
const double _detailStrokeWidth = 1;
const double _glowWidth = 3.2;
const double _glowSigma = 2.6;
const double _glowAlpha = 0.55;

/// 면 안쪽을 부품 색으로 아주 옅게 물들인다(어두운 몸체에 색이 비치는 느낌).
const double _faceTintAlpha = 0.07;

/// 배경 격자 간격(px)과 그림을 틀 안으로 들이는 여백.
const double _gridSpacing = 18;
const double _padding = 10;

/// 앞-왼쪽 위에서 비스듬히 본 F1 V6 하이브리드 파워 유닛 네온 선화(docs/15 §11.3 Engine Wear): 부품마다 마모 단계 색의
/// 빛나는 테두리, 뒤쪽 선은 앞 면이 가린다. [gridColor]가 있으면 설계도 격자를 깐다.
/// 색은 위젯이 정해 넘긴다(그림은 계산만). 모양·배치는 `engine_geometry.dart`의 3D 모델.
class EnginePainter extends CustomPainter {
  EnginePainter({required this.partColors, required this.baseColor, this.gridColor})
      : assert(partColors.length == EnginePart.values.length, '부품 색은 EnginePart 순서대로 7개다.');

  /// [EnginePart] 순서.
  final List<Color> partColors;

  /// 면을 채우는 불투명 색(카드 표면).
  final Color baseColor;

  /// 배경 격자 색. null이면 격자 없이 그림만.
  final Color? gridColor;

  static final EngineProjection _projection = projectEngine();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = gridColor;
    if (grid != null) {
      _paintGrid(canvas, size, grid);
    }
    // 모델 비율을 지키며 가운데에 맞춘다.
    final available = Size(size.width - 2 * _padding, size.height - 2 * _padding);
    final aspect = _projection.aspect;
    final width = available.width / available.height > aspect ? available.height * aspect : available.width;
    final height = width / aspect;
    final origin = Offset((size.width - width) / 2, (size.height - height) / 2);
    Offset place(Offset unit) => origin + Offset(unit.dx * width, unit.dy * height);

    for (final face in _projection.faces) {
      final path = Path()..addPolygon([for (final p in face.points) place(p)], true);
      final color = partColors[face.part.index];
      if (face.style != FaceStyle.outline) {
        canvas
          ..drawPath(path, Paint()..color = baseColor)
          ..drawPath(path, Paint()..color = color.withValues(alpha: _faceTintAlpha));
      }
      if (face.style == FaceStyle.fillOnly) {
        continue;
      }
      canvas
        ..drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: _glowAlpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _glowWidth
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _glowSigma),
        )
        ..drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = face.style == FaceStyle.outline ? _detailStrokeWidth : _strokeWidth
            ..strokeJoin = StrokeJoin.round,
        );
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
