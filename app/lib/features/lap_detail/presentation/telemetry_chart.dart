import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../domain/telemetry_math.dart';

/// 그래프 한 장의 높이.
const double kTelemetryChartHeight = 110;

const double _lineWidth = 1.6;
const double _gridLineWidth = 1;
const double _cursorLineWidth = 1;
const double _cursorDotRadius = 3.5;
const double _cursorAlpha = 0.6;
const int _gridDivisions = 2;
const double _headerGap = 6;
const double _valueGap = 12;
const double _dotSize = 8;
const double _dotGap = 4;

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

/// 그래프 그림(docs/15 §2.3): 가로 = 랩 거리, 가는 격자 3줄, (Delta면) 0 기준선, 계열 선, 십자선(세로선 + 계열마다 점).
/// [cursor]가 바뀌면 다시 그린다(모든 그래프가 같은 [cursor]를 보아 십자선이 함께 움직인다).
class TelemetryChartPainter extends CustomPainter {
  TelemetryChartPainter({
    required this.series,
    required this.maxDistanceM,
    required this.range,
    required this.cursor,
    required this.gridColor,
    required this.cursorColor,
    this.baseline,
  }) : super(repaint: cursor);

  final List<ChartSeries> series;
  final double maxDistanceM;
  final ValueRange range;
  final ValueListenable<double?> cursor;
  final Color gridColor;
  final Color cursorColor;

  /// 기준선 값(Delta의 0). null이면 그리지 않는다.
  final double? baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = ChartGeometry(width: size.width, height: size.height, maxDistanceM: maxDistanceM, range: range);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = _gridLineWidth;
    for (var i = 0; i <= _gridDivisions; i++) {
      final y = size.height * i / _gridDivisions;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final base = baseline;
    if (base != null) {
      final y = geometry.yFor(base);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()
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
    _paintCursor(canvas, size, geometry);
  }

  void _paintCursor(Canvas canvas, Size size, ChartGeometry geometry) {
    final distance = cursor.value;
    if (distance == null) {
      return;
    }
    final x = geometry.xFor(distance);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
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
      oldDelegate.gridColor != gridColor ||
      oldDelegate.cursorColor != cursorColor ||
      oldDelegate.baseline != baseline;
}

/// 텔레메트리 그래프 한 장: 제목 + 십자선 위치의 값(계열마다 색 점 + 값) + 그림.
/// 마우스를 올리거나(웹·데스크톱) 누르고 끌면(터치) [cursor]에 그 거리를 넣는다.
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
          height: height,
          child: LayoutBuilder(
            builder: (context, box) {
              void point(Offset local) => cursor.value = ChartGeometry(
                    width: box.maxWidth,
                    height: height,
                    maxDistanceM: maxDistanceM,
                    range: range,
                  ).distanceAtX(local.dx);
              return MouseRegion(
                onHover: (event) => point(event.localPosition),
                onExit: (_) => cursor.value = null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => point(details.localPosition),
                  onHorizontalDragStart: (details) => point(details.localPosition),
                  onHorizontalDragUpdate: (details) => point(details.localPosition),
                  child: CustomPaint(
                    size: Size(box.maxWidth, height),
                    painter: TelemetryChartPainter(
                      series: series,
                      maxDistanceM: maxDistanceM,
                      range: range,
                      cursor: cursor,
                      gridColor: palette.border,
                      cursorColor: palette.textMuted,
                      baseline: baseline,
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
