import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_preferences.dart';
import '../../laps/presentation/empty_laps_card.dart';
import '../../tracks/application/track_corners_provider.dart';
import '../application/lap_detail_providers.dart';
import '../domain/lap_analysis.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_corners.dart';
import '../domain/lap_detail_models.dart';
import 'lap_analysis_card.dart';
import 'telemetry_tab.dart';

const String _noTraceText = '이 랩은 텔레메트리가 저장되지 않아 분석할 수 없어요.';
const String _raceSessionType = 'Race';
const double _gap = 16;

/// 분석 기준 선택지.
const List<({AnalysisFocus value, String label})> kAnalysisFocusOptions = [
  (value: AnalysisFocus.pace, label: '최대 속도'),
  (value: AnalysisFocus.battery, label: '배터리 관리'),
  (value: AnalysisFocus.tyres, label: '타이어 관리'),
];

/// 세션 종류의 기본 분석 기준: 레이스는 타이어 관리, 그 밖(퀄리·타임 트라이얼·연습)은 최대 속도.
AnalysisFocus defaultAnalysisFocus(String sessionType) =>
    sessionType == _raceSessionType ? AnalysisFocus.tyres : AnalysisFocus.pace;

/// Analysis 탭: 분석 기준(최대 속도·배터리·타이어)을 고르면 그 기준의 조언과, 비교 랩이 있으면 코너마다 잃은 시간·이유를 보인다.
class AnalysisTab extends ConsumerStatefulWidget {
  const AnalysisTab({super.key, required this.detail, this.compare = LapCompareSelection.defaults});

  final LapDetail detail;
  final LapCompareSelection compare;

  @override
  ConsumerState<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends ConsumerState<AnalysisTab> {
  late AnalysisFocus _focus = defaultAnalysisFocus(widget.detail.lap.sessionType);

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final lap = detail.lap;
    if (!lap.hasTrace) {
      return const EmptyLapsCard(message: _noTraceText);
    }
    final traces = watchLapTraces(ref, detail, widget.compare);
    final trace = traces.trace;
    final reference = traces.reference;
    if (trace.isLoading || (reference?.isLoading ?? false)) {
      return const PageLoadingBar();
    }
    final units = ref.watch(authControllerProvider).valueOrNull?.preferences.units ?? UnitSystem.metric;
    final official = ref.watch(trackCornersProvider).valueOrNull?[lap.trackName];
    return trace.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: '텔레메트리를 불러오지 못했어요.',
        onRetry: () => ref.invalidate(lapTraceProvider(lap.lapId)),
      ),
      data: (data) {
        if (data == null || data.isEmpty) {
          return const EmptyLapsCard(message: _noTraceText);
        }
        final referenceTrace = reference?.valueOrNull;
        final analysis = analyzeLap(data, referenceTrace, resolveLapCorners(data, official), focus: _focus);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ButtonGroup<AnalysisFocus>(
                options: kAnalysisFocusOptions,
                selected: _focus,
                onSelected: (focus) => setState(() => _focus = focus),
                segmentKeyOf: (focus) => ValueKey('analysis-focus-${focus.name}'),
              ),
            ),
            const SizedBox(height: _gap),
            LapAnalysisCard(
              analysis: analysis,
              referenceLabel: referenceTrace == null
                  ? null
                  : lapReferenceLabel(
                      otherCar: traces.otherCar,
                      comparison: traces.comparison,
                      otherCarName: traces.otherCarName,
                    ),
              units: units,
              tyreWearStart: detail.car?.tyreWearStart,
              tyreWearEnd: detail.car?.tyreWearEnd,
            ),
          ],
        );
      },
    );
  }
}
