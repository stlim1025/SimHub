import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/team_name_cell.dart';
import '../../profile/application/selected_game_provider.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../application/setups_providers.dart';
import '../domain/setup_models.dart';
import '../domain/setups_display.dart';
import 'page_heading.dart';
import 'setups_page.dart';

const String _setupsLabel = 'Setups';
const String _errorMessage = '셋업을 불러오지 못했다.';
const String _emptyMessage = '아직 가져온 셋업이 없다.';
const String _emptyActionLabel = '트랙 목록으로';
const String _notFoundMessage = '찾을 수 없는 트랙이다.';
const String _fetchedPrefix = 'F1Laps에서 가져온 상위 셋업이다. 갱신';
const int _httpNotFound = 404;
const double _headingGap = 20;
const double _toggleGap = 16;
const double _noteGap = 8;
const double _rankWidth = 40;
const double _lapTimeWidth = 100;
const int _teamFlex = 3;
const int _sessionFlex = 2;

final DateFormat _fetchedFormat = DateFormat('yyyy-MM-dd HH:mm');

/// 한 트랙의 상위 셋업(`/setups/:trackId`, F1Laps `F1 25 Australia Setups` 모양):
/// 이동 경로 + 제목 + Dry | Wet + `# | TEAM | SESSION | LAP TIME` 표(작성자 닉네임은 개인정보라 싣지 않는다). 줄을 누르면 셋업 상세로 간다.
class SetupTrackPage extends ConsumerWidget {
  const SetupTrackPage({super.key, required this.trackId, this.condition});

  final String trackId;

  /// 주소의 `condition` 쿼리(`wet`이면 Wet, 나머지는 Dry).
  final String? condition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameCode = ref.watch(selectedGameProvider);
    final selected = normalizeSetupCondition(condition);
    final query = (trackId: trackId, condition: selected);
    final list = ref.watch(setupListProvider(query));
    final trackName = list.valueOrNull?.track.name;
    final gameTitle = gameTitleOf(gameCode);
    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeading(
          crumbs: [
            (label: gameYearLabelOf(gameCode), path: null),
            (label: _setupsLabel, path: setupsLocation(condition: selected)),
            if (trackName != null) (label: trackName, path: null),
          ],
          title: trackName == null ? '$gameTitle $_setupsLabel' : '$gameTitle $trackName $_setupsLabel',
          countryCode: list.valueOrNull?.track.countryCode,
          showFlag: trackName != null,
        ),
        const SizedBox(height: _headingGap),
        Align(
          alignment: Alignment.centerLeft,
          child: ButtonGroup<String>(
            options: kSetupConditionOptions,
            selected: selected,
            segmentKeyOf: setupConditionKey,
            onSelected: (value) => context.go(setupTrackLocation(trackId, condition: value)),
          ),
        ),
        const SizedBox(height: _toggleGap),
        list.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => e is ApiException && e.statusCode == _httpNotFound
              ? NotFoundState(message: _notFoundMessage, backLabel: _setupsLabel, backPath: setupsLocation())
              : ErrorRetry(
                  error: e,
                  fallbackMessage: _errorMessage,
                  onRetry: () => ref.invalidate(setupListProvider(query)),
                ),
          data: (data) => _SetupListBody(list: data, trackId: trackId),
        ),
      ],
    );
  }
}

class _SetupListBody extends StatelessWidget {
  const _SetupListBody({required this.list, required this.trackId});

  final SetupList list;
  final String trackId;

  @override
  Widget build(BuildContext context) {
    if (list.items.isEmpty) {
      return EmptyStateCard(
        message: _emptyMessage,
        actionLabel: _emptyActionLabel,
        actionPath: setupsLocation(condition: list.condition),
      );
    }
    final fetchedAt = list.fetchedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompactTable<SetupListItem>(
          rows: list.items,
          rowKey: (item) => ValueKey('setup-row-${item.id}'),
          onRowTap: (item) => context.go(setupDetailLocation(trackId, item.id)),
          columns: [
            CompactColumn(label: '#', width: _rankWidth, cell: (item) => Text('${item.rank}', style: kTabularStyle)),
            CompactColumn(label: 'Team', flex: _teamFlex, cell: (item) => TeamNameCell(teamName: item.teamName)),
            CompactColumn(
              label: 'Session',
              flex: _sessionFlex,
              compactHidden: true,
              cell: (item) => Text(setupSessionLabel(item.sessionType), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            CompactColumn(
              label: 'Lap Time',
              width: _lapTimeWidth,
              cell: (item) => Text(formatLapTime(item.lapTimeMs), style: kTabularStyle),
            ),
          ],
        ),
        if (fetchedAt != null) ...[
          const SizedBox(height: _noteGap),
          Text(
            '$_fetchedPrefix ${_fetchedFormat.format(fetchedAt.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ],
    );
  }
}
