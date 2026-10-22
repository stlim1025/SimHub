import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/viewport_pinned.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_preferences.dart';
import '../../laps/domain/lap_models.dart';
import '../../laps/presentation/empty_laps_card.dart';
import '../application/lap_detail_providers.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_detail_models.dart';
import '../domain/telemetry_channels.dart';
import '../domain/telemetry_math.dart';
import 'lap_time_cards.dart';
import 'telemetry_chart.dart';
import 'track_map.dart';

const String _noTraceText = '이 랩은 텔레메트리가 저장되지 않았어요(새 Agent로 달린 랩부터 저장돼요)';
const String _thisLapLabel = '이 랩';
const String _bestLapLabel = '내 최고 랩';
const double _chartGap = 20;
const double _legendSpacing = 16;
const double _legendDotGap = 6;
const double _deltaChartHeight = 90;
const double _panelGap = 16;
const EdgeInsets _cardPadding = EdgeInsets.all(16);
const double _miniMapElevation = 6;
const double _miniMapRadius = 12;
const double _miniMapIconSize = 18;
const String _miniMapCollapseTooltip = '작은 지도 접기';
const String _miniMapExpandTooltip = '작은 트랙 지도 보기';

/// 탭 폭이 이 이상이면 그래프 옆에 지도·통계 칸을 두고 스크롤해도 붙여 둔다(그 아래면 위아래 + 떠 있는 작은 지도).
const double kTelemetrySideBySideMinWidth = 900;

/// 넓은 화면 오른쪽 지도·통계 칸 폭.
const double kTelemetryAsideWidth = 400;

/// 좁은 화면에서 떠 있는 작은 트랙 지도의 한 변.
const double kMiniTrackMapSize = 170;

/// Telemetry 탭(docs/15 §2.3): 트랙 지도·Lap Telemetry 통계와 (비교 랩 트레이스가 있으면) Delta · Speed · Throttle · Brake · Gear · Steering · RPM.
/// 넓은 화면은 그래프 오른쪽에 지도·통계를 붙여 두고(스크롤해도 보임), 좁은 화면은 지도를 지나치면 작은 지도를 띄운다.
/// 가로 = 랩 거리, 이 랩은 강조색, 비교 랩(내 최고 랩)은 청록. 그래프 위에 마우스를 올리거나 누르면 모든 그래프에 같은 거리의 십자선과
/// 두 랩의 값이 보인다. 속도 단위는 사용자 설정(`units`). 트레이스가 없으면 안내.
class TelemetryTab extends ConsumerWidget {
  const TelemetryTab({super.key, required this.detail, this.compare = LapCompareSelection.defaults});

  final LapDetail detail;

  /// 고른 비교(D-51). "비교 안 함"이면 비교 선·Delta 그래프가 없다.
  final LapCompareSelection compare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lap = detail.lap;
    if (!lap.hasTrace) {
      return const EmptyLapsCard(message: _noTraceText);
    }
    final comparison = compare.kind == LapCompareKind.none ? null : detail.comparison;
    final comparisonId = comparison != null && comparison.hasTrace && comparison.lapId != lap.lapId
        ? comparison.lapId
        : null;
    final trace = ref.watch(lapTraceProvider(lap.lapId));
    // 비교 랩 트레이스는 공개 규칙을 지키는 경로(`/laps/{id}/trace`)로 읽는다 — 남의 공개 랩도 여기로 온다(D-51).
    final reference = comparisonId == null ? null : ref.watch(comparisonTraceProvider(comparisonId));
    final units = ref.watch(authControllerProvider).valueOrNull?.preferences.units ?? UnitSystem.metric;

    // 비교 랩 트레이스가 아직 오는 중이면 기다린다. 실패하면 이 랩만 그린다.
    if (trace.isLoading || (reference?.isLoading ?? false)) {
      return const PageLoadingBar();
    }
    return trace.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: '텔레메트리를 불러오지 못했어요.',
        onRetry: () => ref.invalidate(lapTraceProvider(lap.lapId)),
      ),
      data: (data) => data == null || data.isEmpty
          ? const EmptyLapsCard(message: _noTraceText)
          : TelemetryCharts(
              trace: data,
              reference: reference?.valueOrNull,
              lapTimeMs: lap.lapTimeMs,
              referenceLapTimeMs: comparison?.lapTimeMs,
              referenceLabel: comparison == null ? _bestLapLabel : referenceLegendLabel(comparison),
              units: units,
              sectors: lap.sectors,
            ),
    );
  }
}

/// 범례의 비교 랩 이름: 비교 종류별 행 이름, 남의 랩이면 ` · {드라이버}`(D-51).
String referenceLegendLabel(ComparisonLap comparison) {
  final base = comparisonRowLabel(comparison.kind);
  final owner = comparison.isMine ? null : comparison.displayName;
  return owner == null ? base : '$base · $owner';
}

/// 트레이스가 준비된 뒤의 그래프 묶음. 십자선 거리([_cursor])를 모든 그래프가 함께 본다.
class TelemetryCharts extends StatefulWidget {
  const TelemetryCharts({
    super.key,
    required this.trace,
    required this.reference,
    required this.lapTimeMs,
    required this.referenceLapTimeMs,
    required this.units,
    this.referenceLabel = _bestLapLabel,
    this.sectors = const [],
  });

  final LapTrace trace;

  /// 비교 랩 트레이스. 없으면 Delta 그래프·청록 선이 없다.
  final LapTrace? reference;
  final int lapTimeMs;
  final int? referenceLapTimeMs;
  final UnitSystem units;

  /// 범례의 비교 랩 이름(`내 최고 랩`·`리더보드 랩 · 익명 드라이버` …).
  final String referenceLabel;

  /// 이 랩의 섹터 시간 — 트랙 지도의 섹터 색 경계를 정한다. 비어 있으면 한 색.
  final List<LapSector> sectors;

  @override
  State<TelemetryCharts> createState() => _TelemetryChartsState();
}

class _TelemetryChartsState extends State<TelemetryCharts> {
  /// 십자선이 가리키는 랩 거리(m). null이면 숨김.
  final ValueNotifier<double?> _cursor = ValueNotifier<double?>(null);

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final trace = widget.trace;
    final reference = widget.reference;
    final maxDistanceM = math.max(trace.lengthM, reference?.lengthM ?? 0);
    final referenceTime = widget.referenceLapTimeMs;

    Widget channelChart(TelemetryChannel channel) {
      final series = [
        ChartSeries(values: channel.valuesOf(trace, widget.units), resolutionM: trace.resolutionM, color: AppColors.accent),
        if (reference != null)
          ChartSeries(
            values: channel.valuesOf(reference, widget.units),
            resolutionM: reference.resolutionM,
            color: palette.comparison,
          ),
      ];
      return TelemetryChart(
        key: ValueKey('telemetry-chart-${channel.name}'),
        title: channel.title,
        series: series,
        range: channel.rangeOf(series.expand((s) => s.values)),
        maxDistanceM: maxDistanceM,
        cursor: _cursor,
        format: (value) => channel.format(value, widget.units),
        axisLabel: channel.axisLabel,
      );
    }

    final charts = <Widget>[
      if (reference != null) _deltaChart(trace, reference, maxDistanceM),
      for (final channel in kTelemetryChannels) channelChart(channel),
    ];

    final chartsCard = Card(
      child: Padding(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Legend(
              thisLapText: '$_thisLapLabel ${formatLapTime(widget.lapTimeMs)}',
              referenceText: reference == null || referenceTime == null
                  ? null
                  : '${widget.referenceLabel} ${formatLapTime(referenceTime)}',
              cursor: _cursor,
            ),
            for (final chart in charts) ...[const SizedBox(height: _chartGap), chart],
          ],
        ),
      ),
    );
    // 트랙 지도(같은 십자선 거리에 점) + Lap Telemetry 통계.
    final panel = LapTelemetryPanel(trace: trace, sectors: widget.sectors, cursor: _cursor, units: widget.units);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= kTelemetrySideBySideMinWidth
          // 넓은 화면: 왼쪽 그래프, 오른쪽 지도·통계 칸 — 스크롤해도 화면 위쪽에 붙어 있다.
          ? ViewportPinned(
              key: const ValueKey('telemetry-wide-layout'),
              asideWidth: kTelemetryAsideWidth,
              gap: _panelGap,
              main: chartsCard,
              pinned: KeyedSubtree(key: const ValueKey('telemetry-aside'), child: panel),
            )
          // 좁은 화면: 위에서부터 지도·통계 → 그래프. 지도가 화면 위로 지나가면 오른쪽 아래에 작은 지도.
          : _NarrowTelemetryLayout(
              panel: panel,
              charts: chartsCard,
              trace: trace,
              sectors: widget.sectors,
              cursor: _cursor,
            ),
    );
  }

  /// Delta = 같은 거리에서 이 랩 시간 − 비교 랩 시간(초), 0 기준선.
  Widget _deltaChart(LapTrace trace, LapTrace reference, double maxDistanceM) {
    final values = deltaSeconds(trace, reference);
    return TelemetryChart(
      key: const ValueKey('telemetry-chart-delta'),
      title: 'Delta',
      series: [ChartSeries(values: values, resolutionM: trace.resolutionM, color: AppColors.accent)],
      range: valueRangeOf(values, symmetric: true),
      maxDistanceM: maxDistanceM,
      cursor: _cursor,
      baseline: 0,
      height: _deltaChartHeight,
      format: formatDeltaSeconds,
    );
  }
}

/// 좁은 화면 배치: 지도·통계 묶음 아래에 그래프. 지도 묶음의 아래 끝이 화면 위로 지나가면
/// 보이는 영역 오른쪽 아래에 같은 십자선 점을 그리는 작은 트랙 지도를 띄운다. 접으면 지도 아이콘 버튼만 남는다.
class _NarrowTelemetryLayout extends StatefulWidget {
  const _NarrowTelemetryLayout({
    required this.panel,
    required this.charts,
    required this.trace,
    required this.sectors,
    required this.cursor,
  });

  final Widget panel;
  final Widget charts;
  final LapTrace trace;
  final List<LapSector> sectors;
  final ValueNotifier<double?> cursor;

  @override
  State<_NarrowTelemetryLayout> createState() => _NarrowTelemetryLayoutState();
}

class _NarrowTelemetryLayoutState extends State<_NarrowTelemetryLayout> {
  final GlobalKey _panelKey = GlobalKey();

  /// 큰 지도 묶음이 화면 위로 지나갔는지.
  final ValueNotifier<bool> _panelPassed = ValueNotifier<bool>(false);

  /// 작은 지도를 접었는지(스크롤로 숨었다 다시 나와도 기억한다).
  final ValueNotifier<bool> _collapsed = ValueNotifier<bool>(false);
  ScrollPosition? _position;

  /// 다음 프레임 뒤 확인이 이미 예약됐는지(스크롤 알림이 여러 번 와도 한 번만).
  bool _updateScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_scheduleUpdate);
      _position = position?..addListener(_scheduleUpdate);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleUpdate);
    _panelPassed.dispose();
    _collapsed.dispose();
    super.dispose();
  }

  /// 스크롤 알림은 뷰포트가 다시 배치되기 전에 오므로(좌표가 아직 옛 값) 그 프레임이 끝난 뒤에 잰다.
  void _scheduleUpdate() {
    if (_updateScheduled) {
      return;
    }
    _updateScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _updateScheduled = false;
        if (mounted) _updatePanelPassed();
      })
      ..ensureVisualUpdate();
  }

  /// 묶음의 아래 끝이 뷰포트 위쪽(0) 이하이면 지나간 것.
  void _updatePanelPassed() {
    final box = _panelKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox) {
      _panelPassed.value = false;
      return;
    }
    final bottom = box.localToGlobal(Offset(0, box.size.height), ancestor: viewport).dy;
    _panelPassed.value = bottom <= 0;
  }

  @override
  Widget build(BuildContext context) {
    // 크기가 바뀌어 스크롤 없이 위치가 달라질 때도 맞춘다.
    _scheduleUpdate();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(key: _panelKey, child: widget.panel),
        const SizedBox(height: _panelGap),
        widget.charts,
      ],
    );
    if (!widget.trace.hasPositions) {
      return content;
    }
    return ViewportPinned(
      key: const ValueKey('telemetry-narrow-layout'),
      edge: ViewportPinEdge.bottom,
      main: content,
      pinned: ListenableBuilder(
        listenable: Listenable.merge([_panelPassed, _collapsed]),
        builder: (context, _) {
          if (!_panelPassed.value) {
            return const SizedBox.shrink();
          }
          return _collapsed.value
              ? _MiniMapExpandButton(onPressed: () => _collapsed.value = false)
              : _MiniTrackMap(
                  trace: widget.trace,
                  sectors: widget.sectors,
                  cursor: widget.cursor,
                  onCollapse: () => _collapsed.value = true,
                );
        },
      ),
    );
  }
}

/// 떠 있는 작은 트랙 지도: 테두리 있는 정사각 카드(섹터 색·십자선 점은 큰 지도와 같다) + 오른쪽 위 접기 버튼.
class _MiniTrackMap extends StatelessWidget {
  const _MiniTrackMap({required this.trace, required this.sectors, required this.cursor, required this.onCollapse});

  final LapTrace trace;
  final List<LapSector> sectors;
  final ValueNotifier<double?> cursor;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      key: const ValueKey('mini-track-map'),
      color: palette.surface,
      elevation: _miniMapElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_miniMapRadius),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox.square(
        dimension: kMiniTrackMapSize,
        child: Stack(
          children: [
            TrackMap(
              trace: trace,
              sectors: sectors,
              cursor: cursor,
              height: kMiniTrackMapSize,
              showLegend: false,
              paintKey: const ValueKey('mini-track-map-paint'),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                key: const ValueKey('mini-track-map-collapse'),
                tooltip: _miniMapCollapseTooltip,
                iconSize: _miniMapIconSize,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_fullscreen, color: palette.textMuted),
                onPressed: onCollapse,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 접힌 작은 지도: 누르면 다시 펼치는 동그란 지도 아이콘 버튼.
class _MiniMapExpandButton extends StatelessWidget {
  const _MiniMapExpandButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      elevation: _miniMapElevation,
      shape: CircleBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        key: const ValueKey('mini-track-map-expand'),
        tooltip: _miniMapExpandTooltip,
        icon: const Icon(Icons.map_outlined),
        onPressed: onPressed,
      ),
    );
  }
}

/// 범례: 이 랩(강조색)·내 최고 랩(청록)과 각 랩타임, 십자선이 있으면 그 거리.
class _Legend extends StatelessWidget {
  const _Legend({required this.thisLapText, required this.referenceText, required this.cursor});

  final String thisLapText;
  final String? referenceText;
  final ValueNotifier<double?> cursor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reference = referenceText;
    Widget item(Color color, String text, Key key) => Row(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: [
            ChartDot(color: color),
            const SizedBox(width: _legendDotGap),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        );
    return Wrap(
      spacing: _legendSpacing,
      runSpacing: _legendDotGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        item(AppColors.accent, thisLapText, const ValueKey('legend-this-lap')),
        if (reference != null) item(palette.comparison, reference, const ValueKey('legend-reference-lap')),
        ValueListenableBuilder<double?>(
          valueListenable: cursor,
          builder: (context, distance, _) => distance == null
              ? const SizedBox.shrink()
              : Text(
                  formatDistance(distance),
                  key: const ValueKey('telemetry-cursor-distance'),
                  style: TextStyle(color: palette.textMuted),
                ),
        ),
      ],
    );
  }
}
