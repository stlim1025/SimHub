import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../application/laps_providers.dart';
import '../domain/lap_models.dart';
import 'empty_laps_card.dart';

/// 최고 유효 랩이 없는 트랙에 보여주는 자리표시.
const String _noBestLapText = '-';

const double _statSpacing = 32;

/// 내 기록이 있는 트랙 목록(docs/11 §7.3). 트랙을 누르면 그 트랙의 랩 표로 이동한다.
class LapsPage extends ConsumerWidget {
  const LapsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(myTracksProvider);

    return ListView(
      padding: kPagePadding,
      children: [
        Text(
          'Laps',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        tracks.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '트랙 목록을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(myTracksProvider),
          ),
          data: (items) => items.isEmpty ? const EmptyLapsCard() : _TrackList(tracks: items),
        ),
      ],
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.tracks});

  final List<MyTrack> tracks;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < tracks.length; i++) ...[
            if (i > 0) const Divider(),
            _TrackRow(track: tracks[i]),
          ],
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track});

  static final _dateFormat = DateFormat('yyyy-MM-dd');

  final MyTrack track;

  @override
  Widget build(BuildContext context) {
    final bestLapMs = track.bestValidLapTimeMs;
    return InkWell(
      onTap: () => context.go('/laps/tracks/${track.trackId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    track.trackName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: _statSpacing,
              runSpacing: 8,
              children: [
                _Stat(
                  label: '최고 유효 랩',
                  value: bestLapMs == null ? _noBestLapText : formatLapTime(bestLapMs),
                ),
                _Stat(label: '랩 수', value: '${track.lapCount}'),
                _Stat(label: '마지막 주행', value: _dateFormat.format(track.lastSetAt.toLocal())),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
