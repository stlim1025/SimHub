import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../../core/theme/app_palette.dart';
import '../domain/lap_detail_display.dart';
import 'car_tyres_card.dart';

/// 그림 부품 공통 스타일(docs/15 §2.3·§11.3, F1Laps 참고): 같은 색의 반투명 채움 + 실선 테두리.
const double kPartFillAlpha = 0.45;
const double kPartStrokeWidth = 1.6;
const double kPartLineWidth = 2;

/// 부품 하나를 그리는 방식.
enum DiagramShapeKind {
  /// 반투명 채움 + 테두리.
  part,

  /// 선만(서스펜션 암·헤일로).
  line,

  /// 구멍(조종석): 배경색으로 채운다.
  hole,
}

/// 단위 좌표(0~1)로 만든 부품 하나. [part]가 색을 정한다.
class DiagramShape<T> {
  const DiagramShape(this.part, this.path, {this.kind = DiagramShapeKind.part});

  final T part;
  final Path path;
  final DiagramShapeKind kind;
}

/// 마모·손상 % → 그림 색(25/50/75%). 값이 없으면 중립 회색(F1Laps처럼 칠하지 않은 부품).
Color diagramColorFor(double? percent, AppPalette palette) =>
    percent == null ? palette.textMuted : wearLevelColor(tyreWearLevelOf(percent), palette);

/// 단위 좌표 경로를 [size]로 늘린다.
Path scaleToSize(Path unit, Size size) => unit.transform(Matrix4.diagonal3Values(size.width, size.height, 1).storage);

/// 단위 좌표 경로를 세로 중심선(x = 0.5) 기준으로 뒤집는다(왼쪽 절반 → 오른쪽 절반).
Path mirrorX(Path unit) => unit.transform((Matrix4.diagonal3Values(-1, 1, 1)..setTranslationRaw(1, 0, 0)).storage);

/// 중심선에 닿는 왼쪽 절반과 그 거울상을 합친 좌우 대칭 경로.
Path symmetric(Path leftHalf) => Path.combine(PathOperation.union, leftHalf, mirrorX(leftHalf));

/// 둥근 사각형 경로(단위 좌표). 가로세로 비율이 다른 그림에서도 모서리가 둥글게 보이도록 [aspect](폭/높이)로 세로 반경을 맞춘다.
Path roundedRect(double left, double top, double right, double bottom, double radiusX, {double aspect = 1}) =>
    Path()..addRRect(RRect.fromLTRBR(left, top, right, bottom, Radius.elliptical(radiusX, radiusX * aspect)));

/// 3차 곡선을 따라가는 굵기 [halfWidth]×2의 관(배기관), 끝은 둥글다. 끝점의 법선만큼 조절점을 옮겨 근사한다.
Path tubePath(Offset p0, Offset c1, Offset c2, Offset p3, double halfWidth) {
  Offset normal(Offset from, Offset to) {
    final d = to - from;
    final length = math.max(d.distance, double.minPositive);
    return Offset(d.dy / length, -d.dx / length) * halfWidth;
  }

  final n0 = normal(p0, c1);
  final n3 = normal(c2, p3);
  final tip = p3 + Offset(-n3.dy, n3.dx);
  return Path()
    ..moveTo(p0.dx + n0.dx, p0.dy + n0.dy)
    ..cubicTo(c1.dx + n0.dx, c1.dy + n0.dy, c2.dx + n3.dx, c2.dy + n3.dy, p3.dx + n3.dx, p3.dy + n3.dy)
    ..quadraticBezierTo(tip.dx + n3.dx, tip.dy + n3.dy, tip.dx, tip.dy)
    ..quadraticBezierTo(tip.dx - n3.dx, tip.dy - n3.dy, p3.dx - n3.dx, p3.dy - n3.dy)
    ..cubicTo(c2.dx - n3.dx, c2.dy - n3.dy, c1.dx - n0.dx, c1.dy - n0.dy, p0.dx - n0.dx, p0.dy - n0.dy)
    ..close();
}

/// 단위 좌표 부품 목록을 [size]에 그린다. [colorOf]가 부품 색. [baseColor](카드 표면)를 먼저 깔아
/// 반투명 채움이어도 뒤 부품의 선이 비치지 않게 한다. [holeColor]는 구멍 색(구멍이 있는 그림만).
void paintDiagram<T>(
  Canvas canvas,
  Size size,
  List<DiagramShape<T>> shapes, {
  required Color Function(T part) colorOf,
  required Color baseColor,
  Color holeColor = const Color(0x00000000),
}) {
  for (final shape in shapes) {
    final path = scaleToSize(shape.path, size);
    final color = colorOf(shape.part);
    switch (shape.kind) {
      case DiagramShapeKind.part:
        canvas
          ..drawPath(path, Paint()..color = baseColor)
          ..drawPath(path, Paint()..color = color.withValues(alpha: kPartFillAlpha))
          ..drawPath(
            path,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = kPartStrokeWidth
              ..strokeJoin = StrokeJoin.round,
          );
      case DiagramShapeKind.line:
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = kPartLineWidth
            ..strokeCap = StrokeCap.round,
        );
      case DiagramShapeKind.hole:
        canvas
          ..drawPath(path, Paint()..color = holeColor)
          ..drawPath(
            path,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = kPartStrokeWidth,
          );
    }
  }
}
