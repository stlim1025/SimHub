import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/section_card.dart';
import '../../auth/domain/user_preferences.dart';
import '../../laps/domain/lap_models.dart';
import '../domain/lap_corners.dart';
import '../domain/lap_detail_models.dart';
import '../domain/telemetry_channels.dart';
import '../domain/telemetry_math.dart';
import '../domain/track_map.dart' as track;
import 'corner_labels.dart';
import 'detail_list.dart';

/// 트랙 지도 높이.
const double kTrackMapHeight = 240;

/// 지도·통계를 나란히 놓는 최소 폭(그 아래면 위아래로 쌓는다).
const double kTrackPanelWideMinWidth = 720;

const String _trackTitle = 'Track';
const String _statsTitle = 'Lap Telemetry';
const String _noPositionsText = '트랙 모양은 위치 데이터가 있는 랩부터 보여요';
const String _trackSemanticLabel = '트랙 지도';
const double _mapPadding = 12;
const double _outlineWidth = 9;
const double _sectorWidth = 4.5;
const double _dotRingRadius = 7;
const double _dotCenterRadius = 4;
const double _panelGap = 16;
const double _legendSpacing = 16;
const double _legendDotGap = 6;
const double _legendDotSize = 8;
const int _mapFlex = 3;
const int _statsFlex = 2;

/// 섹터 색(0 = S1, 1 = S2, 2 = S3). 섹터를 모르면 S1 색 하나로 그린다.
const List<Color> kTrackSectorColors = [AppColors.trackSector1, AppColors.trackSector2, AppColors.trackSector3];

/// 트랙 지도 그림: 굵은 어두운 테두리 + 섹터 색 안쪽 선, 코너 번호 배지([corners]가 있고 [labelStyle]을 줄 때),
/// [cursor] 거리의 표본에 검은 고리 + 흰 점(커서가 없으면 숨김).
/// [cursor]가 바뀌면 다시 그린다(텔레메트리 그래프와 같은 거리를 본다).
class TrackMapPainter extends CustomPainter {
  TrackMapPainter({
    required this.trace,
    required this.sectorIndexes,
    required this.cursor,
    this.corners = const [],
    this.labelStyle,
  }) : super(repaint: cursor);

  final LapTrace trace;

  /// 표본마다 섹터 번호. null이면 한 색.
  final List<int>? sectorIndexes;
  final ValueListenable<double?> cursor;

  /// 번호를 붙일 코너와 배지 모양. 배지 모양이 null이면 번호를 그리지 않는다.
  final List<LapCorner> corners;
  final CornerLabelStyle? labelStyle;

  bool get _showsLabels => corners.isNotEmpty && labelStyle != null;

  /// 코너 번호를 그리면 번호가 들어갈 여백을 더 둔다.
  track.TrackProjection _projection(Size size) => track.TrackProjection.fit(
        xs: trace.worldPosX,
        zs: trace.worldPosZ,
        width: size.width,
        height: size.height,
        padding: _showsLabels ? kCornerLabelMapPadding : _mapPadding,
      );

  /// [size] 상자에서 [cursor] 거리의 점 위치. 커서가 없거나 범위 밖·위치가 없으면 null(테스트에서도 쓴다).
  Offset? dotOffset(Size size) {
    final distance = cursor.value;
    if (distance == null || !trace.hasPositions) {
      return null;
    }
    final index = sampleIndexAt(trace, distance);
    return index == null ? null : _projection(size).project(trace.worldPosX[index], trace.worldPosZ[index]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!trace.hasPositions || size.isEmpty) {
      return;
    }
    final projection = _projection(size);
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
    final style = labelStyle;
    if (_showsLabels && style != null) {
      paintCornerLabels(
        canvas,
        points: points,
        resolutionM: trace.resolutionM.toDouble(),
        corners: corners,
        size: size,
        style: style,
        trackHalfWidth: _outlineWidth / 2,
      );
    }
    final dot = dotOffset(size);
    if (dot != null) {
      canvas
        ..drawCircle(dot, _dotRingRadius, Paint()..color = AppColors.trackDotRing)
        ..drawCircle(dot, _dotCenterRadius, Paint()..color = AppColors.trackDotCenter);
    }
  }

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  bool shouldRepaint(TrackMapPainter oldDelegate) =>
      !identical(oldDelegate.trace, trace) ||
      !listEquals(oldDelegate.sectorIndexes, sectorIndexes) ||
      oldDelegate.cursor != cursor ||
      !identical(oldDelegate.corners, corners) ||
      oldDelegate.labelStyle != labelStyle;
}

/// 트랙 지도(위치가 있는 트레이스만): 그림 + 섹터 범례(섹터를 알 때).
class TrackMap extends StatelessWidget {
  const TrackMap({
    super.key,
    required this.trace,
    required this.sectors,
    required this.cursor,
    this.height = kTrackMapHeight,
    this.showLegend = true,
    this.paintKey = const ValueKey('track-map'),
    this.corners = const [],
  });

  final LapTrace trace;
  final List<LapSector> sectors;
  final ValueListenable<double?> cursor;

  /// 지도에 번호를 붙일 코너(비어 있으면 번호 없음 — 작은 떠 있는 지도).
  final List<LapCorner> corners;

  /// 그림 높이(작은 떠 있는 지도는 더 낮게).
  final double height;

  /// 섹터 범례를 그림 아래에 붙일지.
  final bool showLegend;

  /// 그림(`CustomPaint`)의 키 — 큰 지도와 작은 지도를 테스트에서 구분한다.
  final Key paintKey;

  @override
  Widget build(BuildContext context) {
    final sectorIndexes = track.sectorIndexesOf(trace.timeMs, sectors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: _trackSemanticLabel,
          // SizedBox로 높이를 주어 나란히 놓을 때(IntrinsicHeight)도 지도 높이가 계산된다.
          child: SizedBox(
            height: height,
            child: RepaintBoundary(
              child: CustomPaint(
                key: paintKey,
                painter: TrackMapPainter(
                  trace: trace,
                  sectorIndexes: sectorIndexes,
                  cursor: cursor,
                  corners: corners,
                  labelStyle: corners.isEmpty ? null : cornerLabelStyleOf(context),
                ),
              ),
            ),
          ),
        ),
        if (showLegend && sectorIndexes != null) ...[
          const SizedBox(height: _panelGap),
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
                    Text('Sector ${i + 1}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Telemetry 탭 맨 위 묶음: Track 카드(위치가 있을 때, [corners]의 번호를 붙인다) + Lap Telemetry 통계 카드.
/// 폭이 [kTrackPanelWideMinWidth] 이상이면 나란히, 아니면 위아래. 위치가 없는 옛 랩은 통계 카드에 안내 한 줄을 붙인다.
class LapTelemetryPanel extends StatelessWidget {
  const LapTelemetryPanel({
    super.key,
    required this.trace,
    required this.sectors,
    required this.cursor,
    required this.units,
    this.corners = const [],
  });

  final LapTrace trace;
  final List<LapSector> sectors;
  final ValueListenable<double?> cursor;
  final UnitSystem units;
  final List<LapCorner> corners;

  @override
  Widget build(BuildContext context) {
    final hasMap = trace.hasPositions;
    final stats = SectionCard(
      key: const ValueKey('lap-telemetry-stats'),
      title: _statsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailList(items: _statItems(track.lapTelemetryStatsOf(trace))),
          if (!hasMap) ...[
            const SizedBox(height: _panelGap),
            Text(_noPositionsText, style: TextStyle(color: context.palette.textMuted)),
          ],
        ],
      ),
    );
    if (!hasMap) {
      return stats;
    }
    final map = SectionCard(
      key: const ValueKey('track-map-card'),
      title: _trackTitle,
      child: TrackMap(trace: trace, sectors: sectors, cursor: cursor, corners: corners),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= kTrackPanelWideMinWidth
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: _mapFlex, child: map),
                  const SizedBox(width: _panelGap),
                  Expanded(flex: _statsFlex, child: stats),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [map, const SizedBox(height: _panelGap), stats],
            ),
    );
  }

  List<DetailItem> _statItems(track.LapTelemetryStats stats) {
    String speed(double kph) =>
        TelemetryChannel.speed.format(units == UnitSystem.imperial ? kphToMph(kph) : kph, units);
    String percent(double value) => TelemetryChannel.throttle.format(value, units);
    return [
      DetailItem('Top Speed', text: speed(stats.topSpeedKph)),
      DetailItem('Average Speed', text: speed(stats.averageSpeedKph)),
      DetailItem('Average Throttle', text: percent(stats.averageThrottle)),
      DetailItem('Average Brake', text: percent(stats.averageBrake)),
    ];
  }
}
