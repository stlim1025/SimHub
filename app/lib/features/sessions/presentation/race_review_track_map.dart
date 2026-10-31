import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../lap_detail/domain/lap_corners.dart';
import '../../lap_detail/domain/lap_detail_models.dart';
import '../../lap_detail/domain/track_map.dart' as track;
import '../../lap_detail/presentation/track_map.dart' show kTrackSectorColors;
import '../../laps/domain/lap_models.dart';
import 'session_widgets.dart';

const String _title = '트랙 지도';
const String _semanticLabel = '섹터와 코너 번호가 적힌 트랙 지도';

/// 지도 높이 범위(트랙 가로세로 비율을 따르되 이 안으로), 상자 가장자리 여백(코너 번호가 잘리지 않게 넉넉히).
const double kRaceTrackMapMinHeight = 180;
const double kRaceTrackMapMaxHeight = 320;
const double _mapPadding = 24;
const double _outlineWidth = 8;
const double _sectorWidth = 4;

/// 코너 번호 자리: 바깥쪽 방향을 잴 앞뒤 거리(m), 트랙에서 띄우는 거리 후보(px, 겹치면 더 멀리), 겹침 판정 여유(px),
/// 코너가 거의 곧을 때(바깥쪽을 못 잴 때) 기준(px).
const double _outwardSpanM = 30;
const List<double> _labelOffsets = [14, 24, 34];
const double _labelClearance = 1;
const double _minOutward = 0.5;

/// 코너 번호 글자·배지.
const double _labelFontSize = 10;
const double _labelPadH = 4;
const double _labelPadV = 1.5;
const double _labelRadius = 6;
const double _labelBorder = 1;
const double _leaderWidth = 1;

/// 섹터 범례.
const double _legendGap = 12;
const double _legendSpacing = 14;
const double _legendDotGap = 6;
const double _legendDotSize = 8;

/// 폭 [width]에 트랙을 꽉 채울 지도 높이: 트랙의 세로/가로 비율대로, [kRaceTrackMapMinHeight]~[kRaceTrackMapMaxHeight] 안.
/// 가로로 긴 트랙 위아래에 빈 곳이 크게 남지 않게 한다. 위치가 없으면 최소 높이.
double raceTrackMapHeight(LapTrace trace, double width) {
  if (!trace.hasPositions || trace.length < 2 || !width.isFinite) {
    return kRaceTrackMapMinHeight;
  }
  double span(List<double> values) => values.reduce(math.max) - values.reduce(math.min);
  final spanX = span(trace.worldPosX);
  final spanZ = span(trace.worldPosZ);
  final inner = math.max(0.0, width - _mapPadding * 2);
  final height = spanX <= 0 ? kRaceTrackMapMaxHeight : inner * spanZ / spanX + _mapPadding * 2;
  return height.clamp(kRaceTrackMapMinHeight, kRaceTrackMapMaxHeight);
}

/// 코너 번호 하나: 글자, 트랙 위 지점, 배지 가운데.
typedef CornerLabelPlacement = ({String text, Offset anchor, Offset center});

/// 코너 번호 배지 자리(순수 계산). 코너 가운데 지점에서 코너 바깥쪽(앞뒤 [_outwardSpanM] 점을 이은 선에서 멀어지는 쪽)으로
/// [_labelOffsets]만큼 띄우고, 먼저 놓인 배지와 겹치면 더 멀리 놓는다. 배지는 상자 [size] 안으로 밀어 넣는다.
/// [points]는 표본마다 화면 점(칸 i = 랩 거리 i × [resolutionM]), [sizeOf]는 글자마다 배지 크기.
List<CornerLabelPlacement> placeCornerLabels({
  required List<Offset> points,
  required double resolutionM,
  required List<LapCorner> corners,
  required Size size,
  required Size Function(String text) sizeOf,
}) {
  if (points.length < 3 || corners.isEmpty || resolutionM <= 0) {
    return const [];
  }
  final n = points.length;
  final span = math.max(1, (_outwardSpanM / resolutionM).round());
  final placed = <({Rect rect, CornerLabelPlacement label})>[];
  for (final corner in corners) {
    final i = ((corner.startM + corner.endM) / 2 / resolutionM).round().clamp(0, n - 1);
    final anchor = points[i];
    final before = points[(i - span).clamp(0, n - 1)];
    final after = points[(i + span).clamp(0, n - 1)];
    var outward = anchor - (before + after) / 2;
    if (outward.distance < _minOutward) {
      final along = after - before;
      outward = Offset(-along.dy, along.dx);
    }
    final unit = outward.distance == 0 ? const Offset(0, -1) : outward / outward.distance;
    final labelSize = sizeOf(corner.label);
    var rect = Rect.zero;
    for (final offset in _labelOffsets) {
      rect = _clampInto(
        Rect.fromCenter(center: anchor + unit * offset, width: labelSize.width, height: labelSize.height),
        size,
      );
      if (!placed.any((p) => p.rect.inflate(_labelClearance).overlaps(rect))) {
        break;
      }
    }
    placed.add((rect: rect, label: (text: corner.label, anchor: anchor, center: rect.center)));
  }
  return [for (final p in placed) p.label];
}

Rect _clampInto(Rect rect, Size size) {
  final dx = rect.left < 0 ? -rect.left : (rect.right > size.width ? size.width - rect.right : 0.0);
  final dy = rect.top < 0 ? -rect.top : (rect.bottom > size.height ? size.height - rect.bottom : 0.0);
  return rect.shift(Offset(dx, dy));
}

/// 레이스 리뷰 옆 트랙 지도 그림: 어두운 테두리 + 섹터 색 선, 코너마다 번호 배지(트랙 바깥쪽, 멀리 놓이면 트랙까지 가는 선).
class RaceTrackMapPainter extends CustomPainter {
  RaceTrackMapPainter({
    required this.trace,
    required this.sectorIndexes,
    required this.corners,
    required this.labelColor,
    required this.labelBackground,
    required this.labelBorder,
  });

  final LapTrace trace;

  /// 표본마다 섹터 번호. null이면 한 색.
  final List<int>? sectorIndexes;
  final List<LapCorner> corners;
  final Color labelColor;
  final Color labelBackground;
  final Color labelBorder;

  TextPainter _text(String text) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: labelColor, fontSize: _labelFontSize, fontWeight: FontWeight.w700, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// [size] 상자에서 코너 번호 배지 자리(테스트에서도 쓴다).
  List<CornerLabelPlacement> labelsFor(Size size) {
    if (!trace.hasPositions || size.isEmpty) {
      return const [];
    }
    final texts = <String, TextPainter>{};
    return placeCornerLabels(
      points: _points(size),
      resolutionM: trace.resolutionM.toDouble(),
      corners: corners,
      size: size,
      sizeOf: (label) => _badgeSize(texts.putIfAbsent(label, () => _text(label))),
    );
  }

  List<Offset> _points(Size size) {
    final projection = track.TrackProjection.fit(
      xs: trace.worldPosX,
      zs: trace.worldPosZ,
      width: size.width,
      height: size.height,
      padding: _mapPadding,
    );
    return [for (var i = 0; i < trace.length; i++) projection.project(trace.worldPosX[i], trace.worldPosZ[i])];
  }

  static Size _badgeSize(TextPainter text) => Size(text.width + _labelPadH * 2, text.height + _labelPadV * 2);

  @override
  void paint(Canvas canvas, Size size) {
    if (!trace.hasPositions || size.isEmpty) {
      return;
    }
    final points = _points(size);
    if (points.length > 1) {
      canvas.drawPath(Path()..addPolygon(points, false), _stroke(AppColors.trackOutline, _outlineWidth));
    }
    for (final segment in track.trackSegments(points, sectorIndexes)) {
      final color = kTrackSectorColors[segment.sector.clamp(0, kTrackSectorColors.length - 1)];
      canvas.drawPath(Path()..addPolygon(segment.points, false), _stroke(color, _sectorWidth));
    }

    final texts = <String, TextPainter>{};
    TextPainter textOf(String label) => texts.putIfAbsent(label, () => _text(label));
    final labels = placeCornerLabels(
      points: points,
      resolutionM: trace.resolutionM.toDouble(),
      corners: corners,
      size: size,
      sizeOf: (label) => _badgeSize(textOf(label)),
    );
    final leader = _stroke(labelBorder, _leaderWidth);
    final fill = Paint()..color = labelBackground;
    final border = _stroke(labelBorder, _labelBorder);
    for (final label in labels) {
      final text = textOf(label.text);
      final badgeSize = _badgeSize(text);
      final rect = Rect.fromCenter(center: label.center, width: badgeSize.width, height: badgeSize.height);
      if ((label.center - label.anchor).distance > _labelOffsets.first + _labelClearance) {
        canvas.drawLine(label.anchor, label.center, leader);
      }
      final badge = RRect.fromRectAndRadius(rect, const Radius.circular(_labelRadius));
      canvas
        ..drawRRect(badge, fill)
        ..drawRRect(badge, border);
      text.paint(canvas, rect.center - Offset(text.width / 2, text.height / 2));
    }
  }

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  bool shouldRepaint(RaceTrackMapPainter oldDelegate) =>
      !identical(oldDelegate.trace, trace) ||
      !listEquals(oldDelegate.sectorIndexes, sectorIndexes) ||
      !identical(oldDelegate.corners, corners) ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.labelBackground != labelBackground ||
      oldDelegate.labelBorder != labelBorder;
}

/// 레이스 리뷰 옆 트랙 지도 카드: 섹터 색 트랙 + 코너 번호(공식 번호, 없으면 주행선에서 찾은 번호) + 섹터 범례(섹터를 알 때).
/// 트랙 모양은 내 랩 하나([trace], 위치가 있어야 한다)로 그리고, 섹터 경계는 그 랩의 섹터 시간([sectors])으로 정한다.
class RaceReviewTrackMap extends StatelessWidget {
  const RaceReviewTrackMap({super.key, required this.trace, required this.sectors, this.officialCorners});

  final LapTrace trace;
  final List<LapSector> sectors;
  final List<OfficialCorner>? officialCorners;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sectorIndexes = track.sectorIndexesOf(trace.timeMs, sectors);
    return SessionCard(
      key: const ValueKey('race-review-track-map'),
      title: _title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: _semanticLabel,
            child: LayoutBuilder(
              builder: (context, box) => SizedBox(
                height: raceTrackMapHeight(trace, box.maxWidth),
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: const ValueKey('race-review-track-map-paint'),
                    painter: RaceTrackMapPainter(
                      trace: trace,
                      sectorIndexes: sectorIndexes,
                      corners: resolveLapCorners(trace, officialCorners),
                      labelColor: palette.textPrimary,
                      labelBackground: palette.surface,
                      labelBorder: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (sectorIndexes != null) ...[
            const SizedBox(height: _legendGap),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: _legendSpacing,
              children: [
                for (var i = 0; i < kTrackSectorColors.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: _legendDotSize,
                        height: _legendDotSize,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: kTrackSectorColors[i]),
                      ),
                      const SizedBox(width: _legendDotGap),
                      Text('섹터 ${i + 1}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
