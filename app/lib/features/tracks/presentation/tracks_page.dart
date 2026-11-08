import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../profile/application/selected_game_provider.dart';
import '../../setups/application/setups_providers.dart';
import '../../setups/domain/setup_models.dart';
import '../../setups/domain/setups_display.dart';
import '../../setups/presentation/page_heading.dart';
import '../../setups/presentation/setups_page.dart';
import '../../setups/presentation/track_grid.dart';

const String _tracksLabel = 'Tracks';
const String _errorMessage = '트랙 목록을 불러오지 못했다.';
const String _emptyMessage = '아직 등록된 트랙이 없다.';
const double _headingGap = 20;
const double _toggleGap = 16;
const String _setupCountPrefix = '셋업';

/// 트랙 칸 오른쪽 글자: 그 조건의 셋업 수(`셋업 3`, 없으면 비움).
String? _setupCountText(int count) => count <= 0 ? null : '$_setupCountPrefix $count';

/// 트랙 목록(`/tracks`, F1Laps `F1 26 Tracks` 모양): 이동 경로 + 제목 + 안내 + 트랙 칸 격자(캘린더 순서, 역방향·옛 레이아웃은 뒤).
/// 트랙은 계정 설정의 게임([selectedGameProvider])을 따르고, 목록은 Setups 화면과 같은 트랙 목록([setupTracksProvider])을 쓴다.
class TracksPage extends ConsumerWidget {
  const TracksPage({super.key, this.condition});

  /// 주소의 `condition` 쿼리(`wet`이면 Wet, 나머지는 Dry). 트랙 칸마다 그 조건의 셋업 수를 보인다(Setups 메뉴를 합쳤다).
  final String? condition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameCode = ref.watch(selectedGameProvider);
    final tracks = ref.watch(setupTracksProvider);
    final selected = normalizeSetupCondition(condition);
    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeading(
          crumbs: [(label: gameYearLabelOf(gameCode), path: null), (label: _tracksLabel, path: null)],
          title: '${gameTitleOf(gameCode)} $_tracksLabel',
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
                  trailingOf: (track) => _setupCountText(track.countOf(selected)),
                  onTap: (track) => context.go(trackOverviewLocation(track.trackId)),
                ),
        ),
      ],
    );
  }
}
