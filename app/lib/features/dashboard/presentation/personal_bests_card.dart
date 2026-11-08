import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/track_flag.dart';
import '../../laps/application/laps_providers.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/domain/lap_models.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../domain/dashboard_home.dart';

const String _title = 'Personal Bests';
const String _emptyText = '트랙별 최고 랩이 아직 없어요. 유효한 랩을 달리면 여기에 표시돼요.';
const String _loadFailedText = '트랙별 최고 랩을 불러오지 못했어요.';
const String _lapCountSuffix = '랩';

const double _rowHeight = 40;
const double _rowPaddingX = 24;
const double _flagGap = 10;
const double _lapCountGap = 16;
const double _bottomPadding = 8;

/// 홈 Personal Bests 카드: 최근에 달린 트랙부터 트랙별 내 최고 유효 랩(국기 · 트랙 · 랩 수 · 최고 랩).
/// 줄을 누르면 그 트랙의 랩 표(`/laps/tracks/:id`).
class PersonalBestsCard extends ConsumerWidget {
  const PersonalBestsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(myTracksProvider);
    return SessionCard(
      key: const ValueKey('dashboard-personal-bests'),
      title: _title,
      padded: !tracks.hasValue || recentPersonalBests(tracks.requireValue).isEmpty,
      child: tracks.when(
        loading: () => const PageLoadingBar(),
        error: (e, _) => ErrorRetry(
          error: e,
          fallbackMessage: _loadFailedText,
          onRetry: () => ref.invalidate(myTracksProvider),
        ),
        data: (all) {
          final bests = recentPersonalBests(all);
          if (bests.isEmpty) {
            return const SessionEmptyText(_emptyText);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: _bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < bests.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _BestRow(track: bests[i]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BestRow extends StatelessWidget {
  const _BestRow({required this.track});

  final MyTrack track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final best = track.bestValidLapTimeMs;
    return InkWell(
      key: ValueKey('dashboard-pb-${track.trackId}'),
      onTap: () => context.go(trackLapsLocation(track.trackId)),
      hoverColor: AppColors.rowHover,
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: _rowPaddingX),
        child: Row(
          children: [
            TrackFlag(countryCode: track.countryCode),
            const SizedBox(width: _flagGap),
            Expanded(
              child: Text(
                track.trackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${track.lapCount}$_lapCountSuffix',
              style: theme.textTheme.bodySmall?.merge(kTabularStyle).copyWith(color: palette.textMuted),
            ),
            const SizedBox(width: _lapCountGap),
            Text(
              best == null ? kLapNoValueText : formatLapTime(best),
              style: kTabularStyle.copyWith(fontWeight: FontWeight.w700, color: AppColors.fastestLap),
            ),
          ],
        ),
      ),
    );
  }
}
