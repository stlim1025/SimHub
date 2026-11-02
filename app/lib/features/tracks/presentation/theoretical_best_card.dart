import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/stat.dart';
import '../../lap_detail/domain/lap_corners.dart' show OfficialCorner;
import '../../lap_detail/domain/lap_detail_display.dart';
import '../../laps/domain/lap_display.dart';
import '../../sessions/presentation/session_widgets.dart' show kTabularStyle;
import '../application/track_corners_provider.dart';
import '../application/tracks_providers.dart';
import '../domain/theoretical_best.dart';

const String _title = 'Theoretical Best';
const String _errorMessage = '이론상 최고 랩을 불러오지 못했다.';
const String _emptyMessage = '이론상 최고 랩은 텔레메트리가 온전히 기록된 유효한 Time Trial·예선 랩으로 계산한다. 이 트랙에는 아직 그런 랩이 없다.';
const String _rainLabel = 'Rain';
const String _noGainMessage = '최고 랩이 모든 구간에서 가장 빠르다.';
const String _statTheoretical = 'Theoretical best';
const String _statBest = 'My best';
const String _statGain = 'Possible gain';
const String _statLaps = 'Laps used';
const String _conditionSeparator = ' · ';

const double _statsSpacing = 40;
const double _statsRunSpacing = 16;
const double _blockGap = 16;
const double _segmentWidth = 88;
const double _gainWidth = 72;
const int _dateFlex = 2;
const int _batteryFlex = 3;
const int _msPerSecond = 1000;
const int _secondDigits = 3;

/// 이론상 최고 랩 카드: 조건(세션 종류 · 컴파운드) 고르기, 이론상 최고 · 내 최고 · 줄일 수 있는 시간 · 쓴 랩 수,
/// 배터리 한도로 뺀 시간 안내, 최고 랩과 다른 구간 표(구간 · 최고 랩 대비 시간 — 빨라지면 초록, 배터리를 아끼느라 느려지면 빨강 · 그 구간을 달린 랩 날짜 ·
/// 최고 랩 대비 배터리). 줄을 누르면 그 랩 상세로 간다.
class TheoreticalBestCard extends ConsumerStatefulWidget {
  const TheoreticalBestCard({super.key, required this.trackId, required this.trackName});

  final String trackId;

  /// 공식 코너 자료(트랙 이름 키)를 찾는 이름.
  final String trackName;

  @override
  ConsumerState<TheoreticalBestCard> createState() => _TheoreticalBestCardState();
}

class _TheoreticalBestCardState extends ConsumerState<TheoreticalBestCard> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(theoreticalBestProvider(widget.trackId));
    final corners = ref.watch(trackCornersProvider).valueOrNull?[widget.trackName];
    final muted = context.palette.textMuted;
    return SectionCard(
      key: const ValueKey('track-theoretical-best'),
      title: _title,
      child: state.when(
        loading: () => const PageLoadingBar(),
        error: (e, _) => ErrorRetry(
          error: e,
          fallbackMessage: _errorMessage,
          onRetry: () => ref.invalidate(theoreticalBestProvider(widget.trackId)),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return Text(_emptyMessage, style: TextStyle(color: muted));
          }
          final index = _selected.clamp(0, groups.length - 1);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (groups.length > 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<int>(
                      key: const ValueKey('theoretical-condition'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: [
                        for (var i = 0; i < groups.length; i++) ButtonSegment(value: i, label: Text(_conditionOf(groups[i]))),
                      ],
                      selected: {index},
                      onSelectionChanged: (s) => setState(() => _selected = s.first),
                    ),
                  ),
                )
              else
                Text(_conditionOf(groups.single), style: TextStyle(color: muted)),
              const SizedBox(height: _blockGap),
              _GroupView(group: groups[index], corners: corners),
            ],
          );
        },
      ),
    );
  }
}

/// `Time Trial · Soft`, 비 오는 조건은 `Qualifying · Soft · Rain`(컴파운드를 모르면 빼고).
String _conditionOf(TheoreticalBestGroup group) => [
      sessionTypeLabel(group.sessionType),
      ?visualCompoundName(group.visualTyreCompound),
      if (group.isWet) _rainLabel,
    ].join(_conditionSeparator);

String _seconds(int ms) => (ms / _msPerSecond).toStringAsFixed(_secondDigits);

class _GroupView extends StatelessWidget {
  const _GroupView({required this.group, required this.corners});

  final TheoreticalBestGroup group;
  final List<OfficialCorner>? corners;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final labels = theoreticalSegmentLabels(group, corners);
    final changes = group.changes;
    final stats = <Widget>[
      Stat(key: const ValueKey('theoretical-stat-theoretical'), label: _statTheoretical, value: formatLapTime(group.theoreticalMs)),
      Stat(
        key: const ValueKey('theoretical-stat-best'),
        label: _statBest,
        value: formatLapTime(group.bestLapMs),
        onTap: () => context.go('/laps/${Uri.encodeComponent(group.bestLapId)}'),
      ),
      Stat(key: const ValueKey('theoretical-stat-gain'), label: _statGain, value: formatDeltaMs(group.gainMs)),
      Stat(key: const ValueKey('theoretical-stat-laps'), label: _statLaps, value: '${group.lapCount}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: _statsSpacing, runSpacing: _statsRunSpacing, children: stats),
        if (group.hasBattery && group.batteryLimitMs > 0) ...[
          const SizedBox(height: _blockGap),
          Text(
            '배터리를 따지지 않고 구간 최고 기록만 이으면 ${formatLapTime(group.unlimitedMs)}이다. '
            '${_seconds(group.batteryLimitMs)}초는 한 랩에 쓸 수 있는 배터리를 넘는 조합이라 뺐다.',
            key: const ValueKey('theoretical-battery-note'),
            style: TextStyle(color: palette.textMuted),
          ),
        ],
        const SizedBox(height: _blockGap),
        if (changes.isEmpty)
          Text(_noGainMessage, style: TextStyle(color: palette.textMuted))
        else
          CompactTable<TheoreticalSegment>(
            framed: false,
            rows: changes,
            rowKey: (s) => ValueKey('theoretical-segment-${s.index}'),
            onRowTap: (s) => context.go('/laps/${Uri.encodeComponent(s.lapId)}'),
            columns: [
              CompactColumn(label: 'Segment', width: _segmentWidth, cell: (s) => Text(labels[s.index])),
              CompactColumn(
                label: 'vs best',
                width: _gainWidth,
                cell: (s) => Text(
                  formatDeltaMs(s.gainMs),
                  style: kTabularStyle.copyWith(color: s.gainMs < 0 ? palette.success : palette.danger, fontWeight: FontWeight.w600),
                ),
              ),
              CompactColumn(
                label: 'Lap',
                flex: _dateFlex,
                cell: (s) => Text(
                  formatLapDate(s.lapSetAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
              if (group.hasBattery)
                CompactColumn(
                  label: 'Battery vs best',
                  flex: _batteryFlex,
                  compactHidden: true,
                  cell: (s) => Text(theoreticalBatteryDelta(s) ?? kLapNoValueText, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
      ],
    );
  }
}
