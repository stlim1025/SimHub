import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';

/// 추세 그래프 높이(그림 영역 + 축 글자).
const double kTrendChartHeight = 200;

const double _leftGutter = 64;
const double _bottomGutter = 22;
const double _topPadding = 8;
const double _rightPadding = 8;
const double _lineWidth = 2;
const double _dotRadius = 3;
const double _gridLineWidth = 1;
const double _zeroLineWidth = 1.5;
const int _gridDivisions = 4;
const double _labelFontSize = 11;
const double _labelGap = 6;
const int _maxXTicks = 6;

/// 가로 눈금 글자 사이 최소 간격(좁은 그래프에서 날짜가 겹치지 않게 눈금 수를 줄인다).
const double _minTickSpacing = 64;
const int _minXTicks = 2;
const double _rangePadding = 0.08;
const double _barBandFraction = 0.6;
const double _maxBarWidth = 18;
const double _barRadius = 2;
const double _secondaryAlpha = 0.45;
const double _hoverLineAlpha = 0.6;
const double _hoverLineWidth = 1;
const double _hoverRingRadius = 5;
const double _hoverRingWidth = 2;
const double _tooltipOffset = 12;
const double _tooltipPadding = 8;
const double _tooltipRowGap = 2;
const double _tooltipRadius = 6;
const double _tooltipElevation = 4;
const double _tooltipMaxWidth = 220;

/// 추세 그래프의 점 하나. [value]가 null이면 그 자리는 비운다(선이 끊긴다). [secondary]는 흐린 점으로 함께 그리는 두 번째 값.
@immutable
class TrendPoint {
  const TrendPoint({required this.label, required this.value, this.secondary, this.detail, this.tick});

  /// 툴팁 첫 줄(`10.24 Monaco`).
  final String label;
  final double? value;
  final double? secondary;

  /// 툴팁 마지막 줄(없으면 생략).
  final String? detail;

  /// 가로 눈금 글자(없으면 [label]).
  final String? tick;

  @override
  bool operator ==(Object other) =>
      other is TrendPoint &&
      other.label == label &&
      other.value == value &&
      other.secondary == secondary &&
      other.detail == detail &&
      other.tick == tick;

  @override
  int get hashCode => Object.hash(label, value, secondary, detail, tick);
}

/// 선(값의 흐름) 또는 막대(0 기준 위·아래).
enum TrendChartKind { line, bars }

/// 세로 범위(그릴 최솟값·최댓값). 순수 함수: 값(과 막대면 0)을 다 담고 위아래로 조금 여유를 둔다. 값이 없으면 null.
({double min, double max})? trendRange(Iterable<double> values, {required bool includeZero, double? minY, double? maxY}) {
  final list = [...values, if (includeZero) 0.0];
  if (list.isEmpty) {
    return null;
  }
  var low = minY ?? list.reduce(math.min);
  var high = maxY ?? list.reduce(math.max);
  if (high - low == 0) {
    low -= 1;
    high += 1;
  }
  final pad = (high - low) * _rangePadding;
  return (min: minY ?? low - pad, max: maxY ?? high + pad);
}

/// 가로 눈금을 둘 점 번호들(많으면 고르게 건너뛰고, 마지막 점은 늘 넣는다). [maxTicks]는 눈금 최대 개수. 순수 함수.
List<int> trendXTicks(int count, {int maxTicks = _maxXTicks}) {
  if (count <= 0) {
    return const [];
  }
  final step = math.max(1, (count / math.max(1, maxTicks)).ceil());
  final ticks = [for (var i = 0; i < count; i += step) i];
  if (ticks.last != count - 1) {
    if (count - 1 - ticks.last < step / 2) {
      ticks.removeLast();
    }
    ticks.add(count - 1);
  }
  return ticks;
}

/// 마우스 가로 위치 [dx] → 가장 가까운 점 번호(0부터). 그림 영역 밖이거나 점이 없으면 null(순수 함수).
int? trendHoverIndex({required double dx, required double width, required int count}) {
  final plotWidth = width - _leftGutter - _rightPadding;
  if (plotWidth <= 0 || count == 0) {
    return null;
  }
  final band = plotWidth / count;
  return ((dx - _leftGutter) / band).floor().clamp(0, count - 1);
}

Rect _plotRect(Size size) => Rect.fromLTRB(_leftGutter, _topPadding, size.width - _rightPadding, size.height - _bottomGutter);

/// 추세 그림: 왼쪽 눈금 + 가로 격자, 아래 눈금 글자, 점마다 같은 폭의 칸 가운데에 선의 점 또는 막대.
class TrendChartPainter extends CustomPainter {
  TrendChartPainter({
    required this.points,
    required this.kind,
    required this.range,
    required this.formatTick,
    required this.invertY,
    required this.color,
    required this.positiveColor,
    required this.negativeColor,
    required this.gridColor,
    required this.labelColor,
    this.hoverIndex,
  });

  final List<TrendPoint> points;
  final TrendChartKind kind;
  final ({double min, double max}) range;

  /// 세로 눈금 글자(왼쪽 칸에 들어가게 짧게).
  final String Function(double value) formatTick;
  final bool invertY;
  final Color color;

  /// 막대: 0보다 크면 이 색, 작으면 [negativeColor].
  final Color positiveColor;
  final Color negativeColor;
  final Color gridColor;
  final Color labelColor;
  final int? hoverIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _plotRect(size);
    if (plot.width <= 0 || plot.height <= 0 || points.isEmpty) {
      return;
    }
    final span = range.max - range.min;
    double yOf(double v) => invertY
        ? plot.top + (v - range.min) / span * plot.height
        : plot.top + (range.max - v) / span * plot.height;
    final band = plot.width / points.length;
    double xOf(int i) => plot.left + band * (i + 0.5);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = _gridLineWidth;
    for (var i = 0; i <= _gridDivisions; i++) {
      final value = invertY ? range.min + span * i / _gridDivisions : range.max - span * i / _gridDivisions;
      final y = yOf(value);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(canvas, formatTick(value), Offset(plot.left - _labelGap, y), alignRight: true);
    }
    final maxTicks = math.min(_maxXTicks, math.max(_minXTicks, (plot.width / _minTickSpacing).floor()));
    for (final i in trendXTicks(points.length, maxTicks: maxTicks)) {
      _label(canvas, points[i].tick ?? points[i].label, Offset(xOf(i), plot.bottom + _labelGap), centered: true);
    }

    if (kind == TrendChartKind.bars) {
      _paintBars(canvas, plot, band, xOf, yOf);
    } else {
      _paintLine(canvas, xOf, yOf);
    }
    _paintSecondary(canvas, xOf, yOf);
    _paintHover(canvas, plot, xOf, yOf);
  }

  void _paintBars(Canvas canvas, Rect plot, double band, double Function(int) xOf, double Function(double) yOf) {
    final zero = yOf(0);
    canvas.drawLine(Offset(plot.left, zero), Offset(plot.right, zero), Paint()
      ..color = labelColor
      ..strokeWidth = _zeroLineWidth);
    final width = math.min(band * _barBandFraction, _maxBarWidth);
    for (var i = 0; i < points.length; i++) {
      final value = points[i].value;
      if (value == null || value == 0) {
        continue;
      }
      final rect = Rect.fromLTRB(xOf(i) - width / 2, math.min(zero, yOf(value)), xOf(i) + width / 2, math.max(zero, yOf(value)));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(_barRadius)),
        Paint()..color = value > 0 ? positiveColor : negativeColor,
      );
    }
  }

  void _paintLine(Canvas canvas, double Function(int) xOf, double Function(double) yOf) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lineWidth
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = color;
    Path? path;
    for (var i = 0; i < points.length; i++) {
      final value = points[i].value;
      if (value == null) {
        if (path != null) {
          canvas.drawPath(path, stroke);
        }
        path = null;
        continue;
      }
      final at = Offset(xOf(i), yOf(value));
      path = path == null ? (Path()..moveTo(at.dx, at.dy)) : (path..lineTo(at.dx, at.dy));
      canvas.drawCircle(at, _dotRadius, dot);
    }
    if (path != null) {
      canvas.drawPath(path, stroke);
    }
  }

  void _paintSecondary(Canvas canvas, double Function(int) xOf, double Function(double) yOf) {
    final dot = Paint()..color = labelColor.withValues(alpha: _secondaryAlpha);
    for (var i = 0; i < points.length; i++) {
      final value = points[i].secondary;
      if (value != null) {
        canvas.drawCircle(Offset(xOf(i), yOf(value)), _dotRadius, dot);
      }
    }
  }

  void _paintHover(Canvas canvas, Rect plot, double Function(int) xOf, double Function(double) yOf) {
    final i = hoverIndex;
    if (i == null || i >= points.length) {
      return;
    }
    canvas.drawLine(Offset(xOf(i), plot.top), Offset(xOf(i), plot.bottom), Paint()
      ..color = labelColor.withValues(alpha: _hoverLineAlpha)
      ..strokeWidth = _hoverLineWidth);
    final value = points[i].value;
    if (kind == TrendChartKind.line && value != null) {
      canvas.drawCircle(Offset(xOf(i), yOf(value)), _hoverRingRadius, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _hoverRingWidth);
    }
  }

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
  bool shouldRepaint(TrendChartPainter oldDelegate) =>
      !listEquals(oldDelegate.points, points) ||
      oldDelegate.kind != kind ||
      oldDelegate.range != range ||
      oldDelegate.formatTick != formatTick ||
      oldDelegate.invertY != invertY ||
      oldDelegate.color != color ||
      oldDelegate.positiveColor != positiveColor ||
      oldDelegate.negativeColor != negativeColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.hoverIndex != hoverIndex;
}

/// 추세 그래프 한 장. 마우스를 올리거나(웹·데스크톱) 누르면 가장 가까운 점에 안내선과 툴팁([TrendPoint.label] · 값 · [TrendPoint.detail]).
/// [invertY]면 작은 값이 위(순위 — P1이 맨 위). 막대는 0 기준으로, 기본은 음수(내가 빠름) 초록 · 양수 빨강([positiveIsGood]면 반대).
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.kind,
    required this.formatValue,
    required this.semanticLabel,
    this.formatTick,
    this.invertY = false,
    this.minY,
    this.maxY,
    this.color,
    this.positiveIsGood = false,
    this.neutralBars = false,
  });

  final List<TrendPoint> points;
  final TrendChartKind kind;
  /// 툴팁 값 글자.
  final String Function(double value) formatValue;

  /// 세로 눈금 글자(없으면 [formatValue]). 왼쪽 칸에 들어가게 짧은 형식을 준다.
  final String Function(double value)? formatTick;
  final String semanticLabel;
  final bool invertY;
  final double? minY;
  final double? maxY;

  /// 선 색(기본 강조색).
  final Color? color;

  /// 막대: 양수가 좋은 값(초록)이면 true.
  final bool positiveIsGood;

  /// 막대를 좋고 나쁨 없이 한 색([color])으로 칠한다(주행량처럼 크기만 보는 값).
  final bool neutralBars;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _hover;

  void _point(Offset local, double width) {
    final index = trendHoverIndex(dx: local.dx, width: width, count: widget.points.length);
    if (index != _hover) {
      setState(() => _hover = index);
    }
  }

  void _clear() {
    if (_hover != null) {
      setState(() => _hover = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final values = [
      for (final p in widget.points) ...[?p.value, ?p.secondary],
    ];
    final range = trendRange(
      values,
      includeZero: widget.kind == TrendChartKind.bars,
      minY: widget.minY,
      maxY: widget.maxY,
    );
    if (range == null) {
      return const SizedBox(height: kTrendChartHeight);
    }
    final lineColor = widget.color ?? AppColors.accent;
    final (positive, negative) = widget.neutralBars
        ? (lineColor, lineColor)
        : widget.positiveIsGood
            ? (palette.success, palette.danger)
            : (palette.danger, palette.success);
    return SizedBox(
      height: kTrendChartHeight,
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
                    size: Size(box.maxWidth, kTrendChartHeight),
                    painter: TrendChartPainter(
                      points: widget.points,
                      kind: widget.kind,
                      range: range,
                      formatTick: widget.formatTick ?? widget.formatValue,
                      invertY: widget.invertY,
                      color: lineColor,
                      positiveColor: positive,
                      negativeColor: negative,
                      gridColor: palette.border,
                      labelColor: palette.textMuted,
                      hoverIndex: _hover,
                    ),
                  ),
                ),
                ?_tooltip(context, Size(box.maxWidth, kTrendChartHeight)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 안내선 옆 툴팁. 안내선이 그림 왼쪽 절반이면 오른쪽에, 아니면 왼쪽에 놓는다.
  Widget? _tooltip(BuildContext context, Size size) {
    final index = _hover;
    if (index == null || index >= widget.points.length) {
      return null;
    }
    final point = widget.points[index];
    final plot = _plotRect(size);
    final dx = plot.left + plot.width / widget.points.length * (index + 0.5);
    final onLeftHalf = dx < plot.center.dx;
    final palette = context.palette;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final value = point.value;
    return Positioned(
      key: const ValueKey('trend-chart-tooltip'),
      top: plot.top,
      left: onLeftHalf ? dx + _tooltipOffset : null,
      right: onLeftHalf ? null : size.width - dx + _tooltipOffset,
      child: Material(
        elevation: _tooltipElevation,
        color: palette.surface,
        borderRadius: BorderRadius.circular(_tooltipRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _tooltipMaxWidth),
          child: Padding(
            padding: const EdgeInsets.all(_tooltipPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(point.label, style: style?.copyWith(color: palette.textMuted)),
                const SizedBox(height: _tooltipRowGap),
                Text(value == null ? '-' : widget.formatValue(value), style: style?.copyWith(fontWeight: FontWeight.bold)),
                if (point.detail case final detail?) ...[
                  const SizedBox(height: _tooltipRowGap),
                  Text(detail, style: style),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
