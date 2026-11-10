import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/lap_time.dart';
import '../../../core/widgets/stat.dart';
import '../../lap_detail/application/lap_detail_providers.dart';
import '../../lap_detail/domain/lap_compare.dart' show LapDetailKey;
import '../../lap_detail/presentation/detail_list.dart';
import '../../laps/domain/lap_display.dart';
import '../../sessions/presentation/race_review_track_map.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../application/track_corners_provider.dart';
import '../application/track_outlines_provider.dart';
import '../application/tracks_providers.dart';
import '../domain/track_overview_models.dart';
import 'track_outline_view.dart';

const String _mapTitle = '트랙 지도';
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
const double _statSpacing = 28;
const double _statRunSpacing = 16;

/// 목록 보드 오른쪽 카드 열(랩 목록·리더보드): 트랙 지도 카드(레이스 리뷰 옆 지도와 같은 카드 — 섹터 색 · 코너 번호 · 섹터 범례),
/// 트랙 정보 카드(서킷 · 길이 · F1 랩 레코드), 내 기록 요약 카드(최고 랩 · Time Trial 최고 · 평균 랩 · 평균 AI · 랩 수 · 세션 수).
/// 트랙 개요를 못 받으면 아무것도 그리지 않는다.
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
    final length = track.lengthKm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrackMapSection(trackName: track.name, lapId: overview.mapLapId),
        SessionCard(
          key: const ValueKey('track-side-info'),
          title: track.name,
          child: DetailList(
            items: [
              DetailItem(_detailCircuit, text: track.circuitName ?? kLapNoValueText),
              DetailItem(
                _detailLength,
                text: length == null ? kLapNoValueText : '${length.toStringAsFixed(_lengthFractionDigits)} $_kmUnit',
              ),
              DetailItem(_detailLapRecord, text: track.f1LapRecord ?? kLapNoValueText),
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

/// 트랙 지도 카드(+ 아래 간격): 트랙 개요의 지도 랩([lapId])이 있으면 그 랩 트레이스로 섹터 색·코너 번호를 그린 지도
/// ([RaceReviewTrackMap]), 없거나 위치가 없으면 서킷 윤곽. 둘 다 없으면 카드를 두지 않는다.
/// 트레이스·섹터 시간·공식 코너를 다 받을 때까지는 그리지 않는다(윤곽 → 한 색 → 섹터 색으로 바뀌어 보이지 않게).
class _TrackMapSection extends ConsumerWidget {
  const _TrackMapSection({required this.trackName, required this.lapId});

  final String trackName;
  final String? lapId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lapId = this.lapId;
    final Widget? card;
    if (lapId == null) {
      card = _outlineCard(ref);
    } else {
      final trace = ref.watch(comparisonTraceProvider(lapId));
      final detail = ref.watch(lapDetailProvider(LapDetailKey(lapId)));
      final corners = ref.watch(trackCornersProvider);
      if (trace.isLoading || detail.isLoading || corners.isLoading) {
        return const SizedBox.shrink();
      }
      final lapTrace = trace.valueOrNull;
      card = lapTrace == null || !lapTrace.hasPositions
          ? _outlineCard(ref)
          : RaceReviewTrackMap(
              trace: lapTrace,
              sectors: detail.valueOrNull?.lap.sectors ?? const [],
              officialCorners: corners.valueOrNull?[trackName],
            );
    }
    if (card == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [card, const SizedBox(height: _cardGap)],
    );
  }

  Widget? _outlineCard(WidgetRef ref) {
    final outline = ref.watch(trackOutlinesProvider).valueOrNull?[trackName];
    return outline == null
        ? null
        : SessionCard(
            key: const ValueKey('track-side-outline'),
            title: _mapTitle,
            child: TrackOutlineView(outline: outline),
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
