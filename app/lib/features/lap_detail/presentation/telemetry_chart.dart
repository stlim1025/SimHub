import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../domain/telemetry_channels.dart';
import '../domain/telemetry_math.dart';

/// 그래프 한 장의 그림 영역 높이(축 글자 칸은 따로 더한다).
const double kTelemetryChartHeight = 110;

const double _lineWidth = 1.6;
const double _gridLineWidth = 1;
const double _cursorLineWidth = 1;
const double _cursorDotRadius = 3.5;
const double _cursorAlpha = 0.6;
const double _leftGutter = 44;
const double _rightPadding = 8;
const double _topPadding = 6;
const double _bottomGutter = 18;
const double _labelFontSize = 11;
const double _yLabelGap = 6;
const double _xLabelGap = 3;

/// 눈금 글자 사이 최소 간격(px): 세로축은 글자 높이보다 조금 크게, 가로축은 `12,500` 폭의 두 배쯤.
const double _minYTickSpacing = 16;
const double _minXTickSpacing = 64;
const double _headerGap = 6;
const double _valueGap = 12;
const double _dotSize = 8;
const double _dotGap = 4;
const String _chartSemanticSuffix = '그래프';

/// 그래프의 선 하나(이 랩 또는 비교 랩). 표본 i의 거리 = i × [resolutionM]. 값이 없는(null) 칸에서는 선을 끊는다.
@immutable
class ChartSeries {
  const ChartSeries({required this.values, required this.resolutionM, required this.color});

  final List<double?> values;
  final int resolutionM;
  final Color color;

  /// [distanceM]에 가장 가까운 표본 값. 범위 밖이거나 값이 없으면 null.
  double? valueAt(double distanceM) {
    final index = seriesIndexAt(length: values.length, resolutionM: resolutionM, distanceM: distanceM);
    return index == null ? null : values[index];
  }
}

/// 계열을 화면 좌표의 선 조각들로 나눈다(값이 null인 칸에서 끊김, 점 하나뿐인 조각은 버린다). 순수 함수.
List<List<Offset>> seriesSegments(ChartSeries series, ChartGeometry geometry) {
  final segments = <List<Offset>>[];
  var current = <Offset>[];
  for (var i = 0; i < series.values.length; i++) {
    final value = series.values[i];
    if (value == null) {
      if (current.length > 1) {
        segments.add(current);
      }
      current = <Offset>[];
      continue;
    }
    current.add(Offset(geometry.xFor((i * series.resolutionM).toDouble()), geometry.yFor(value)));
  }
  if (current.length > 1) {
    segments.add(current);
  }
  return segments;
}

/// 그래프 전체 높이 = 위 여백 + 그림 영역 [plotHeight] + 아래 거리 글자 칸.
double telemetryChartTotalHeight(double plotHeight) => _topPadding + plotHeight + _bottomGutter;

/// 그림 영역(왼쪽 값 눈금 글자·아래 거리 글자 칸을 뺀 칸). 모든 그래프가 같은 왼쪽 칸을 써서 같은 거리가 같은 x에 온다.
Rect telemetryPlotRect(Size size) =>
    Rect.fromLTRB(_leftGutter, _topPadding, size.width - _rightPadding, size.height - _bottomGutter);

/// 세로축 눈금 값: 그림 영역 높이 [plotHeight]에 글자가 겹치지 않을 만큼(순수 함수).
List<double> telemetryYTicks(ValueRange range, double plotHeight) =>
    axisTicks(range, maxTicks: (plotHeight / _minYTickSpacing).floor() + 1);

/// 가로축 거리 눈금(m): 0부터 [maxDistanceM]까지, 그림 영역 폭 [plotWidth]에 글자가 겹치지 않을 만큼(순수 함수).
List<double> telemetryXTicks(double maxDistanceM, double plotWidth) =>
    axisTicks(ValueRange(0, maxDistanceM), maxTicks: (plotWidth / _minXTickSpacing).floor() + 1);

/// 그래프 축(docs/15 §2.3): 세로 값 눈금 글자 + 가는 가로 격자, 아래 거리(m) 눈금 글자.
/// 십자선과 따로 그려 마우스가 움직여도 다시 그리지 않는다.
class TelemetryAxesPainter extends CustomPainter {
  TelemetryAxesPainter({
    required this.range,
    required this.maxDistanceM,
    required this.gridColor,
    required this.labelColor,
    this.axisLabel = formatAxisValue,
  });

  final ValueRange range;
  final double maxDistanceM;
  final Color gridColor;
  final Color labelColor;

  /// 세로축 눈금 글자 함수(기어는 `R`·`N`).
  final AxisLabelFormat axisLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = telemetryPlotRect(size);
    if (plot.width <= 0 || plot.height <= 0) {
      return;
    }
    final geometry = ChartGeometry(width: plot.width, height: plot.height, maxDistanceM: maxDistanceM, range: range);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = _gridLineWidth;
    final yTicks = telemetryYTicks(range, plot.height);
    final yStep = yTicks.length > 1 ? yTicks[1] - yTicks[0] : range.span;
    for (final value in yTicks) {
      final y = plot.top + geometry.yFor(value);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(canvas, size, axisLabel(value, yStep), Offset(plot.left - _yLabelGap, y), alignRight: true);
    }
    final xTicks = telemetryXTicks(maxDistanceM, plot.width);
    final xStep = xTicks.length > 1 ? xTicks[1] - xTicks[0] : maxDistanceM;
    for (final distance in xTicks) {
      final x = plot.left + geometry.xFor(distance);
      _label(canvas, size, formatAxisValue(distance, xStep), Offset(x, plot.bottom + _xLabelGap));
    }
  }

  /// [anchor]에 글자를 놓는다. [alignRight]면 오른쪽 끝·세로 가운데(세로축), 아니면 가로 가운데·위 끝(가로축).
  /// 그래프 밖으로 나가지 않게 자른다(맨 끝 거리 글자 등).
  void _label(Canvas canvas, Size size, String text, Offset anchor, {bool alignRight = false}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: labelColor, fontSize: _labelFontSize)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final dx = alignRight ? anchor.dx - painter.width : anchor.dx - painter.width / 2;
    final dy = alignRight ? anchor.dy - painter.height / 2 : anchor.dy;
    final maxDx = math.max(0.0, size.width - painter.width);
    final maxDy = math.max(0.0, size.height - painter.height);
    painter
      ..paint(canvas, Offset(dx.clamp(0.0, maxDx), dy.clamp(0.0, maxDy)))
      ..dispose();
  }

  @override
  bool shouldRepaint(TelemetryAxesPainter oldDelegate) =>
      oldDelegate.range.min != range.min ||
      oldDelegate.range.max != range.max ||
      oldDelegate.maxDistanceM != maxDistanceM ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.axisLabel != axisLabel;
}

/// 그래프 그림(docs/15 §2.3): 그림 영역([telemetryPlotRect]) 안에 (Delta면) 0 기준선, 계열 선, 십자선(세로선 + 계열마다 점).
/// [cursor]가 바뀌면 다시 그린다(모든 그래프가 같은 [cursor]를 보아 십자선이 함께 움직인다). 축은 [TelemetryAxesPainter].
class TelemetryChartPainter extends CustomPainter {
  TelemetryChartPainter({
    required this.series,
    required this.maxDistanceM,
    required this.range,
    required this.cursor,
    required this.cursorColor,
    this.baseline,
  }) : super(repaint: cursor);

  final List<ChartSeries> series;
  final double maxDistanceM;
  final ValueRange range;
  final ValueListenable<double?> cursor;
  final Color cursorColor;

  /// 기준선 값(Delta의 0). null이면 그리지 않는다.
  final double? baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = telemetryPlotRect(size);
    if (plot.width <= 0 || plot.height <= 0) {
      return;
    }
    // 아래부터는 그림 영역 왼쪽 위가 원점(ChartGeometry 좌표 그대로).
    canvas
      ..save()
      ..translate(plot.left, plot.top);
    final geometry = ChartGeometry(width: plot.width, height: plot.height, maxDistanceM: maxDistanceM, range: range);
    final base = baseline;
    if (base != null) {
      final y = geometry.yFor(base);
      canvas.drawLine(Offset(0, y), Offset(plot.width, y), Paint()
        ..color = cursorColor
        ..strokeWidth = _gridLineWidth);
    }

    for (final line in series) {
      final paint = Paint()
        ..color = line.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _lineWidth
        ..strokeJoin = StrokeJoin.round;
      for (final segment in seriesSegments(line, geometry)) {
        canvas.drawPath(Path()..addPolygon(segment, false), paint);
      }
    }
    _paintCursor(canvas, geometry);
    canvas.restore();
  }

  void _paintCursor(Canvas canvas, ChartGeometry geometry) {
    final distance = cursor.value;
    if (distance == null) {
      return;
    }
    final x = geometry.xFor(distance);
    canvas.drawLine(Offset(x, 0), Offset(x, geometry.height), Paint()
      ..color = cursorColor.withValues(alpha: _cursorAlpha)
      ..strokeWidth = _cursorLineWidth);
    for (final line in series) {
      final value = line.valueAt(distance);
      if (value != null) {
        canvas.drawCircle(Offset(x, geometry.yFor(value)), _cursorDotRadius, Paint()..color = line.color);
      }
    }
  }

  @override
  bool shouldRepaint(TelemetryChartPainter oldDelegate) =>
      !listEquals(oldDelegate.series, series) ||
      oldDelegate.maxDistanceM != maxDistanceM ||
      oldDelegate.range.min != range.min ||
      oldDelegate.range.max != range.max ||
      oldDelegate.cursor != cursor ||
      oldDelegate.cursorColor != cursorColor ||
      oldDelegate.baseline != baseline;
}

/// 텔레메트리 그래프 한 장: 제목 + 십자선 위치의 값(계열마다 색 점 + 값) + 그림(왼쪽 값 눈금·아래 거리 눈금).
/// 마우스를 올리거나(웹·데스크톱) 누르고 끌면(터치) [cursor]에 그 거리를 넣는다(그림 영역 기준, 왼쪽 끝 = 0m).
class TelemetryChart extends StatelessWidget {
  const TelemetryChart({
    super.key,
    required this.title,
    required this.series,
    required this.range,
    required this.maxDistanceM,
    required this.cursor,
    required this.format,
    this.baseline,
    this.axisLabel = formatAxisValue,
    this.height = kTelemetryChartHeight,
  });

  final String title;
  final List<ChartSeries> series;
  final ValueRange range;
  final double maxDistanceM;
  final ValueNotifier<double?> cursor;

  /// 값 → 글자(단위 포함).
  final String Function(double value) format;
  final double? baseline;

  /// 세로축 눈금 글자 함수.
  final AxisLabelFormat axisLabel;

  /// 그림 영역 높이(축 글자 칸 제외).
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChartHeader(title: title, series: series, cursor: cursor, format: format),
        const SizedBox(height: _headerGap),
        SizedBox(
          height: telemetryChartTotalHeight(height),
          child: LayoutBuilder(
            builder: (context, box) {
              final size = Size(box.maxWidth, telemetryChartTotalHeight(height));
              final plot = telemetryPlotRect(size);
              // 그리는 쪽과 같은 그림 영역으로 바꿔야 마우스 거리와 십자선 위치가 맞는다.
              void point(Offset local) => cursor.value = ChartGeometry(
                    width: plot.width,
                    height: plot.height,
                    maxDistanceM: maxDistanceM,
                    range: range,
                  ).distanceAtX(local.dx - plot.left);
              return MouseRegion(
                onHover: (event) => point(event.localPosition),
                onExit: (_) => cursor.value = null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => point(details.localPosition),
                  onHorizontalDragStart: (details) => point(details.localPosition),
                  onHorizontalDragUpdate: (details) => point(details.localPosition),
                  // 십자선이 움직일 때 그래프마다 따로 다시 그리도록 경계를 둔다. 읽기 도구에는 그래프 이름을 알린다.
                  child: Semantics(
                    label: '$title $_chartSemanticSuffix',
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: TelemetryAxesPainter(
                          range: range,
                          maxDistanceM: maxDistanceM,
                          gridColor: palette.border,
                          labelColor: palette.textMuted,
                          axisLabel: axisLabel,
                        ),
                        // 십자선만 다시 그리도록 축과 층을 나눈다.
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: size,
                            painter: TelemetryChartPainter(
                              series: series,
                              maxDistanceM: maxDistanceM,
                              range: range,
                              cursor: cursor,
                              cursorColor: palette.textMuted,
                              baseline: baseline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({required this.title, required this.series, required this.cursor, required this.format});

  final String title;
  final List<ChartSeries> series;
  final ValueListenable<double?> cursor;
  final String Function(double value) format;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(title, style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
        ),
        // 좁은 화면에서 값이 길면 줄여 그린다(넘치지 않게).
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<double?>(
              valueListenable: cursor,
              builder: (context, distance, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (distance != null)
                    for (final line in series)
                      if (line.valueAt(distance) case final value?) ...[
                        const SizedBox(width: _valueGap),
                        ChartDot(color: line.color),
                        const SizedBox(width: _dotGap),
                        Text(format(value), style: _valueStyle(textTheme)),
                      ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static TextStyle? _valueStyle(TextTheme textTheme) => textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// 계열 색 점(범례·십자선 값 공용).
class ChartDot extends StatelessWidget {
  const ChartDot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
