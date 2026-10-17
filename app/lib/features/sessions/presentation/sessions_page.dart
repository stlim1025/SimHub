import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/pagination_bar.dart';
import '../application/sessions_providers.dart';
import '../domain/session_display.dart';
// 같은 이름의 모델 `SessionsPage`(목록 한 페이지)와 이 파일의 화면 위젯이 겹치므로 모델은 가져오지 않고 필요한 것만 쓴다.
import '../domain/session_models.dart' show SessionSummary;

const String _sessionsPath = '/sessions';
const String _telemetryAppPath = '/telemetry-app';

const String _guideText = '결과 화면까지 마친 세션이 여기에 기록됩니다.';
const String _noMatchText = '이 조건에 맞는 세션이 없습니다.';

const double _rowHeight = 44;
const double _filterSpacing = 8;
const double _gridGap = 8;

/// 필터 값 → 칩 글자(`kSessionFilters`와 같은 순서로 그린다).
const Map<String, String> _filterLabels = {
  kSessionFilterAll: 'All',
  kSessionFilterRace: 'Race',
  kSessionFilterQualifying: 'Qualifying',
  kSessionFilterPractice: 'Practice',
};

const _timeStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// 내 세션 목록(docs/12 §8.3). 필터는 주소의 `?type=`(모르는 값은 all), 페이지 번호는 화면 상태.
class SessionsPage extends ConsumerStatefulWidget {
  const SessionsPage({super.key, this.filter});

  /// 주소의 `type` 쿼리. null이거나 모르는 값이면 `all`.
  final String? filter;

  @override
  ConsumerState<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends ConsumerState<SessionsPage> {
  int _page = 1;

  String get _filter => normalizeSessionFilter(widget.filter);

  SessionsQuery get _query => SessionsQuery(_filter, _page);

  @override
  void didUpdateWidget(SessionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 필터가 바뀌면 처음 페이지부터 본다.
    if (normalizeSessionFilter(oldWidget.filter) != _filter) {
      _page = 1;
    }
  }

  /// 칩을 누를 때마다 브라우저 기록에 항목이 쌓이지 않도록 neglect로 감싸 쿼리만 바꾼다.
  void _selectFilter(String filter) {
    if (filter == _filter) {
      return;
    }
    Router.neglect(context, () => context.go('$_sessionsPath?type=$filter'));
  }

  void _changePage(int page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider(_query));

    return ListView(
      padding: kPagePadding,
      children: [
        Text(
          'Sessions',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        _FilterChips(selected: _filter, onSelected: _selectFilter),
        const SizedBox(height: 16),
        sessions.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '세션 목록을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(sessionsProvider(_query)),
          ),
          data: (data) => data.total == 0
              ? _EmptySessionsCard(filtered: _filter != kSessionFilterAll)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SessionsTable(items: data.items),
                    const SizedBox(height: 12),
                    PaginationBar(
                      page: data.page,
                      pageSize: data.pageSize,
                      total: data.total,
                      onPageChanged: _changePage,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: _filterSpacing,
      runSpacing: _filterSpacing,
      children: [
        for (final filter in kSessionFilters)
          ChoiceChip(
            label: Text(_filterLabels[filter]!),
            selected: filter == selected,
            onSelected: (_) => onSelected(filter),
          ),
      ],
    );
  }
}

/// 세션이 하나도 없을 때: 필터가 없으면 안내 + Telemetry App 링크, 필터가 있으면 조건 불일치 문구.
class _EmptySessionsCard extends StatelessWidget {
  const _EmptySessionsCard({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filtered ? _noMatchText : _guideText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              if (!filtered) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go(_telemetryAppPath),
                  child: const Text('Telemetry App'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionsTable extends StatelessWidget {
  const _SessionsTable({required this.items});

  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  final List<SessionSummary> items;

  @override
  Widget build(BuildContext context) {
    final headingStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.textMuted);

    return Card(
      // 좁은 화면에서는 표를 가로로 스크롤하고, 넓은 화면에서는 카드 폭을 채운다.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              headingTextStyle: headingStyle,
              headingRowHeight: _rowHeight,
              dataRowMinHeight: _rowHeight,
              dataRowMaxHeight: _rowHeight,
              columns: const [
                DataColumn(label: Text('날짜')),
                DataColumn(label: Text('트랙')),
                DataColumn(label: Text('세션')),
                DataColumn(label: Text('모드')),
                DataColumn(label: Text('결과')),
                DataColumn(label: Text('베스트 랩')),
                DataColumn(label: Text('점수')),
              ],
              rows: [
                for (final session in items)
                  DataRow(
                    onSelectChanged: (_) => context.go('$_sessionsPath/${session.sessionId}'),
                    cells: [
                      DataCell(Text(_dateFormat.format(session.classifiedAt.toLocal()))),
                      DataCell(Text(session.trackName)),
                      DataCell(Text(sessionKindLabel(session.sessionKind))),
                      DataCell(Text(gameModeLabel(session.gameMode))),
                      DataCell(_ResultCell(session: session)),
                      DataCell(Text(_bestLapText(session), style: _timeStyle)),
                      DataCell(Text(session.myPoints?.toString() ?? kNoValueText)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _bestLapText(SessionSummary session) {
    final bestLap = session.myBestLapTimeMs;
    return bestLap == null ? kNoValueText : formatLapTime(bestLap);
  }
}

/// `P4 / 22` + 출발 순위(`Grid P6`). 내 결과가 없으면 `-`.
class _ResultCell extends StatelessWidget {
  const _ResultCell({required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    final position = session.myPosition;
    if (position == null) {
      return const Text(kNoValueText);
    }
    final grid = session.myGridPosition;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('P$position / ${session.carCount}', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (grid != null && grid > 0) ...[
          const SizedBox(width: _gridGap),
          Text(
            'Grid P$grid',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}
