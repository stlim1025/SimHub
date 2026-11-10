import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/list_board.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/track_picker.dart';
import '../../sessions/domain/session_display.dart' show formatGapMs, kNoValueText;
import '../../sessions/presentation/session_widgets.dart' show kTabularStyle;
import '../../tracks/presentation/track_rail.dart';
import '../../tracks/presentation/track_side_panel.dart';
import '../application/ranking_providers.dart';
import '../domain/ranking_models.dart';
import 'track_choices.dart';

const String _tracksTitle = 'Tracks';

/// 시상대에 올리는 순위 수, 시상대 칸 순서(가운데가 1위), 칸 사이·시상대와 표 사이 간격.
const int _podiumPlaces = 3;
const List<int> _podiumOrder = [2, 1, 3];
const double _podiumGap = 12;
const double _podiumTableGap = 16;

/// 시상대 카드: 안쪽 여백·줄 간격·글자 크기(순위 · 1위 랩타임 · 2·3위 랩타임).
const double _podiumCardPadding = 16;
const double _podiumLineGap = 6;
const double _podiumPlaceFontSize = 13;
const double _podiumLeaderTimeFontSize = 30;
const double _podiumTimeFontSize = 24;

/// 시상대 단: 순위별 높이(1위가 가장 높다)·바탕 투명도·윗선 굵기·숫자 크기.
const Map<int, double> _podiumStepHeights = {1: 84, 2: 60, 3: 44};

/// 시상대 칸이 이보다 좁으면(휴대폰) 기록한 날을 빼고 1위와의 차이만 둔다(순위표가 좁을 때 DATE 열을 숨기는 것과 같다).
const double _podiumDateMinWidth = 200;
const double _podiumStepAlpha = 0.16;
const double _podiumStepBorder = 3;
const double _podiumStepFontSize = 26;

/// 4위부터의 표: 열 폭·이름 칸 비율·순위 글자 크기.
const double _rankColumnWidth = 56;
const double _rankFontSize = 15;
const double _lapTimeColumnWidth = 120;
const double _gapColumnWidth = 110;
const double _dateColumnWidth = 120;
const int _driverFlex = 4;

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

/// 기간 선택지(서버 period 값 → 표시 라벨).
const _periodLabels = <String, String>{
  kRankingPeriodDaily: '일',
  kRankingPeriodMonthly: '월',
  kRankingPeriodYearly: '연',
};

const _periodNames = <String, String>{
  kRankingPeriodDaily: '일별',
  kRankingPeriodMonthly: '월별',
  kRankingPeriodYearly: '연별',
};

/// 트랙·기간별 TOP10(월별 기본, D-8a). 월별 보기는 RankingHub로 실시간 갱신된다.
/// 트랙은 주소의 `?trackId=`로 고르고, 없으면 첫 트랙을 보여준다.
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key, this.trackId});

  /// 주소의 `trackId` 쿼리. null이거나 알 수 없는 값이면 첫 트랙.
  final String? trackId;

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  String _period = kRankingPeriodMonthly;

  void _selectTrack(String trackId) {
    context.go('/leaderboard?trackId=${Uri.encodeQueryComponent(trackId)}');
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(tracksProvider);

    return ListView(
      padding: pagePadding(context),
      children: [
        Text(
          'Leaderboard',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        tracks.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '트랙을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(tracksProvider),
          ),
          data: _buildLoaded,
        ),
      ],
    );
  }

  Widget _buildLoaded(List<Track> tracks) {
    if (tracks.isEmpty) {
      return Text('등록된 트랙이 없어요.', style: TextStyle(color: context.palette.textMuted));
    }

    final selected = tracks.firstWhere(
      (t) => t.trackId == widget.trackId,
      orElse: () => tracks.first,
    );
    final query = RankingQuery(trackId: selected.trackId, period: _period);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 트랙 메뉴(D-43·D-47): 국기 + 이름 + ⇅, 캘린더 순서 목록. Laps와 같은 위젯이다.
            TrackPicker(
              tracks: trackChoicesOf(tracks),
              selected: trackChoiceOf(selected),
              onSelected: (choice) => _selectTrack(choice.id),
              textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            // 기간: Laps 정렬과 같은 웹식 테두리 버튼 묶음(Material 알약형 SegmentedButton 대신).
            ButtonGroup<String>(
              options: [for (final entry in _periodLabels.entries) (value: entry.key, label: entry.value)],
              selected: _period,
              onSelected: (period) => setState(() => _period = period),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // 넓은 화면: 왼쪽에 트랙 목록(캘린더 순서, 바로 옮겨 가기), 오른쪽에 트랙 정보·내 기록 카드 열.
        ListBoard(
          rail: TrackRail(
            title: _tracksTitle,
            selectedId: selected.trackId,
            onSelected: _selectTrack,
            items: [for (final t in tracks) (id: t.trackId, name: t.name, countryCode: t.countryCode, detail: null)],
          ),
          aside: TrackSidePanel(trackId: selected.trackId),
          main: _RankingSection(query: query),
        ),
      ],
    );
  }
}

class _RankingSection extends ConsumerWidget {
  const _RankingSection({required this.query});

  final RankingQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(rankingControllerProvider(query));

    return ranking.when(
      loading: () => const PageLoadingBar(),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: '랭킹을 불러오지 못했어요.',
        onRetry: () => ref.invalidate(rankingControllerProvider(query)),
      ),
      data: (snapshot) => _RankingList(snapshot: snapshot),
    );
  }
}

class _RankingList extends StatelessWidget {
  const _RankingList({required this.snapshot});

  final RankingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final periodName = _periodNames[snapshot.period] ?? snapshot.period;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '$periodName · ${snapshot.periodKey}',
              style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
            ),
            const Spacer(),
            Icon(Icons.circle, size: 10, color: context.palette.success),
            const SizedBox(width: 6),
            Text('실시간', style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted)),
          ],
        ),
        const SizedBox(height: 8),
        if (snapshot.entries.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '아직 기록이 없어요. 첫 랩의 주인공이 되어보세요!',
                style: TextStyle(color: context.palette.textMuted),
              ),
            ),
          )
        else ...[
          _Podium(entries: snapshot.entries.take(_podiumPlaces).toList()),
          if (snapshot.entries.length > _podiumPlaces) ...[
            const SizedBox(height: _podiumTableGap),
            _RankingTable(entries: snapshot.entries),
          ],
        ],
      ],
    );
  }
}

/// 1~3위 시상대: 2위 · 1위 · 3위 순으로 나란히, 아래 단(1위가 가장 높다)은 금·은·동 색. 단 위 카드에 순위·드라이버·랩타임·
/// 1위와 차이(1위는 없음)·기록한 날. 칸이 좁으면 기록한 날을 빼고, 그래도 넘치면 글자를 칸에 맞춰 줄인다.
class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  final List<RankingEntry> entries;

  @override
  Widget build(BuildContext context) {
    final byRank = {for (final e in entries) e.rank: e};
    final leaderMs = entries.first.bestLapTimeMs;
    return Row(
      key: const ValueKey('ranking-podium'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, rank) in _podiumOrder.indexed) ...[
          if (i > 0) const SizedBox(width: _podiumGap),
          Expanded(
            child: switch (byRank[rank]) {
              final entry? => _PodiumStep(entry: entry, leaderMs: leaderMs),
              null => const SizedBox.shrink(),
            },
          ),
        ],
      ],
    );
  }
}

/// 시상대 한 칸: 기록 카드 + 순위 색 단(순위가 높을수록 높다).
class _PodiumStep extends StatelessWidget {
  const _PodiumStep({required this.entry, required this.leaderMs});

  final RankingEntry entry;
  final int leaderMs;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rank = entry.rank;
    final color = palette.podiumFor(rank) ?? palette.textMuted;
    final theme = Theme.of(context);
    final muted = TextStyle(color: palette.textMuted);
    Widget fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child);
    return Column(
      key: ValueKey('ranking-podium-$rank'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(_podiumCardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'P$rank',
                  style: kTabularStyle.copyWith(color: color, fontWeight: FontWeight.w800, fontSize: _podiumPlaceFontSize),
                ),
                const SizedBox(height: _podiumLineGap),
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: _podiumLineGap),
                fit(Text(
                  formatLapTime(entry.bestLapTimeMs),
                  style: kTabularStyle.copyWith(
                    fontSize: rank == 1 ? _podiumLeaderTimeFontSize : _podiumTimeFontSize,
                    fontWeight: FontWeight.w800,
                  ),
                )),
                LayoutBuilder(builder: (context, constraints) {
                  final date = constraints.maxWidth >= _podiumDateMinWidth ? _dateFormat.format(entry.setAt.toLocal()) : null;
                  final gap = rank == 1 ? null : formatGapMs(entry.bestLapTimeMs - leaderMs);
                  final line = [?gap, ?date].join(' · ');
                  return line.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: _podiumLineGap),
                          child: fit(Text(line, style: kTabularStyle.merge(muted))),
                        );
                }),
              ],
            ),
          ),
        ),
        Container(
          height: _podiumStepHeights[rank] ?? _podiumStepHeights.values.last,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: _podiumStepAlpha),
            border: Border(top: BorderSide(color: color, width: _podiumStepBorder)),
          ),
          child: Text(
            '$rank',
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: _podiumStepFontSize),
          ),
        ),
      ],
    );
  }
}

/// 4위부터의 순위표(세션·랩 목록과 같은 촘촘한 표, [entries]는 1위부터 전체): # · DRIVER · LAP TIME · GAP(1위와 차이) ·
/// INT(바로 앞 순위와 차이) · DATE(기록한 날). 좁으면 GAP·INT·DATE를 숨긴다.
class _RankingTable extends StatelessWidget {
  const _RankingTable({required this.entries});

  final List<RankingEntry> entries;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.textMuted;
    final leaderMs = entries.first.bestLapTimeMs;
    final aheadMs = {for (var i = 1; i < entries.length; i++) entries[i].rank: entries[i - 1].bestLapTimeMs};
    return CompactTable<RankingEntry>(
      rows: entries.skip(_podiumPlaces).toList(),
      rowKey: (e) => ValueKey('ranking-row-${e.rank}'),
      columns: [
        CompactColumn(
          label: '#',
          width: _rankColumnWidth,
          cell: (e) => Text('${e.rank}', style: kTabularStyle.copyWith(fontWeight: FontWeight.w800, fontSize: _rankFontSize)),
        ),
        CompactColumn(
          label: 'Driver',
          flex: _driverFlex,
          cell: (e) => Text(e.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        CompactColumn(
          label: 'Lap Time',
          width: _lapTimeColumnWidth,
          cell: (e) => Text(formatLapTime(e.bestLapTimeMs), style: kTabularStyle.copyWith(fontWeight: FontWeight.bold)),
        ),
        CompactColumn(
          label: 'Gap',
          width: _gapColumnWidth,
          compactHidden: true,
          cell: (e) => Text(formatGapMs(e.bestLapTimeMs - leaderMs), style: kTabularStyle.copyWith(color: muted)),
        ),
        CompactColumn(
          label: 'Int',
          width: _gapColumnWidth,
          compactHidden: true,
          cell: (e) => Text(
            switch (aheadMs[e.rank]) {
              final ahead? => formatGapMs(e.bestLapTimeMs - ahead),
              null => kNoValueText,
            },
            style: kTabularStyle.copyWith(color: muted),
          ),
        ),
        CompactColumn(
          label: 'Date',
          width: _dateColumnWidth,
          compactHidden: true,
          cell: (e) => Text(_dateFormat.format(e.setAt.toLocal()), style: kTabularStyle.copyWith(color: muted)),
        ),
      ],
    );
  }
}
