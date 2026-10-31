import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../lap_detail/domain/lap_corners.dart';
import '../../lap_detail/domain/lap_detail_models.dart';
import '../../lap_detail/domain/track_map.dart' as track;
import '../../lap_detail/presentation/corner_labels.dart';
import '../../lap_detail/presentation/track_map.dart' show kTrackSectorColors;
import '../../laps/domain/lap_models.dart';
import 'session_widgets.dart';

const String _title = '트랙 지도';
const String _semanticLabel = '섹터와 코너 번호가 적힌 트랙 지도';

/// 지도 높이 범위(트랙 가로세로 비율을 따르되 이 안으로).
const double kRaceTrackMapMinHeight = 180;
const double kRaceTrackMapMaxHeight = 320;
const double _outlineWidth = 8;
const double _sectorWidth = 4;

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
  final inner = math.max(0.0, width - kCornerLabelMapPadding * 2);
  final height = spanX <= 0 ? kRaceTrackMapMaxHeight : inner * spanZ / spanX + kCornerLabelMapPadding * 2;
  return height.clamp(kRaceTrackMapMinHeight, kRaceTrackMapMaxHeight);
}

/// 레이스 리뷰 옆 트랙 지도 그림: 어두운 테두리 + 섹터 색 선, 코너마다 번호 배지([paintCornerLabels]).
class RaceTrackMapPainter extends CustomPainter {
  RaceTrackMapPainter({
    required this.trace,
    required this.sectorIndexes,
    required this.corners,
    required this.labelStyle,
  });

  final LapTrace trace;

  /// 표본마다 섹터 번호. null이면 한 색.
  final List<int>? sectorIndexes;
  final List<LapCorner> corners;
  final CornerLabelStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (!trace.hasPositions || size.isEmpty) {
      return;
    }
    final projection = track.TrackProjection.fit(
      xs: trace.worldPosX,
      zs: trace.worldPosZ,
      width: size.width,
      height: size.height,
      padding: kCornerLabelMapPadding,
    );
    final points = [
      for (var i = 0; i < trace.length; i++) projection.project(trace.worldPosX[i], trace.worldPosZ[i]),
    ];
    if (points.length > 1) {
      canvas.drawPath(Path()..addPolygon(points, false), _stroke(AppColors.trackOutline, _outlineWidth));
    }
    for (final segment in track.trackSegments(points, sectorIndexes)) {
      final color = kTrackSectorColors[segment.sector.clamp(0, kTrackSectorColors.length - 1)];
      canvas.drawPath(Path()..addPolygon(segment.points, false), _stroke(color, _sectorWidth));
    }
    paintCornerLabels(
      canvas,
      points: points,
      resolutionM: trace.resolutionM.toDouble(),
      corners: corners,
      size: size,
      style: labelStyle,
      trackHalfWidth: _outlineWidth / 2,
    );
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
      oldDelegate.labelStyle != labelStyle;
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
                      labelStyle: cornerLabelStyleOf(context),
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
