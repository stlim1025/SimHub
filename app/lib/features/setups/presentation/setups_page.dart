import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../profile/application/selected_game_provider.dart';
import '../application/setups_providers.dart';
import '../domain/setup_models.dart';
import '../domain/setups_display.dart';
import 'page_heading.dart';
import 'track_grid.dart';

const String _setupsLabel = 'Setups';
const String _errorMessage = '트랙 목록을 불러오지 못했다.';
const String _emptyMessage = '아직 가져온 셋업이 없다.';
const double _headingGap = 20;
const double _toggleGap = 16;

/// Dry | Wet 선택지.
const List<ButtonGroupOption<String>> kSetupConditionOptions = [
  (value: kSetupConditionDry, label: kSetupConditionDry),
  (value: kSetupConditionWet, label: kSetupConditionWet),
];

/// Dry | Wet 버튼 묶음 칸 키(`setup-condition-Dry` 등).
Key setupConditionKey(String condition) => ValueKey('setup-condition-$condition');

/// 셋업 모음 목록(`/setups`, F1Laps `F1 25 Setups` 모양): 이동 경로 + 제목 + 안내 + Dry | Wet + 트랙 칸 격자.
/// 트랙은 계정 설정의 게임([selectedGameProvider])을 따른다. 조건은 주소의 `?condition=wet`으로 고른다.
class SetupsPage extends ConsumerWidget {
  const SetupsPage({super.key, this.condition});

  /// 주소의 `condition` 쿼리(`wet`이면 Wet, 나머지는 Dry).
  final String? condition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameCode = ref.watch(selectedGameProvider);
    final selected = normalizeSetupCondition(condition);
    final tracks = ref.watch(setupTracksProvider);
    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeading(
          crumbs: [(label: gameYearLabelOf(gameCode), path: null), (label: _setupsLabel, path: null)],
          title: '${gameTitleOf(gameCode)} $_setupsLabel',
        ),
        const SizedBox(height: _headingGap),
        Align(
          alignment: Alignment.centerLeft,
          child: ButtonGroup<String>(
            options: kSetupConditionOptions,
            selected: selected,
            segmentKeyOf: setupConditionKey,
            onSelected: (value) => context.go(setupsLocation(condition: value)),
          ),
        ),
        const SizedBox(height: _toggleGap),
        tracks.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: _errorMessage,
            onRetry: () => ref.invalidate(setupTracksProvider),
          ),
          data: (data) => data.isEmpty
              ? const EmptyStateCard(message: _emptyMessage)
              : TrackGrid(
                  tracks: data,
                  trailingOf: (track) => _countText(track.countOf(selected)),
                  onTap: (track) => context.go(setupTrackLocation(track.trackId, condition: selected)),
                ),
        ),
      ],
    );
  }

  static String? _countText(int count) => count <= 0 ? null : '$count';
}
