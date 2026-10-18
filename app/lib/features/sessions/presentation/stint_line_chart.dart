import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../lap_detail/domain/telemetry_math.dart';
import '../../lap_detail/presentation/telemetry_chart.dart';
import '../domain/session_detail_display.dart' show StintPoint;

/// 스틴트 그래프 높이(그림 영역 + 축 글자).
const double kStintChartHeight = 220;

const double _leftGutter = 64;
const double _bottomGutter = 22;
const double _topPadding = 8;
const double _rightPadding = 8;
const double _lineWidth = 2;
const double _dotRadius = 3;
const double _gridLineWidth = 1;
const int _gridDivisions = 4;
const double _labelFontSize = 11;
const double _labelGap = 6;
const int _maxXTicks = 10;
const double _legendSpacing = 16;
const double _legendDotGap = 6;
const double _axisTitleGap = 4;

/// 그래프에 그릴 선 하나(색이 정해진 [StintLine]).
@immutable
class StintChartSeries {
  const StintChartSeries({required this.label, required this.color, required this.points});

  final String label;
  final Color color;
  final List<StintPoint> points;
}

/// 가로 눈금 랩 번호들(1부터 [maxX]까지, 많으면 건너뛴다). 순수 함수.
List<int> stintXTicks(int maxX) {
  final step = math.max(1, (maxX / _maxXTicks).ceil());
  return [for (var x = 1; x <= maxX; x += step) x];
}

/// 스틴트 선 그래프 그림(docs/15 §11.3): 왼쪽 세로 눈금 글자 + 가로 격자, 아래 랩 번호, 스틴트마다 선 + 점.
/// 좌표는 텔레메트리 그래프의 [ChartGeometry]를 그대로 쓴다(가로 = 랩 − 1).
class StintChartPainter extends CustomPainter {
  StintChartPainter({
    required this.series,
    required this.maxX,
    required this.range,
    required this.formatY,
    required this.gridColor,
    required this.labelColor,
  });

  final List<StintChartSeries> series;
  final int maxX;
  final ValueRange range;
  final String Function(double value) formatY;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_leftGutter, _topPadding, size.width - _rightPadding, size.height - _bottomGutter);
    if (plot.width <= 0 || plot.height <= 0) {
      return;
    }
    final geometry = ChartGeometry(
      width: plot.width,
      height: plot.height,
      maxDistanceM: (maxX - 1).toDouble(),
      range: range,
    );
    Offset at(StintPoint p) => Offset(plot.left + geometry.xFor((p.x - 1).toDouble()), plot.top + geometry.yFor(p.y));

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = _gridLineWidth;
    for (var i = 0; i <= _gridDivisions; i++) {
      final y = plot.top + plot.height * i / _gridDivisions;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final value = range.max - range.span * i / _gridDivisions;
      _label(canvas, formatY(value), Offset(plot.left - _labelGap, y), alignRight: true);
    }
    for (final x in stintXTicks(maxX)) {
      final dx = plot.left + geometry.xFor((x - 1).toDouble());
      _label(canvas, '$x', Offset(dx, plot.bottom + _labelGap), centered: true);
    }

    for (final line in series) {
      final points = [for (final p in line.points) at(p)];
      final stroke = Paint()
        ..color = line.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _lineWidth
        ..strokeJoin = StrokeJoin.round;
      if (points.length > 1) {
        canvas.drawPath(Path()..addPolygon(points, false), stroke);
      }
      final dot = Paint()..color = line.color;
      for (final point in points) {
        canvas.drawCircle(point, _dotRadius, dot);
      }
    }
  }

  /// [anchor]에 글자를 놓는다. [alignRight]면 오른쪽 끝·세로 가운데, [centered]면 가로 가운데·위 끝.
  void _label(Canvas canvas, String text, Offset anchor, {bool alignRight = false, bool centered = false}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: labelColor, fontSize: _labelFontSize)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final dx = alignRight ? anchor.dx - painter.width : (centered ? anchor.dx - painter.width / 2 : anchor.dx);
    final dy = alignRight ? anchor.dy - painter.height / 2 : anchor.dy;
    painter
      ..paint(canvas, Offset(dx, dy))
      ..dispose();
  }

  @override
  bool shouldRepaint(StintChartPainter oldDelegate) =>
      !listEquals(oldDelegate.series, series) ||
      oldDelegate.maxX != maxX ||
      oldDelegate.range.min != range.min ||
      oldDelegate.range.max != range.max ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor;
}

/// 스틴트 선 그래프 한 장: 범례(색 점 + `Stint 1 · Medium`) + 세로축 제목 + 그림 + 가로축 제목.
class StintLineChart extends StatelessWidget {
  const StintLineChart({
    super.key,
    required this.series,
    required this.maxX,
    required this.range,
    required this.formatY,
    required this.yTitle,
    required this.xTitle,
    required this.semanticLabel,
  });

  final List<StintChartSeries> series;

  /// 가로축 끝 랩(`stintChartMaxX`).
  final int maxX;
  final ValueRange range;
  final String Function(double value) formatY;
  final String yTitle;
  final String xTitle;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final small = Theme.of(context).textTheme.bodySmall;
    final muted = small?.copyWith(color: palette.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: _legendSpacing,
          runSpacing: _axisTitleGap,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChartDot(color: s.color),
                  const SizedBox(width: _legendDotGap),
                  Flexible(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: small)),
                ],
              ),
          ],
        ),
        const SizedBox(height: _legendSpacing),
        Text(yTitle, style: muted),
        const SizedBox(height: _axisTitleGap),
        Semantics(
          label: semanticLabel,
          child: CustomPaint(
            size: const Size(double.infinity, kStintChartHeight),
            painter: StintChartPainter(
              series: series,
              maxX: maxX,
              range: range,
              formatY: formatY,
              gridColor: palette.border,
              labelColor: palette.textMuted,
            ),
          ),
        ),
        const SizedBox(height: _axisTitleGap),
        Center(child: Text(xTitle, style: muted)),
      ],
    );
  }
}
