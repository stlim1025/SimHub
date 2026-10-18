import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/widgets/error_retry.dart';
import '../application/laps_providers.dart';
import 'empty_laps_card.dart';
import 'laps_track_picker.dart';
import 'track_laps_view.dart';

const double _titleGap = 16;

/// Laps(`/laps`, D-47·docs/15 §2.1): 마지막으로 달린 트랙(`GET /me/tracks` 첫 항목)의 표를 주소를 바꾸지 않고 바로 보인다.
/// 기록이 하나도 없으면 트랙 메뉴 + 빈 상태 카드.
class LapsPage extends ConsumerWidget {
  const LapsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(myTracksProvider);

    return tracks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: '트랙 목록을 불러오지 못했어요.',
        onRetry: () => ref.invalidate(myTracksProvider),
      ),
      data: (items) => items.isEmpty ? const _NoLaps() : TrackLapsView(trackId: items.first.trackId),
    );
  }
}

class _NoLaps extends StatelessWidget {
  const _NoLaps();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: pagePadding(context),
      children: const [
        Align(alignment: Alignment.centerLeft, child: LapsTrackPicker(trackId: null)),
        SizedBox(height: _titleGap),
        EmptyLapsCard(),
      ],
    );
  }
}
