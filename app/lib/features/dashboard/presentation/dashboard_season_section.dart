import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/hex_color.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/select_box.dart';
import '../../../core/widgets/team_color_bar.dart';
import '../../../core/widgets/track_flag.dart';
import '../../seasons/application/seasons_providers.dart';
import '../../seasons/domain/season_display.dart';
import '../../seasons/domain/season_models.dart';
import '../../sessions/domain/session_display.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../application/dashboard_providers.dart';
import '../domain/dashboard_season.dart';

const String _activeTitle = '진행 중인 시즌';
const String _latestTitle = '최근 시즌';
const String _viewSeasonLabel = 'View season';
const String _recentResultsTitle = '최근 결과';
const String _standingsTitle = '드라이버 순위';
const String _nextRoundLabel = '다음 라운드';
const String _loadFailedText = '시즌을 불러오지 못했어요.';
const String _noResultsText = '아직 달린 라운드가 없어요.';
const String _noStandingsText = '아직 순위가 없어요.';
const String _subtitleSeparator = ' · ';

const String _positionLabel = '순위';
const String _pointsLabel = '포인트';
const String _leaderGapLabel = '선두와 차이';
const String _secondGapLabel = '2위와 차이';
const String _winsLabel = '우승';
const String _podiumsLabel = '포디움';
const String _roundsLabel = '라운드';

// -- 크기 ---------------------------------------------------------------------

const double _sectionGap = 8;
const double _cardGap = 16;
const double _titleBarGap = 12;

/// 시즌 선택 상자 최대 폭(좁으면 제목 옆 남는 폭까지 줄어든다).
const double _seasonPickerMaxWidth = 280;
const double _statSpacing = 40;
const double _statRunSpacing = 16;
const double _statLabelGap = 4;
const double _nextRoundGap = 8;
const double _cardPadding = 24;

/// 최근 결과·순위 카드를 나란히 놓는 최소 폭(이보다 좁으면 위아래로).
const double _sideBySideMinWidth = 760;

/// 표 한 줄이 차지하는 높이(줄 + 위 구분선). 나란히 놓은 두 카드의 높이를 맞출 때 짧은 쪽 아래에 이만큼씩 비운다.
const double _tableRowExtent = kCompactRowHeight + 1;

/// 최근 결과 카드가 순위 카드보다 넓게(비율).
const int _resultsFlex = 3;
const int _standingsFlex = 2;

/// 최근 결과 표가 이보다 좁으면 라운드 열을 숨겨 그랑프리 이름 칸을 넓힌다.
const double _resultsCompactWidth = 480;

/// 표 열 폭.
const double _roundColumnWidth = 44;
const double _positionColumnWidth = 56;
const double _pointsColumnWidth = 52;
const double _standingPositionWidth = 44;

/// 드라이버 순위의 포인트 막대(선두 대비 비율): 두께, 표가 이보다 좁으면 숨긴다.
const double _pointsBarHeight = 8;
const double _pointsBarMinTableWidth = 360;

/// 대시보드 시즌 영역: 진행 중인 시즌(없으면 가장 최근 시즌)의 순위·포인트 요약 + 최근 결과 + 드라이버 순위 미리보기.
/// 진행 중인 시즌이 여럿이면 제목 옆 선택 상자로 보여 줄 시즌을 고른다(이 기기에 기억).
/// 시즌이 하나도 없으면 아무것도 그리지 않는다.
class DashboardSeasonSection extends ConsumerWidget {
  const DashboardSeasonSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(dashboardSeasonProvider);
    final choices = activeSeasons(ref.watch(allSeasonsProvider).valueOrNull ?? const []);
    // 다른 시즌을 고르면 새 시즌을 읽는 동안 지금 시즌을 그대로 둔다.
    return season.when(
      skipLoadingOnReload: true,
      loading: () => const PageLoadingBar(),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: _loadFailedText,
        onRetry: () => ref.invalidate(dashboardSeasonProvider),
      ),
      data: (detail) => detail == null
          ? const SizedBox.shrink()
          : _SeasonOverview(
              detail: detail,
              choices: choices,
              onChoose: (seasonId) => ref.read(dashboardSeasonChoiceProvider.notifier).select(seasonId),
            ),
    );
  }
}

class _SeasonOverview extends StatelessWidget {
  const _SeasonOverview({required this.detail, required this.choices, required this.onChoose});

  final SeasonDetail detail;

  /// 고를 수 있는 진행 중인 시즌들. 둘 이상일 때만 선택 상자를 보인다.
  final List<SeasonSummary> choices;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final season = detail.season;
    final theme = Theme.of(context);
    final rounds = recentCalendarRounds(detail.calendar);
    final drivers = standingsPreview(detail.standings.drivers);
    // 나란히 놓을 때 두 표의 줄 수를 맞춰 카드 높이를 같게 한다(한쪽이 비어 있으면 그대로).
    final rows = rounds.isEmpty || drivers.isEmpty ? null : math.max(rounds.length, drivers.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(season.isCompleted ? _latestTitle : _activeTitle, style: theme.textTheme.titleMedium),
                  if (choices.length > 1) ...[
                    const SizedBox(width: _titleBarGap),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _seasonPickerMaxWidth),
                        child: SelectBox<String>(
                          key: const ValueKey('dashboard-season-picker'),
                          options: [for (final s in choices) (value: s.seasonId, label: seasonDisplayTitle(s))],
                          selected: season.seasonId,
                          onSelected: onChoose,
                          optionKeyOf: (id) => ValueKey('dashboard-season-option-$id'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('dashboard-season-link'),
              onPressed: () => context.go(seasonLocation(season.seasonId)),
              child: const Text(_viewSeasonLabel),
            ),
          ],
        ),
        const SizedBox(height: _sectionGap),
        _SeasonSummaryCard(detail: detail),
        const SizedBox(height: _cardGap),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= _sideBySideMinWidth
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: _resultsFlex,
                      child: _RecentResultsCard(rounds: rounds, fillerRows: rows == null ? 0 : rows - rounds.length),
                    ),
                    const SizedBox(width: _cardGap),
                    Expanded(
                      flex: _standingsFlex,
                      child: _StandingsCard(drivers: drivers, fillerRows: rows == null ? 0 : rows - drivers.length),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RecentResultsCard(rounds: rounds),
                    const SizedBox(height: _cardGap),
                    _StandingsCard(drivers: drivers),
                  ],
                ),
        ),
      ],
    );
  }
}

/// [table] 아래에 [rows]줄만큼 빈 공간을 둔다.
Widget _withFiller(int rows, Widget table) => rows <= 0
    ? table
    : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [table, SizedBox(height: rows * _tableRowExtent)],
      );

// -- 요약 카드 ------------------------------------------------------------------

/// 시즌 이름 + 팀·드라이버, 순위·포인트·선두와 차이·우승·포디움·라운드, 다음 라운드.
class _SeasonSummaryCard extends StatelessWidget {
  const _SeasonSummaryCard({required this.detail});

  final SeasonDetail detail;

  @override
  Widget build(BuildContext context) {
    final season = detail.season;
    final palette = context.palette;
    final theme = Theme.of(context);
    final me = myStanding(detail.standings.drivers);
    final gap = leaderGap(detail.standings.drivers);
    final progress = roundProgress(detail);
    final next = nextCalendarRound(detail.calendar);
    final subtitle = [season.myTeamName, season.myDriverName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(_subtitleSeparator);
    final leading = me?.position == 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (me != null) ...[TeamColorBar(colorHex: me.teamColor), const SizedBox(width: _titleBarGap)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(seasonDisplayTitle(season), style: cardTitleStyle(context)),
                      if (subtitle.isNotEmpty)
                        Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: _cardPadding),
            Wrap(
              spacing: _statSpacing,
              runSpacing: _statRunSpacing,
              children: [
                _Stat(
                  key: const ValueKey('dashboard-stat-position'),
                  label: _positionLabel,
                  value: season.myPosition == null ? kNoValueText : 'P${season.myPosition}',
                  color: palette.podiumFor(season.myPosition),
                ),
                _Stat(
                  key: const ValueKey('dashboard-stat-points'),
                  label: _pointsLabel,
                  value: '${season.myPoints ?? 0}',
                ),
                if (gap != null)
                  _Stat(
                    key: const ValueKey('dashboard-stat-gap'),
                    label: leading ? _secondGapLabel : _leaderGapLabel,
                    value: gap.gap > 0 ? '+${gap.gap}' : '${gap.gap}',
                    caption: gap.rival.name,
                  ),
                if (me != null) ...[
                  _Stat(key: const ValueKey('dashboard-stat-wins'), label: _winsLabel, value: '${me.wins}'),
                  _Stat(key: const ValueKey('dashboard-stat-podiums'), label: _podiumsLabel, value: '${me.podiums}'),
                ],
                _Stat(
                  key: const ValueKey('dashboard-stat-rounds'),
                  label: _roundsLabel,
                  value: progress.total == null ? '${progress.driven}' : '${progress.driven} / ${progress.total}',
                ),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: _cardPadding),
              const Divider(height: 1),
              const SizedBox(height: _statRunSpacing),
              Row(
                key: const ValueKey('dashboard-next-round'),
                children: [
                  Text(_nextRoundLabel, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
                  const SizedBox(width: _titleBarGap),
                  TrackFlag(countryCode: next.countryCode),
                  const SizedBox(width: _nextRoundGap),
                  Flexible(
                    child: Text(
                      next.trackName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('${_subtitleSeparator}R${next.round}', style: TextStyle(color: palette.textMuted)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 흐린 라벨 + 큰 숫자(+ 아래 흐린 설명).
class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value, this.caption, this.color});

  final String label;
  final String value;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted);
    final caption = this.caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: muted),
        const SizedBox(height: _statLabelGap),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.merge(kTabularStyle).copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        if (caption != null) Text(caption, style: muted),
      ],
    );
  }
}

// -- 최근 결과 -------------------------------------------------------------------

/// 최근 달린 라운드: 라운드 · 그랑프리 · 예선 · 레이스 · 포인트(좁으면 라운드 열은 숨긴다). 줄을 누르면 그 주말 본 레이스(없으면 첫 세션).
class _RecentResultsCard extends StatelessWidget {
  const _RecentResultsCard({required this.rounds, this.fillerRows = 0});

  final List<SeasonCalendarRound> rounds;

  /// 표 아래에 비워 둘 줄 수(옆 카드와 높이 맞춤).
  final int fillerRows;

  @override
  Widget build(BuildContext context) {
    return SessionCard(
      title: _recentResultsTitle,
      padded: rounds.isEmpty,
      child: rounds.isEmpty
          ? const SessionEmptyText(_noResultsText)
          : _withFiller(fillerRows, CompactTable<SeasonCalendarRound>(
              framed: false,
              compactWidth: _resultsCompactWidth,
              rows: rounds,
              rowKey: (r) => ValueKey('dashboard-round-${r.round}'),
              onRowTap: (r) {
                final target = calendarRoundTarget(r);
                if (target != null) {
                  context.go(sessionLocation(target));
                }
              },
              columns: [
                CompactColumn(
                  label: 'Rd',
                  width: _roundColumnWidth,
                  compactHidden: true,
                  cell: (r) => Text('R${r.round}', style: kTabularStyle.copyWith(color: context.palette.textMuted)),
                ),
                CompactColumn(label: 'Grand Prix', cell: (r) => _GrandPrixName(round: r)),
                CompactColumn(
                  label: 'Quali',
                  width: _positionColumnWidth,
                  cell: (r) => _Position(position: r.qualiPosition),
                ),
                CompactColumn(
                  label: 'Race',
                  width: _positionColumnWidth,
                  cell: (r) => _Position(position: r.racePosition, emphasized: true),
                ),
                CompactColumn(
                  label: 'Pts',
                  width: _pointsColumnWidth,
                  alignment: Alignment.centerRight,
                  cell: (r) => Text(r.points == null ? '' : '${r.points}', style: kTabularStyle),
                ),
              ],
            )),
    );
  }
}

class _GrandPrixName extends StatelessWidget {
  const _GrandPrixName({required this.round});

  final SeasonCalendarRound round;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TrackFlag(countryCode: round.countryCode),
        const SizedBox(width: _nextRoundGap),
        Expanded(
          child: Text(
            round.trackName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.palette.link, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// `P3` 배지. 순위를 모르면 빈 칸.
class _Position extends StatelessWidget {
  const _Position({required this.position, this.emphasized = false});

  final int? position;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final value = knownPosition(position);
    return value == null
        ? const SizedBox.shrink()
        : FittedBox(fit: BoxFit.scaleDown, child: PositionBadge(text: 'P$value', emphasized: emphasized));
  }
}

// -- 드라이버 순위 ----------------------------------------------------------------

/// 위쪽 순위 + 내 앞뒤(내 줄은 강조). 1·2·3위 순위 숫자는 금·은·동, 이름 옆에 선두 대비 포인트 막대(팀 색, 내 막대는 강조색).
class _StandingsCard extends StatelessWidget {
  const _StandingsCard({required this.drivers, this.fillerRows = 0});

  final List<DriverStanding> drivers;

  /// 표 아래에 비워 둘 줄 수(옆 카드와 높이 맞춤).
  final int fillerRows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final leaderPoints = drivers.fold(0, (top, d) => math.max(top, d.points));
    return SessionCard(
      title: _standingsTitle,
      padded: drivers.isEmpty,
      child: drivers.isEmpty
          ? const SessionEmptyText(_noStandingsText)
          : _withFiller(fillerRows, CompactTable<DriverStanding>(
              framed: false,
              compactWidth: 0,
              rows: drivers,
              rowKey: (d) => ValueKey('dashboard-standing-${d.position}'),
              isHighlighted: (d) => d.isPlayer,
              columns: [
                CompactColumn(
                  label: 'Pos',
                  width: _standingPositionWidth,
                  cell: (d) => Text(
                    '${d.position}',
                    style: kTabularStyle.copyWith(
                      fontWeight: FontWeight.bold,
                      color: palette.podiumFor(d.position) ?? palette.textPrimary,
                    ),
                  ),
                ),
                CompactColumn(
                  label: 'Driver',
                  cell: (d) => DriverNameCell(name: d.name, teamColor: d.teamColor, isPlayer: d.isPlayer),
                ),
                CompactColumn(
                  label: '',
                  hideBelowWidth: _pointsBarMinTableWidth,
                  cell: (d) => _PointsBar(
                    key: ValueKey('dashboard-standing-bar-${d.position}'),
                    fraction: leaderPoints <= 0 ? 0 : d.points / leaderPoints,
                    color: d.isPlayer ? AppColors.accent : parseHexColor(d.teamColor, fallback: palette.textMuted),
                  ),
                ),
                CompactColumn(
                  label: 'Pts',
                  width: _pointsColumnWidth,
                  alignment: Alignment.centerRight,
                  cell: (d) => Text('${d.points}', style: kTabularStyle.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            )),
    );
  }
}

/// 선두 대비 포인트 막대: 테두리 색 바탕 위에 [fraction](0~1)만큼 [color]로 채운다.
class _PointsBar extends StatelessWidget {
  const _PointsBar({super.key, required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _pointsBarHeight,
      color: context.palette.border,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0, 1).toDouble(),
        heightFactor: 1,
        child: ColoredBox(color: color),
      ),
    );
  }
}
