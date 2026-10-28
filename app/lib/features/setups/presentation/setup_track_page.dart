import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
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
const int _httpNotFound = 404;
const double _headingGap = 20;
const double _toggleGap = 16;
const double _rankWidth = 40;
const double _lapTimeWidth = 100;
const int _teamFlex = 3;
const int _sessionFlex = 2;


/// 한 트랙의 상위 셋업(`/setups/:trackId`, F1Laps `F1 25 Australia Setups` 모양):
/// 이동 경로 + 제목 + Dry | Wet · Time Trial | Race | Qualifying(Wet은 타임 트라이얼 없음) + `# | TEAM | SESSION | LAP TIME` 표
/// (작성자 닉네임은 개인정보라 싣지 않는다). 조건 × 세션 종류마다 출처 순위표가 따로다. 줄을 누르면 셋업 상세로 간다.
class SetupTrackPage extends ConsumerWidget {
  const SetupTrackPage({super.key, required this.trackId, this.condition, this.session});

  final String trackId;

  /// 주소의 `condition` 쿼리(`wet`이면 Wet, 나머지는 Dry).
  final String? condition;

  /// 주소의 `session` 쿼리(`timetrial`·`race`·`qualifying`, 없으면 조건의 기본 — Dry는 타임 트라이얼, Wet은 레이스).
  final String? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameCode = ref.watch(selectedGameProvider);
    final selected = normalizeSetupCondition(condition);
    final selectedSession = normalizeSetupSession(session, selected);
    final query = (trackId: trackId, condition: selected, session: selectedSession);
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
        Wrap(
          spacing: _toggleGap,
          runSpacing: _toggleGap / 2,
          children: [
            ButtonGroup<String>(
              options: kSetupConditionOptions,
              selected: selected,
              segmentKeyOf: setupConditionKey,
              // 조건을 바꾸면 그 조건에도 있는 세션 종류는 그대로 둔다(Wet으로 가면 타임 트라이얼은 레이스로).
              onSelected: (value) => context.go(setupTrackLocation(
                trackId,
                condition: value,
                session: normalizeSetupSession(selectedSession, value),
              )),
            ),
            ButtonGroup<String>(
              options: [for (final s in setupSessionsFor(selected)) (value: s, label: kSetupSessionLabels[s]!)],
              selected: selectedSession,
              segmentKeyOf: (s) => ValueKey('setup-session-$s'),
              onSelected: (value) => context.go(setupTrackLocation(trackId, condition: selected, session: value)),
            ),
          ],
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
      ],
    );
  }
}
