import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/track_picker.dart';
import '../application/ranking_providers.dart';
import '../domain/ranking_models.dart';
import 'track_choices.dart';

const double _rankBadgeSize = 32;

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
        _RankingSection(query: query),
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
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < snapshot.entries.length; i++) ...[
                  if (i > 0) const Divider(),
                  _RankingRow(entry: snapshot.entries[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.entry});

  final RankingEntry entry;

  @override
  Widget build(BuildContext context) {
    final isLeader = entry.rank == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: _rankBadgeSize,
            height: _rankBadgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLeader ? AppColors.accent : context.palette.border,
            ),
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isLeader ? AppColors.onAccent : context.palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(entry.displayName, overflow: TextOverflow.ellipsis)),
          Text(
            formatLapTime(entry.bestLapTimeMs),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
