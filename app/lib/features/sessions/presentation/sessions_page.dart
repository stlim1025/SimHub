import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/menu_items.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/pagination_bar.dart';
import '../application/sessions_providers.dart';
import '../domain/session_display.dart';
import 'sessions_table.dart';

const String _sessionsPath = '/sessions';
const String _telemetryAppPath = '/telemetry-app';
const String _telemetryAppLabel = 'Telemetry App';

const String _title = 'All Sessions';
const String _filtersLabel = 'Filters';
const String _guideText = '결과 화면까지 마친 세션이 여기에 기록됩니다.';
const String _noMatchText = '이 조건에 맞는 세션이 없습니다.';

const double _titleGap = 12;
const double _menuFaceHeight = 32;
const double _menuFaceRadius = 6;
const double _menuIconSize = 18;
const EdgeInsets _menuFacePadding = EdgeInsets.only(left: 12, right: 6);

/// 필터 값 → 메뉴 글자(`kSessionFilters`와 같은 순서로 그린다).
const Map<String, String> kSessionFilterLabels = {
  kSessionFilterAll: 'All',
  kSessionFilterRace: 'Race',
  kSessionFilterQualifying: 'Qualifying',
  kSessionFilterPractice: 'Practice',
};

/// 내 세션 목록(docs/15 §11.2, F1Laps "All Sessions"). 필터는 주소의 `?type=`(모르는 값은 all), 페이지 번호는 화면 상태.
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

  /// 고를 때마다 브라우저 기록에 항목이 쌓이지 않도록 neglect로 감싸 쿼리만 바꾼다.
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
      padding: pagePadding(context),
      children: [
        Wrap(
          spacing: _titleGap,
          runSpacing: _titleGap,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            SessionFilterMenu(selected: _filter, onSelected: _selectFilter),
          ],
        ),
        const SizedBox(height: 16),
        sessions.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '세션 목록을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(sessionsProvider(_query)),
          ),
          data: (data) => data.total == 0
              ? _EmptySessions(filtered: _filter != kSessionFilterAll)
              : SessionsTable(
                  items: data.items,
                  footer: PaginationBar(
                    page: data.page,
                    pageSize: data.pageSize,
                    total: data.total,
                    onPageChanged: _changePage,
                  ),
                ),
        ),
      ],
    );
  }
}

/// `Filters ▾` 메뉴(세션 종류 하나 고르기). 전체가 아니면 `Filters: Race`처럼 보인다.
class SessionFilterMenu extends StatelessWidget {
  const SessionFilterMenu({super.key, required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = selected == kSessionFilterAll ? _filtersLabel : '$_filtersLabel: ${kSessionFilterLabels[selected]}';
    return PopupMenuButton<String>(
      key: const ValueKey('sessions-filter-menu'),
      tooltip: _filtersLabel,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final filter in kSessionFilters)
          CheckMenuItem<String>(value: filter, checked: filter == selected, label: kSessionFilterLabels[filter]!),
      ],
      child: Container(
        height: _menuFaceHeight,
        padding: _menuFacePadding,
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(_menuFaceRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            Icon(Icons.arrow_drop_down, size: _menuIconSize, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

/// 세션이 하나도 없을 때: 필터가 없으면 안내 + Telemetry App 링크, 필터가 있으면 조건 불일치 문구.
class _EmptySessions extends StatelessWidget {
  const _EmptySessions({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return filtered
        ? const EmptyStateCard(message: _noMatchText)
        : const EmptyStateCard(
            message: _guideText,
            actionLabel: _telemetryAppLabel,
            actionPath: _telemetryAppPath,
          );
  }
}
