import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/layout_constants.dart';
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
import 'setup_detail_page.dart';
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

/// 콘텐츠 폭이 이 이상이면 셋업 목록 옆에 고른 셋업을 나란히 보인다. 목록 · 셋업 칸 비율과 사이 간격.
const double kSetupSplitWidth = 1100;
const int _listFlex = 2;
const int _detailFlex = 3;
const double _splitGap = 20;

/// 표 폭이 이보다 좁을 때만 SESSION 열을 숨긴다.
const double _tableCompactWidth = 460;


/// 한 트랙의 상위 셋업(`/setups/:trackId`, F1Laps `F1 25 Australia Setups` 모양):
/// 이동 경로 + 제목 + Dry | Wet · Time Trial | Race | Qualifying(Wet은 타임 트라이얼 없음) + `# | TEAM | SESSION | LAP TIME` 표
/// (작성자 닉네임은 개인정보라 싣지 않는다). 조건 × 세션 종류마다 출처 순위표가 따로다. 줄을 누르면 셋업 상세로 간다.
class SetupTrackPage extends ConsumerWidget {
  const SetupTrackPage({super.key, required this.trackId, this.condition, this.session, this.embedded = false});

  final String trackId;

  /// 트랙 화면의 셋업 탭 안에 들어가는지 — 참이면 머리(이동 경로·제목)와 바깥 스크롤 없이 토글과 표만 그린다.
  final bool embedded;

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
    final body = [
        Wrap(
          spacing: _toggleGap,
          runSpacing: _toggleGap / 2,
          children: [
            ButtonGroup<String>(
              options: kSetupConditionOptions,
              selected: selected,
              segmentKeyOf: setupConditionKey,
              // 조건을 바꾸면 그 조건의 기본 세션 종류로(Dry는 타임 트라이얼, Wet은 레이스).
              onSelected: (value) => context.go(setupTrackLocation(trackId, condition: value)),
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
    ];
    if (embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body);
    }
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
        ...body,
      ],
    );
  }
}

/// 셋업 목록. 넓으면([kSetupSplitWidth] 이상) 왼쪽 목록 + 오른쪽 고른 셋업(기본 = 1위)을 나란히 두고, 줄을 누르면 오른쪽만 바뀐다.
/// 좁으면 목록만 두고 줄을 누르면 셋업 상세 화면으로 간다.
class _SetupListBody extends StatefulWidget {
  const _SetupListBody({required this.list, required this.trackId});

  final SetupList list;
  final String trackId;

  @override
  State<_SetupListBody> createState() => _SetupListBodyState();
}

class _SetupListBodyState extends State<_SetupListBody> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    if (list.items.isEmpty) {
      return EmptyStateCard(
        message: _emptyMessage,
        actionLabel: _emptyActionLabel,
        actionPath: setupsLocation(condition: list.condition),
      );
    }
    // 조건·세션을 바꿔 목록이 바뀌면, 고른 셋업이 새 목록에 없을 때 1위로 돌아간다.
    final selectedId = list.items.any((item) => item.id == _selectedId) ? _selectedId! : list.items.first.id;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kSetupSplitWidth) {
          // 열이 넷뿐이라 넓게 늘리면 칸 사이가 비므로 읽기 좋은 폭까지만 쓴다(위 토글과 같이 왼쪽 정렬).
          return Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kReadableContentMaxWidth),
              child: _table(onRowTap: (item) => context.go(setupDetailLocation(widget.trackId, item.id))),
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: _listFlex,
              child: _table(
                selectedId: selectedId,
                onRowTap: (item) => setState(() => _selectedId = item.id),
              ),
            ),
            const SizedBox(width: _splitGap),
            Expanded(
              flex: _detailFlex,
              child: KeyedSubtree(
                key: const ValueKey('setup-detail-panel'),
                child: SetupDetailView(trackId: widget.trackId, setupId: selectedId),
              ),
            ),
          ],
        );
      },
    );
  }

  /// `# | TEAM | SESSION | LAP TIME` 표. [selectedId]가 있으면 그 줄을 강조한다.
  Widget _table({required ValueChanged<SetupListItem> onRowTap, String? selectedId}) => CompactTable<SetupListItem>(
          rows: widget.list.items,
          rowKey: (item) => ValueKey('setup-row-${item.id}'),
          // 열이 넷뿐이라 목록 칸(넓은 화면의 2/5)에서도 SESSION 열을 보인다.
          compactWidth: _tableCompactWidth,
          onRowTap: onRowTap,
          isHighlighted: selectedId == null ? null : (item) => item.id == selectedId,
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
        );
}
