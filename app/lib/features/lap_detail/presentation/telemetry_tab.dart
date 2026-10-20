import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Telemetry 탭(docs/15 §2.3): 맨 위 트랙 지도·Lap Telemetry 통계, 그 아래 (비교 랩 트레이스가 있으면) Delta · Speed · Throttle · Brake · Gear · Steering · RPM.
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
    // 맨 위: 트랙 지도(같은 십자선 거리에 점) + Lap Telemetry 통계.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LapTelemetryPanel(trace: trace, sectors: widget.sectors, cursor: _cursor, units: widget.units),
        const SizedBox(height: _panelGap),
        chartsCard,
      ],
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
