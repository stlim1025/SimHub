import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_preferences.dart';
import '../../laps/domain/lap_models.dart';
import '../../laps/presentation/empty_laps_card.dart';
import '../../tracks/application/track_corners_provider.dart';
import '../../tracks/application/track_widths_provider.dart';
import '../../tracks/application/tracks_providers.dart';
import '../../tracks/domain/track_width_profile.dart';
import '../application/lap_detail_providers.dart';
import '../domain/lap_analysis.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_corners.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import 'ghost_replay.dart';
import 'lap_analysis_card.dart';
import 'telemetry_tab.dart';
import 'track_map.dart';

const String _noTraceText = '이 랩은 텔레메트리가 저장되지 않아 분석할 수 없어요.';
const String _raceSessionType = 'Race';
const double _gap = 16;
const String _thisLapLabel = '이 랩';

/// 코너를 눌러 리플레이로 올라갈 때 스크롤 시간.
const Duration _scrollToReplay = Duration(milliseconds: 350);

/// 네 바퀴 평균 마모(%). 하나라도 모르면 null.
double? averageWear(WheelValues? wear) {
  final values = [wear?.frontLeft, wear?.frontRight, wear?.rearLeft, wear?.rearRight];
  if (values.any((v) => v == null)) {
    return null;
  }
  return values.fold<double>(0, (sum, v) => sum + v!) / values.length;
}

/// 분석 기준 선택지.
const List<({AnalysisFocus value, String label})> kAnalysisFocusOptions = [
  (value: AnalysisFocus.pace, label: '최대 속도'),
  (value: AnalysisFocus.battery, label: '배터리 관리'),
  (value: AnalysisFocus.tyres, label: '타이어 관리'),
];

/// 세션 종류의 기본 분석 기준: 레이스는 타이어 관리, 그 밖(퀄리·타임 트라이얼·연습)은 최대 속도.
AnalysisFocus defaultAnalysisFocus(String sessionType) =>
    sessionType == _raceSessionType ? AnalysisFocus.tyres : AnalysisFocus.pace;

/// Analysis 탭: Telemetry 탭과 같은 배치(오른쪽·위 트랙 지도·Lap Telemetry 통계)에서 그래프 대신
/// 이 랩(비교 랩이 있으면 고스트와 함께) 리플레이와 분석 기준(최대 속도·배터리·타이어)별 조언, 비교 랩이 있으면 코너마다 잃은 시간·이유.
/// 코너 줄을 누르면 리플레이로 올라가 그 코너 앞부터 보여 준다.
class AnalysisTab extends ConsumerStatefulWidget {
  const AnalysisTab({super.key, required this.detail, this.compare = LapCompareSelection.defaults});

  final LapDetail detail;
  final LapCompareSelection compare;

  @override
  ConsumerState<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends ConsumerState<AnalysisTab> {
  late AnalysisFocus _focus = defaultAnalysisFocus(widget.detail.lap.sessionType);

  /// 리플레이가 쓰는 이 랩의 재생 위치(랩 거리)·밖에서 옮기는 손잡이·리플레이 자리(스크롤 대상).
  final ValueNotifier<double?> _replayCursor = ValueNotifier<double?>(null);
  final GhostReplaySeek _seek = GhostReplaySeek();
  final GlobalKey _replayKey = GlobalKey();

  @override
  void dispose() {
    _replayCursor.dispose();
    _seek.dispose();
    super.dispose();
  }

  /// 코너 줄을 누르면: 리플레이가 보이게 올리고 그 코너 시작 조금 앞으로 옮긴다.
  void _showCorner(LapCorner corner) {
    final replay = _replayKey.currentContext;
    if (replay != null) {
      Scrollable.ensureVisible(replay, duration: _scrollToReplay, curve: Curves.easeOut);
    }
    _seek.seekToDistance(corner.startM - kReplayCornerLeadM);
  }

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
    // 서킷 재료도 기다려 다시보기를 한 번에 제대로 그린다.
    final circuitLoading = watchReplayCircuitLoading(ref, trackId: detail.trackId, gameCode: lap.gameCode);
    if (trace.isLoading || (reference?.isLoading ?? false) || circuitLoading) {
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
        final corners = resolveLapCorners(data, official);
        final comparison = traces.otherCar ? null : traces.comparison;
        final analysis = analyzeLap(
          data,
          referenceTrace,
          corners,
          focus: _focus,
          tyres: TyreCondition(
            wearPct: averageWear(detail.car?.tyreWearEnd),
            referenceWearPct: comparison?.tyreWearPercent,
            compound: visualCompoundName(detail.car?.visualTyreCompound),
            referenceCompound: visualCompoundName(comparison?.visualTyreCompound),
          ),
        );
        final referenceLabel = lapReferenceLabel(
          otherCar: traces.otherCar,
          comparison: traces.comparison,
          otherCarName: traces.otherCarName,
        );
        final otherCarColor = widget.compare.compareTeamColor;
        Widget main(double replayHeight) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data.hasPositions) ...[
              KeyedSubtree(
                key: _replayKey,
                child: GhostReplay(
                  trace: data,
                  reference: referenceTrace,
                  cursor: _replayCursor,
                  units: units,
                  height: replayHeight,
                  thisLapLabel: _thisLapLabel,
                  referenceLabel: referenceLabel,
                  playerTeam: lap.team,
                  referenceTeam: traces.otherCar
                      ? (otherCarColor == null ? null : LapTeam(name: traces.otherCarName, color: otherCarColor))
                      : traces.comparison?.team,
                  playerSectors: lap.sectors,
                  referenceSectors: referenceTrace == null ? const [] : traces.comparison?.sectors ?? const [],
                  playerTyreCompound: visualCompoundName(detail.car?.visualTyreCompound),
                  referenceTyreCompound: referenceTrace == null || traces.otherCar
                      ? null
                      : visualCompoundName(traces.comparison?.visualTyreCompound),
                  realTrack: ref.watch(trackWidthsProvider).valueOrNull?[lap.trackName],
                  trackSamples:
                      ref.watch(trackGeometryProvider((trackId: detail.trackId, gameCode: lap.gameCode))).valueOrNull,
                  estimatedTrackWidthM: kEstimatedTrackWidthsM[lap.trackName],
                  streetCircuit: kStreetCircuits.contains(lap.trackName),
                  corners: corners,
                  seek: _seek,
                ),
              ),
              const SizedBox(height: _gap),
            ],
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
              referenceLabel: referenceTrace == null ? null : referenceLabel,
              units: units,
              tyreWearStart: detail.car?.tyreWearStart,
              tyreWearEnd: detail.car?.tyreWearEnd,
              onSelect: data.hasPositions ? _showCorner : null,
            ),
          ],
        );
        return LapPanelLayout(
          panel: LapTelemetryPanel(
            trace: data,
            sectors: lap.sectors,
            cursor: _replayCursor,
            units: units,
            corners: corners,
          ),
          main: main,
          trace: data,
          sectors: lap.sectors,
          cursor: _replayCursor,
        );
      },
    );
  }
}
