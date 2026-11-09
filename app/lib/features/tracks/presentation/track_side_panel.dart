import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/lap_time.dart';
import '../../../core/widgets/stat.dart';
import '../../lap_detail/presentation/detail_list.dart';
import '../../laps/domain/lap_display.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../application/track_outlines_provider.dart';
import '../application/tracks_providers.dart';
import '../domain/track_overview_models.dart';
import 'track_outline_view.dart';

const String _statsTitle = 'My stats';
const String _detailCircuit = 'Circuit';
const String _detailLength = 'Length';
const String _detailLapRecord = 'F1 Lap Record';
const String _statBestLap = 'Best lap';
const String _statBestTimeTrial = 'Time Trial best';
const String _statAverageLap = 'Average lap';
const String _statAverageAi = 'Average AI';
const String _statLaps = 'Laps';
const String _statSessions = 'Sessions';
const String _kmUnit = 'km';
const int _lengthFractionDigits = 3;

const double _cardGap = 20;
const double _mapGap = 16;
const double _statSpacing = 28;
const double _statRunSpacing = 16;

/// 목록 보드 오른쪽 카드 열(랩 목록·리더보드): [trackId] 트랙의 지도(서킷 윤곽)·정보(서킷·길이·F1 랩 레코드)와
/// 내 기록 요약(최고 랩 · Time Trial 최고 · 평균 랩 · 평균 AI · 랩 수 · 세션 수). 트랙 개요를 못 받으면 아무것도 그리지 않는다.
class TrackSidePanel extends ConsumerWidget {
  const TrackSidePanel({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(trackOverviewProvider(trackId)).valueOrNull;
    if (overview == null) {
      return const SizedBox.shrink();
    }
    final track = overview.track;
    final outline = ref.watch(trackOutlinesProvider).valueOrNull?[track.name];
    final length = track.lengthKm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SessionCard(
          key: const ValueKey('track-side-info'),
          title: track.name,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (outline != null) ...[TrackOutlineView(outline: outline), const SizedBox(height: _mapGap)],
              DetailList(
                items: [
                  DetailItem(_detailCircuit, text: track.circuitName ?? kLapNoValueText),
                  DetailItem(
                    _detailLength,
                    text: length == null ? kLapNoValueText : '${length.toStringAsFixed(_lengthFractionDigits)} $_kmUnit',
                  ),
                  DetailItem(_detailLapRecord, text: track.f1LapRecord ?? kLapNoValueText),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: _cardGap),
        SessionCard(
          key: const ValueKey('track-side-stats'),
          title: _statsTitle,
          child: _StatsGrid(stats: overview.myStats),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final TrackMyStats stats;

  @override
  Widget build(BuildContext context) {
    String ms(int? value) => value == null ? kLapNoValueText : formatLapTime(value);
    final ai = stats.averageAiDifficulty;
    return Wrap(
      spacing: _statSpacing,
      runSpacing: _statRunSpacing,
      children: [
        Stat(label: _statBestLap, value: ms(stats.bestLapMs)),
        Stat(label: _statBestTimeTrial, value: ms(stats.bestTimeTrialLapMs)),
        Stat(label: _statAverageLap, value: ms(stats.averageLapMs)),
        Stat(label: _statAverageAi, value: ai == null ? kLapNoValueText : '${ai.round()}'),
        Stat(label: _statLaps, value: '${stats.lapCount}'),
        Stat(label: _statSessions, value: '${stats.sessionCount}'),
      ],
    );
  }
}
