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
const double _hoverLineWidth = 1;
const double _hoverLineAlpha = 0.6;
const double _hoverDotRadius = 5;
const double _hoverRingWidth = 2;
const double _tooltipOffset = 12;
const double _tooltipPadding = 8;
const double _tooltipRowGap = 4;
const double _tooltipRadius = 6;
const double _tooltipElevation = 4;

/// 그래프에 그릴 선 하나(색이 정해진 [StintLine]).
@immutable
class StintChartSeries {
  const StintChartSeries({
    required this.label,
    required this.color,
    required this.points,
    this.startLap,
    this.compound,
  });

  final String label;
  final Color color;
  final List<StintPoint> points;

  /// 스틴트 첫 랩(세션 랩 번호). 있으면 툴팁에 `Lap 12`처럼 세션 랩 번호를 쓴다.
  final int? startLap;

  /// 컴파운드 이름(툴팁 끝에 붙인다). 없으면 생략.
  final String? compound;

  /// 스틴트 안 랩 [x]의 값. 그 랩 점이 없으면 null.
  double? valueAt(int x) => points.where((p) => p.x == x).firstOrNull?.y;

  // 값 동등성: build마다 새로 만들어도 같은 데이터면 다시 그리지 않는다(shouldRepaint).
  @override
  bool operator ==(Object other) =>
      other is StintChartSeries &&
      other.label == label &&
      other.color == color &&
      other.startLap == startLap &&
      other.compound == compound &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(label, color, startLap, compound, Object.hashAll(points));
}

/// 그림 영역(왼쪽 눈금 글자·아래 랩 번호를 뺀 칸).
Rect stintPlotRect(Size size) =>
    Rect.fromLTRB(_leftGutter, _topPadding, size.width - _rightPadding, size.height - _bottomGutter);

/// 마우스 가로 위치 [dx](그래프 왼쪽 끝 기준) → 가장 가까운 스틴트 안 랩(1~[maxX]). 그림 영역 폭이 0 이하면 null(순수 함수).
int? stintHoverX({required double dx, required double width, required int maxX}) {
  final plotWidth = width - _leftGutter - _rightPadding;
  if (plotWidth <= 0) {
    return null;
  }
  if (maxX <= 1) {
    return 1;
  }
  final position = ((dx - _leftGutter) / plotWidth * (maxX - 1)).clamp(0, maxX - 1);
  return position.round() + 1;
}

/// 툴팁 한 줄 글자: `Lap 12 · 1:30.088 · Medium`. 첫 랩을 모르면 `Lap 3 in stint`(순수 함수).
String stintTooltipText(StintChartSeries series, int x, double value, String Function(double value) formatY) {
  final start = series.startLap;
  final lap = start == null ? 'Lap $x in stint' : 'Lap ${start + x - 1}';
  final compound = series.compound;
  return compound == null ? '$lap · ${formatY(value)}' : '$lap · ${formatY(value)} · $compound';
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
    this.hoverX,
  });

  final List<StintChartSeries> series;
  final int maxX;
  final ValueRange range;
  final String Function(double value) formatY;
  final Color gridColor;
  final Color labelColor;

  /// 마우스가 가리키는 스틴트 안 랩. 있으면 세로 안내선과 그 랩 점의 고리를 그린다.
  final int? hoverX;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = stintPlotRect(size);
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
    _paintHover(canvas, plot, geometry, at);
  }

  void _paintHover(Canvas canvas, Rect plot, ChartGeometry geometry, Offset Function(StintPoint p) at) {
    final x = hoverX;
    if (x == null) {
      return;
    }
    final dx = plot.left + geometry.xFor((x - 1).toDouble());
    canvas.drawLine(Offset(dx, plot.top), Offset(dx, plot.bottom), Paint()
      ..color = labelColor.withValues(alpha: _hoverLineAlpha)
      ..strokeWidth = _hoverLineWidth);
    for (final line in series) {
      final value = line.valueAt(x);
      if (value != null) {
        canvas.drawCircle(at((x: x, y: value)), _hoverDotRadius, Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _hoverRingWidth);
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
      oldDelegate.labelColor != labelColor ||
      oldDelegate.hoverX != hoverX;
}

/// 스틴트 선 그래프 한 장: 범례(색 점 + `Stint 1 · Medium`) + 세로축 제목 + 그림 + 가로축 제목.
/// 마우스를 올리거나(웹·데스크톱) 누르면 가장 가까운 랩에 세로 안내선과 툴팁(`Lap 12 · 1:30.088 · Medium`, 스틴트마다 한 줄)을 보인다.
class StintLineChart extends StatefulWidget {
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
  State<StintLineChart> createState() => _StintLineChartState();
}

class _StintLineChartState extends State<StintLineChart> {
  /// 마우스가 가리키는 스틴트 안 랩. null이면 툴팁 없음.
  int? _hoverX;

  void _point(Offset local, double width) {
    final x = stintHoverX(dx: local.dx, width: width, maxX: widget.maxX);
    if (x != _hoverX) {
      setState(() => _hoverX = x);
    }
  }

  void _clear() {
    if (_hoverX != null) {
      setState(() => _hoverX = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final series = widget.series;
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
        Text(widget.yTitle, style: muted),
        const SizedBox(height: _axisTitleGap),
        SizedBox(
          height: kStintChartHeight,
          child: LayoutBuilder(
            builder: (context, box) => MouseRegion(
              onHover: (event) => _point(event.localPosition, box.maxWidth),
              onExit: (_) => _clear(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _point(details.localPosition, box.maxWidth),
                onHorizontalDragUpdate: (details) => _point(details.localPosition, box.maxWidth),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Semantics(
                      label: widget.semanticLabel,
                      child: CustomPaint(
                        size: Size(box.maxWidth, kStintChartHeight),
                        painter: StintChartPainter(
                          series: series,
                          maxX: widget.maxX,
                          range: widget.range,
                          formatY: widget.formatY,
                          gridColor: palette.border,
                          labelColor: palette.textMuted,
                          hoverX: _hoverX,
                        ),
                      ),
                    ),
                    ?_tooltip(context, Size(box.maxWidth, kStintChartHeight)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: _axisTitleGap),
        Center(child: Text(widget.xTitle, style: muted)),
      ],
    );
  }

  /// 안내선 옆 툴팁. 안내선이 그림 왼쪽 절반이면 오른쪽에, 아니면 왼쪽에 놓는다. 그 랩 점이 하나도 없으면 null.
  Widget? _tooltip(BuildContext context, Size size) {
    final x = _hoverX;
    if (x == null) {
      return null;
    }
    final rows = [
      for (final line in widget.series)
        if (line.valueAt(x) case final value?) (color: line.color, text: stintTooltipText(line, x, value, widget.formatY)),
    ];
    if (rows.isEmpty) {
      return null;
    }
    final plot = stintPlotRect(size);
    final span = widget.maxX <= 1 ? 0.0 : (x - 1) / (widget.maxX - 1);
    final dx = plot.left + plot.width * span;
    final onLeftHalf = dx < plot.center.dx;
    final palette = context.palette;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return Positioned(
      key: const ValueKey('stint-chart-tooltip'),
      top: plot.top,
      left: onLeftHalf ? dx + _tooltipOffset : null,
      right: onLeftHalf ? null : size.width - dx + _tooltipOffset,
      child: IgnorePointer(
        child: Material(
          color: palette.surface,
          elevation: _tooltipElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_tooltipRadius),
            side: BorderSide(color: palette.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(_tooltipPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: _tooltipRowGap),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChartDot(color: rows[i].color),
                      const SizedBox(width: _legendDotGap),
                      Text(rows[i].text, style: style),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
