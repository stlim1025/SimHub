import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/stat.dart';
import '../../../core/widgets/track_flag.dart';
import '../application/sessions_providers.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';

const String _recentTitle = '최근 레이스';
const String _tracksTitle = '트랙별 최고 순위';
const String _noRacesText = '아직 기록된 레이스가 없어요.';
const String _winsLabel = '우승';
const String _podiumsLabel = '포디움';
const String _averageLabel = '평균 순위';
const String _pointsLabel = '포인트';
const String _racesSuffix = '경기';

/// 포디움 순위(이 순위 이하면 막대를 강조색으로).
const int _podiumPosition = 3;

const double _cardGap = 20;
const double _statSpacing = 28;
const double _statRunSpacing = 16;
const double _barsTopGap = 20;
const double _barsHeight = 72;
const double _barGap = 3;
const double _barRadius = 2;

/// 가장 낮은 순위 막대도 이 비율만큼은 보이게(꼴찌가 빈칸으로 사라지지 않게).
const double _barMinFactor = 0.08;
const double _mutedBarAlpha = 0.45;
const int _averageDigits = 1;

/// 트랙별 줄 수 상한·줄 높이·국기 간격.
const int _trackRowsMax = 8;
const double _trackRowHeight = 40;
const double _flagGap = 10;
const double _badgeGap = 10;
const EdgeInsets _trackRowPadding = EdgeInsets.symmetric(horizontal: 24);

/// 세션 목록 보드 오른쪽 카드 열: 최근 레이스(레이스 목록 첫 페이지, 최대 [kSessionsPageSize]경기)의 우승·포디움·평균 순위·
/// 포인트와 경기마다 결과 막대(오래된 → 최근, 높을수록 앞 순위, 포디움은 강조색), 그 레이스들의 트랙별 최고 순위.
/// 레이스 목록을 아직 못 받았으면 아무것도 그리지 않는다.
class RecentRacesPanel extends ConsumerWidget {
  const RecentRacesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final races = ref.watch(sessionsProvider(const SessionsQuery(kSessionFilterRace, 1))).valueOrNull?.items;
    if (races == null) {
      return const SizedBox.shrink();
    }
    final finished = [for (final r in races) if (r.myPosition case final p? when p > 0) (race: r, position: p)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SessionCard(
          key: const ValueKey('recent-races'),
          title: _recentTitle,
          trailing: Text('${races.length}$_racesSuffix', style: TextStyle(color: context.palette.textMuted)),
          child: finished.isEmpty
              ? const SessionEmptyText(_noRacesText)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: _statSpacing,
                      runSpacing: _statRunSpacing,
                      children: [
                        Stat(label: _winsLabel, value: '${finished.where((f) => f.position == 1).length}'),
                        Stat(label: _podiumsLabel, value: '${finished.where((f) => f.position <= _podiumPosition).length}'),
                        Stat(
                          label: _averageLabel,
                          value:
                              'P${(finished.map((f) => f.position).reduce((a, b) => a + b) / finished.length).toStringAsFixed(_averageDigits)}',
                        ),
                        Stat(label: _pointsLabel, value: '${races.fold(0, (sum, r) => sum + (r.myPoints ?? 0))}'),
                      ],
                    ),
                    const SizedBox(height: _barsTopGap),
                    _FinishBars(results: finished.reversed.toList()),
                  ],
                ),
        ),
        if (finished.isNotEmpty) ...[
          const SizedBox(height: _cardGap),
          SessionCard(
            key: const ValueKey('recent-race-tracks'),
            title: _tracksTitle,
            padded: false,
            child: _TrackBests(results: finished),
          ),
        ],
      ],
    );
  }
}

/// 경기마다 결과 막대(왼쪽이 오래된 경기). 높이 = 앞 순위일수록 높게(참가 대수 기준), 포디움은 강조색. 막대에 올리면 트랙 · 순위.
class _FinishBars extends StatelessWidget {
  const _FinishBars({required this.results});

  final List<({SessionSummary race, int position})> results;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.textMuted.withValues(alpha: _mutedBarAlpha);
    return SizedBox(
      key: const ValueKey('recent-race-bars'),
      height: _barsHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, r) in results.indexed) ...[
            if (i > 0) const SizedBox(width: _barGap),
            Expanded(
              child: Tooltip(
                message: '${r.race.trackName} · P${r.position}',
                child: FractionallySizedBox(
                  heightFactor: _heightFactor(r.position, r.race.carCount),
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: r.position <= _podiumPosition ? AppColors.accent : muted,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(_barRadius)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static double _heightFactor(int position, int carCount) {
    final field = math.max(carCount, position);
    return math.max(_barMinFactor, (field - position + 1) / field);
  }
}

/// 트랙별 최고 순위(앞 순위 → 이름 순, 최대 [_trackRowsMax]줄): 국기 · 트랙 · P 배지(우승은 강조) · 경기 수.
class _TrackBests extends StatelessWidget {
  const _TrackBests({required this.results});

  final List<({SessionSummary race, int position})> results;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final byTrack = <String, ({String? countryCode, int best, int count})>{};
    for (final r in results) {
      final current = byTrack[r.race.trackName];
      byTrack[r.race.trackName] = (
        countryCode: r.race.countryCode,
        best: current == null ? r.position : math.min(current.best, r.position),
        count: (current?.count ?? 0) + 1,
      );
    }
    final rows = byTrack.entries.toList()
      ..sort((a, b) => a.value.best != b.value.best ? a.value.best.compareTo(b.value.best) : a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows.take(_trackRowsMax))
          Container(
            key: ValueKey('recent-race-track-${row.key}'),
            height: _trackRowHeight,
            padding: _trackRowPadding,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.border))),
            child: Row(
              children: [
                TrackFlag(countryCode: row.value.countryCode),
                const SizedBox(width: _flagGap),
                Expanded(child: Text(row.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                PositionBadge(text: 'P${row.value.best}', emphasized: row.value.best == 1),
                const SizedBox(width: _badgeGap),
                Text('${row.value.count}$_racesSuffix', style: kTabularStyle.copyWith(color: palette.textMuted)),
              ],
            ),
          ),
      ],
    );
  }
}
